//
//  AvatarAssessmentCanvas.swift
//  VoiceMiniCog
//
//  Root view for the avatar-guided assessment.
//  ONE unified canvas: content zone (left) + avatar zone (right).
//  Layout ratios are driven by AvatarLayoutManager per phase.
//

import SwiftUI
import os

private let canvasLog = Logger(subsystem: "com.mercycog.VoiceMiniCog", category: "Canvas")

// MARK: - AvatarAssessmentCanvas

struct AvatarAssessmentCanvas: View {

    let flowType: AssessmentFlowType
    let sessionID: UUID
    /// When false the canvas is in the hierarchy (keeping the WebView alive)
    /// but phase content is not rendered — prevents WelcomePhaseView.onAppear
    /// from firing the welcome echo before the user taps Start.
    var isActive: Bool
    /// When true and `isActive` is false, still pass Daily URL into the avatar zone so
    /// `TavusCVIView` stays mounted across Home → Start (avoids WKWebView teardown races).
    /// Must be false while another screen (e.g. caregiver) hosts its own `TavusCVIView`.
    var warmTavusWebViewOnHome: Bool = false
    @Bindable var assessmentState: AssessmentState
    var tavusService: TavusService
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    @State private var avatarDismissed = false
    @State private var isCancelling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth  = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // MARK: Layer 1 — Unified background gradient
                // Light content on left → dark avatar on right,
                // gradient stop animated with avatarWidthRatio.
                LinearGradient(
                    stops: [
                        .init(color: AssessmentTheme.Content.background, location: 0.0),
                        .init(
                            color: AssessmentTheme.Content.background,
                            location: 1.0 - layoutManager.avatarWidthRatio
                        ),
                        .init(color: AssessmentTheme.canvasDark, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.avatarWidthRatio)

                // MARK: Layer 2 — Content + Avatar HStack
                HStack(spacing: 0) {

                    // MARK: Content Zone (left) — only rendered when assessment is active.
                    // When isActive is false, the canvas is in the hierarchy (keeping the
                    // WebView alive for connection stability) but no phase views mount,
                    // so WelcomePhaseView.onAppear won't fire the welcome echo prematurely.
                    if isActive {
                        contentZone
                            .frame(width: contentWidth)
                    } else {
                        // Assessment not started — don't mount phase views.
                        // This prevents WelcomePhaseView.onAppear from firing
                        // the welcome echo before the user taps Start.
                        Color.clear
                            .frame(width: contentWidth)
                            .onAppear {
                                canvasLog.debug("Phase content suppressed — isActive=false, waiting for user to start assessment")
                            }
                    }

                    // MARK: Right Panel — avatar zone (always present, never swapped out)
                    avatarZone(width: avatarWidth, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .animation(
            reduceMotion ? AssessmentTheme.Anim.reducedMotion : AssessmentTheme.Anim.phaseTransition,
            value: layoutManager.currentPhase
        )
        .onChange(of: isActive) { _, active in
            // Only initialize the phase when the user explicitly starts.
            // The canvas onAppear fires at app launch (always in hierarchy)
            // — setting currentPhase there would prime WelcomePhaseView
            // before the user taps Start.
            if active {
                layoutManager.flowType = flowType
                layoutManager.currentPhase = .welcome
                isCancelling = false
                canvasLog.debug("Assessment started — phase set to .welcome")
            }
        }
        .onChange(of: flowType) { _, newFlow in
            // flowType is `let` on this view, so it only changes when the parent
            // reconstructs the canvas (i.e., a new session). Guard ensures no
            // accidental mid-session reset if SwiftUI re-evaluates the parent body.
            guard isActive else { return }
            layoutManager.flowType = newFlow
            layoutManager.currentPhase = .welcome
        }
        .onChange(of: sessionID) { _, _ in
            // New assessment started — reset dismissed state and cancel guard.
            // Skip phase reset when isActive also changed in the same render
            // cycle (the isActive handler already set .welcome).
            guard isActive else { return }
            if layoutManager.currentPhase != .welcome {
                layoutManager.flowType = flowType
                layoutManager.currentPhase = .welcome
            }
            avatarDismissed = false
            isCancelling = false
        }
    }

    // MARK: - Content Zone

    @ViewBuilder
    private var contentZone: some View {
        VStack(spacing: 0) {
            // Progress track — 60pt top padding for safe area.
            // No horizontal padding so the track spans the full content width.
            progressTrack
                .padding(.top, 60)

            // Phase-specific content — crossfade + subtle upward drift
            Group {
                phaseContent
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal: .opacity
                        )
                    )
                    .id(layoutManager.currentPhase)
                    .animation(
                        reduceMotion
                            ? AssessmentTheme.Anim.reducedMotion
                            : AssessmentTheme.Anim.contentSwap,
                        value: layoutManager.currentPhase
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            // End Session — clock drawing has its own button in the avatar zone.
            // Active testing phases (wordRegistration, wordRecall, verbalFluency)
            // hide the regular button to prevent accidental patient taps, but show
            // an examiner-only long-press exit so the clinician always has a way out.
            if layoutManager.currentPhase == .clockDrawing {
                // Avatar zone provides its own End Session button
            } else if [AssessmentPhaseID.wordRegistration, .wordRecall, .verbalFluency]
                .contains(layoutManager.currentPhase) {
                examinerLongPressExit
                    .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            } else {
                endSessionButton
                    .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Phase Content Switch

    @ViewBuilder
    private var phaseContent: some View {
        switch layoutManager.currentPhase {
        case .welcome:
            WelcomePhaseView(layoutManager: layoutManager, onGoToMainMenu: onCancel)
        case .qdrs:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .qdrs)
        case .phq2:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .phq2)
        case .orientation:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .orientation)
        case .wordRegistration:
            WordRegistrationPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .clockDrawing:
            ClockDrawingPhaseView(layoutManager: layoutManager, assessmentState: assessmentState)
        case .verbalFluency:
            VerbalFluencyPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .storyRecall:
            StoryRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .wordRecall:
            WordRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .completion:
            CompletionPhaseView(onComplete: onComplete)
        }
    }

    // MARK: - Progress Track

    private var progressTrack: some View {
        ProgressTrackView(layoutManager: layoutManager)
    }

    // MARK: - End Session Button

    private var endSessionButton: some View {
        Button {
            guard !isCancelling else { return }
            isCancelling = true
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.prepare()
            haptic.impactOccurred()
            onCancel()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                Text("End Session")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color(hex: "#DC2626"))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Examiner Long-Press Exit

    /// Subtle exit control for active testing phases where a regular button
    /// could be tapped accidentally by the patient. Requires a deliberate
    /// 2-second long press to trigger — examiner-only interaction.
    private var examinerLongPressExit: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12))
            Text("Hold to End Session")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color(hex: "#DC2626").opacity(0.5))
        .onLongPressGesture(minimumDuration: 2.0) {
            guard !isCancelling else { return }
            isCancelling = true
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.prepare()
            haptic.impactOccurred()
            onCancel()
        }
    }

    // MARK: - Avatar Zone

    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        // Mount TavusCVIView whenever we have a URL and (assessment active OR Home warm
        // path). Omit URL while an inactive canvas shares the session with another
        // screen that embeds its own `TavusCVIView` (e.g. caregiver).
        let roomURL: String? = {
            guard let u = tavusService.activeConversation?.conversation_url, !avatarDismissed else { return nil }
            if isActive { return u }
            if warmTavusWebViewOnHome { return u }
            return nil
        }()
        let deferDailyJoin = warmTavusWebViewOnHome && !isActive
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: roomURL, // avatarDismissed already handled in roomURL closure
            deferDailyRoomJoin: deferDailyJoin,
            isConnecting: avatarDismissed ? false : tavusService.isCreatingConversation,
            errorMessage: avatarDismissed ? nil : tavusService.lastError,
            width: width,
            height: height,
            onRetry: {
                Task {
                    do {
                        _ = try await tavusService.createConversation(
                            conversationName: TavusService.defaultConversationName()
                        )
                    } catch {
                        tavusService.lastError = error.localizedDescription
                    }
                }
            },
            onContinueWithoutAvatar: {
                avatarDismissed = true
                tavusService.lastError = nil
            },
            onDoneDrawing: {
                layoutManager.advanceToNextPhase()
            },
            onEndSession: {
                guard !isCancelling else { return }
                isCancelling = true
                onCancel()
            }
        )
        .frame(width: width, height: height)
    }
}

// MARK: - Preview

#Preview {
    // TavusService.shared is a singleton with private init — safe in previews
    // because no API calls fire unless preWarm() is explicitly called.
    AvatarAssessmentCanvas(
        flowType: .quick,
        sessionID: UUID(),
        isActive: true,
        warmTavusWebViewOnHome: false,
        assessmentState: AssessmentState(),
        tavusService: TavusService.shared,
        onComplete: {},
        onCancel: {}
    )
}

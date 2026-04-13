//
//  AvatarAssessmentCanvas.swift
//  VoiceMiniCog
//
//  Root view for the avatar-guided assessment.
//  ONE unified canvas: content zone (left) + avatar zone (right).
//  Layout ratios are driven by AvatarLayoutManager per phase.
//

import SwiftUI

// MARK: - AvatarAssessmentCanvas

struct AvatarAssessmentCanvas: View {

    let flowType: AssessmentFlowType
    let sessionID: UUID
    /// When false the canvas is in the hierarchy (keeping the WebView alive)
    /// but phase content is not rendered — prevents WelcomePhaseView.onAppear
    /// from firing the welcome echo before the user taps Start.
    var isActive: Bool
    @Bindable var assessmentState: AssessmentState
    var tavusService: TavusService
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    // Pause sheet removed — End Session button replaces it
    @State private var avatarDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth  = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // MARK: Layer 1 — Unified background gradient
                // Light #F8F9FA on left → dark #080808 on right,
                // gradient stop animated with avatarWidthRatio.
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                        .init(
                            color: Color(hex: "#F8F9FA"),
                            location: 1.0 - layoutManager.avatarWidthRatio
                        ),
                        .init(color: Color(hex: "#080808"), location: 1.0)
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
                                print("[Canvas] Phase content SUPPRESSED — isActive=false, waiting for user to start assessment")
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
                print("[Canvas] Assessment STARTED — phase set to .welcome")
            }
        }
        .onChange(of: flowType) { _, newFlow in
            guard isActive else { return }
            layoutManager.flowType = newFlow
            layoutManager.currentPhase = .welcome
        }
        .onChange(of: sessionID) { _, _ in
            // New assessment started — reset to welcome regardless of flow type.
            // Only act if isActive, otherwise this is just a UUID refresh at init.
            guard isActive else { return }
            layoutManager.flowType = flowType
            layoutManager.currentPhase = .welcome
            avatarDismissed = false
        }
    }

    // MARK: - Content Zone

    @ViewBuilder
    private var contentZone: some View {
        VStack(spacing: 0) {
            // Progress track — 60pt top padding for safe area
            progressTrackPlaceholder
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

            // End Session — hidden during phases where it lives on the avatar/clinician panel only.
            if ![AssessmentPhaseID.clockDrawing, .wordRegistration, .wordRecall, .verbalFluency]
                .contains(layoutManager.currentPhase) {
                endSessionButton
            }
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
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

    private var progressTrackPlaceholder: some View {
        ProgressTrackView(layoutManager: layoutManager)
    }

    // MARK: - End Session Button

    private var endSessionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - Avatar Zone

    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        // Only hand the Daily URL to the WebView while this canvas is the active
        // screen. Pre-warm may fill `activeConversation` on Home — if we passed
        // the URL while `isActive` is false, TavusCVIView would join immediately
        // and the replica often speaks before the user taps Start.
        let roomURL = isActive ? tavusService.activeConversation?.conversation_url : nil
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: avatarDismissed ? nil : roomURL,
            isConnecting: avatarDismissed ? false : tavusService.isCreatingConversation,
            errorMessage: avatarDismissed ? nil : tavusService.lastError,
            width: width,
            height: height,
            onRetry: {
                Task {
                    do {
                        _ = try await tavusService.createConversation(
                            conversationName: "MercyCog Assessment \(Date().formatted(date: .abbreviated, time: .shortened))"
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
            onEndSession: onCancel
        )
        .frame(width: width, height: height)
    }
}

// MARK: - Preview

#Preview {
    AvatarAssessmentCanvas(
        flowType: .quick,
        sessionID: UUID(),
        isActive: true,
        assessmentState: AssessmentState(),
        tavusService: TavusService.shared,
        onComplete: {},
        onCancel: {}
    )
}

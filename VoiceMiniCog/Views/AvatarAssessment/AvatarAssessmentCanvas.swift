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
    /// DailyCallManager for native Daily SDK integration.
    var dailyCallManager: DailyCallManager
    @Bindable var assessmentState: AssessmentState
    var tavusService: TavusService
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    @State private var avatarDismissed = false
    @State private var isCancelling = false
    /// Confirmation alert shown when the clinician taps "Done Drawing" with
    /// zero strokes on the canvas. Prevents accidental blank submissions.
    @State private var showNoStrokesAlert = false
    /// Confirmation alert for the End Session button — prevents accidental
    /// mid-assessment aborts.
    @State private var showEndSessionConfirm = false
    /// Accent color of the phase that just exited — drives the celebratory
    /// checkmark so the color matches the completed phase, not the incoming one.
    @State private var completedPhaseAccent: Color = .clear
    @State private var showCompletionCheck: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth  = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth
            let accent = layoutManager.accentColor

            ZStack {
                // MARK: Layer 1 — Unified breathing canvas
                // ONE continuous surface that both panes sit on. A neutral
                // warm base + a soft radial tint in the current phase accent
                // at 4–6% opacity. No hard left/right split; no stark white.
                unifiedCanvasBackground(accent: accent, size: geo.size)
                    .ignoresSafeArea()

                // MARK: Layer 2 — Content + Avatar HStack
                HStack(spacing: 0) {

                    // Content Zone (left) — only rendered when assessment is active.
                    if isActive {
                        contentZone
                            .frame(width: contentWidth)
                    } else {
                        Color.clear
                            .frame(width: contentWidth)
                            .onAppear {
                                canvasLog.debug("Phase content suppressed — isActive=false, waiting for user to start assessment")
                            }
                    }

                    // Right Panel — avatar zone (always present, never swapped out)
                    avatarZone(width: avatarWidth, height: geo.size.height)
                }

                // Layer 3 removed — no visible divider between panes.

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
            if active {
                layoutManager.flowType = flowType
                layoutManager.currentPhase = .welcome
                isCancelling = false
                canvasLog.debug("Assessment started — phase set to .welcome")

                // Daily SDK: unlock deferred join and attempt join now.
                // configure() was already called when the URL became available.
                dailyCallManager.deferJoinUntilAssessmentActive = false
                if let url = tavusService.activeConversation?.conversation_url {
                    dailyCallManager.configure(url: url)
                }
                dailyCallManager.joinIfReady()
            }
        }
        .onChange(of: tavusService.activeConversation?.conversation_url) { _, url in
            // URL becomes available — configure and always attempt join.
            // DailyCallManager's deferJoinUntilAssessmentActive flag gates whether
            // the join actually proceeds (true on Home, false once isActive fires).
            if let url {
                dailyCallManager.configure(url: url)
                dailyCallManager.joinIfReady()
                canvasLog.debug("URL arrived — configured + joinIfReady (isActive=\(isActive))")
            }
        }
        // Phase-completion checkmark — shown briefly as a phase transitions
        // out so each section gets a satisfying close.
        .overlay {
            if showCompletionCheck {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    PhaseCompletionCheckmark(
                        accentColor: completedPhaseAccent,
                        isVisible: showCompletionCheck
                    )
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onChange(of: layoutManager.currentPhase) { oldPhase, newPhase in
            // Suppress the check on initial entry (welcome appears on load)
            // and on exiting into the completion phase (its own screen handles the moment).
            guard oldPhase != newPhase,
                  oldPhase != .welcome,
                  newPhase != .welcome,
                  newPhase != .completion
            else { return }
            completedPhaseAccent = AssessmentTheme.accent(for: oldPhase.rawValue)
            withAnimation(AssessmentTheme.Motion.contentFade) {
                showCompletionCheck = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation(AssessmentTheme.Motion.contentFade) {
                    showCompletionCheck = false
                }
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

    // MARK: - Unified canvas helpers

    /// Warm neutral canvas base + a full-bleed 6% phase accent wash.
    /// Both panes (content + avatar) sit on this single surface. The
    /// wash cross-fades on phase change over 0.6s easeInOut so the
    /// whole room appears to gently shift lighting.
    @ViewBuilder
    private func unifiedCanvasBackground(accent: Color, size: CGSize) -> some View {
        ZStack {
            AssessmentTheme.canvasBase
            AssessmentTheme.tint(for: layoutManager.currentPhase.rawValue)
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.6),
                    value: layoutManager.currentPhase
                )
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

            // Phase-specific content — coordinated enter/exit + subtle
            // accent wash. Avatar layout reflow is animated by the parent
            // gradient / width binding (phaseTransition) so the two move
            // together.
            PhaseTransitionContainer(
                phase: layoutManager.currentPhase,
                accentColor: layoutManager.accentColor
            ) {
                phaseContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            // Bottom controls — ghost Main Menu (welcome only) + pill End
            // Session with confirmation. Active testing phases render an
            // examiner long-press exit instead so the patient can't tap.
            bottomControls
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .padding(.bottom, 40)
        }
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
            CompletionPhaseView(onComplete: onComplete, assessmentState: assessmentState)
        }
    }

    // MARK: - Progress Track

    private var progressTrack: some View {
        ProgressTrackView(layoutManager: layoutManager)
    }

    // MARK: - Bottom Controls

    /// Ghost "Main Menu" (welcome only) + soft destructive "End Session"
    /// with confirmation. Active testing phases render an examiner long-
    /// press exit instead so the patient can't accidentally abort.
    @ViewBuilder
    private var bottomControls: some View {
        // Word Registration, Word Recall, and Orientation all use the
        // standard ghost pill (consistent visual language across phases).
        // Only Verbal Fluency keeps the examiner long-press exit since
        // its 60s countdown is easy to break accidentally.
        let isActiveTesting = [AssessmentPhaseID.verbalFluency]
            .contains(layoutManager.currentPhase)
        let isClockPhase = layoutManager.currentPhase == .clockDrawing

        if isClockPhase {
            // Avatar zone provides its own End Session button during clock.
            EmptyView()
        } else if isActiveTesting {
            examinerLongPressExit
        } else {
            HStack(spacing: 14) {
                if layoutManager.currentPhase == .welcome {
                    mainMenuButton
                }
                endSessionPill
            }
            .frame(maxWidth: .infinity)
            .confirmationDialog(
                "End this session?",
                isPresented: $showEndSessionConfirm,
                titleVisibility: .visible
            ) {
                Button("End Session", role: .destructive) {
                    performEndSession()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can always restart the assessment from the beginning.")
            }
        }
    }

    /// Ghost button — rounded rect, 1pt border, no fill. Label "← Main Menu".
    private var mainMenuButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.prepare(); haptic.impactOccurred()
            onCancel()
        } label: {
            Text("← Main Menu")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Soft destructive pill — .red.opacity(0.08) bg, red label + xmark.circle.
    /// Opens a confirmation dialog before actually ending.
    private var endSessionPill: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.prepare(); haptic.impactOccurred()
            showEndSessionConfirm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text("End Session")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    /// Examiner long-press exit during active testing phases. Same visual
    /// language as the End Session pill (soft red) but requires a 2s hold
    /// so the patient can't trigger it by accident.
    private var examinerLongPressExit: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 12, weight: .semibold))
            Text("Hold to End Session")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color.red.opacity(0.65))
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(0.05))
        )
        .frame(maxWidth: .infinity)
        .onLongPressGesture(minimumDuration: 2.0) {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.prepare(); haptic.impactOccurred()
            performEndSession()
        }
    }

    private func performEndSession() {
        guard !isCancelling else { return }
        isCancelling = true
        onCancel()
    }

    // MARK: - Avatar Zone

    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        // Pass conversation URL for UI state (connecting spinner vs video).
        // DailyCallManager handles join/leave lifecycle separately.
        let roomURL: String? = {
            guard let u = tavusService.activeConversation?.conversation_url, !avatarDismissed else { return nil }
            return u
        }()
        // Sync failures no longer block conversation creation (best-effort
        // sync); only surface `lastError` which tracks genuine conversation-
        // creation or network failures. `voiceIsolationSyncState` is still
        // observable for any scoring-phase gate that wants it.
        let canvasErrorMessage: String? = avatarDismissed ? nil : tavusService.lastError

        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: roomURL,
            dailyCallManager: dailyCallManager,
            isConnecting: avatarDismissed ? false : tavusService.isCreatingConversation,
            errorMessage: canvasErrorMessage,
            width: width,
            height: height,
            onRetry: {
                // User-initiated retry: clear cooldown + last-error and run a
                // fresh conversation. `createConversation` awaits the hard-gate
                // via `ensurePersonaSyncVerified(bypassCooldown: true)` — but
                // createConversation itself doesn't know about the bypass,
                // so we invalidate the cooldown here first.
                tavusService.invalidateSyncCooldown()
                tavusService.lastError = nil
                Task {
                    do {
                        print("[Tavus.lifecycle] retry tapped — origin=welcome-retry")
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
                // Fix 14: confirm if zero strokes before advancing.
                if assessmentState.qmciState.clockStrokeEvents.isEmpty {
                    showNoStrokesAlert = true
                } else {
                    layoutManager.advanceToNextPhase()
                }
            },
            onEndSession: {
                guard !isCancelling else { return }
                isCancelling = true
                onCancel()
            }
        )
        .frame(width: width, height: height)
        .alert("No Drawing Detected", isPresented: $showNoStrokesAlert) {
            Button("Continue Drawing", role: .cancel) { }
            Button("Skip Clock Drawing", role: .destructive) {
                layoutManager.advanceToNextPhase()
            }
        } message: {
            Text("The patient hasn't drawn anything yet. Are you sure you want to skip the clock drawing test?")
        }
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
        dailyCallManager: DailyCallManager(),
        assessmentState: AssessmentState(),
        tavusService: TavusService.shared,
        onComplete: {},
        onCancel: {}
    )
}

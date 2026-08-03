//
//  VerbalFluencyPhaseView.swift
//  VoiceMiniCog
//
//  Phase 7 — Verbal Fluency (60-second animal naming).
//
//  CLINICAL-UI: Patient panel shows only the category label "Animals",
//  a countdown ring, and a live "X named" count. The actual words named
//  are NOT displayed — showing them would create recognition cues and
//  contaminate cluster/switch analysis.
//
//  No buttons on patient panel. Timer starts automatically when the
//  avatar finishes saying "Go." Avatar stays silent for the full 60s.
//

import SwiftUI
import Combine

// MARK: - VerbalFluencyPhaseView

struct VerbalFluencyPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    let qmciState: QmciState

    private enum PhaseMode {
        case prompting  // Avatar delivering instructions
        case timing     // 60-second countdown active
        case done       // Time's up, closing
    }

    @State private var mode: PhaseMode = .prompting
    @State private var timeRemaining: Int = 60
    @State private var timerActive = false
    @State private var contentVisible = false
    @State private var didFinish = false
    @State private var timingBegan = false
    @State private var hasStarted = false

    // Scoring
    @StateObject private var scorer = VerbalFluencyScorer()
    @StateObject private var speech = SpeechService()
    @State private var didRequestAuth = false

    // Timing
    @State private var phaseStartTime = Date()
    @State private var timerStartTime: Date? = nil
    @State private var speechEpoch = 0
    @State private var closingUtteranceEpoch = 0

    // Re-prompt tracking
    @State private var rePromptUsed = false
    @State private var hasTranscriptActivity = false
    @State private var rePromptUnmuteWork: DispatchWorkItem?

    // Cancellable fallback dispatches
    @State private var promptFallbackWork: DispatchWorkItem?
    @State private var closingFallbackWork: DispatchWorkItem?
    /// One-shot guard: once the closing utterance has advanced us to the
    /// next phase (either via avatarDoneSpeaking or the fallback), never
    /// let the *other* path fire a second advance. Without this guard the
    /// notification path advances into Story Recall, the fallback fires
    /// ~6s later, and advances Story Recall → Completion mid-intro.
    @State private var didAdvanceAfterClosing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            // Phase name rendered by the chevron track — no header badge.
            Spacer()

            // MARK: Speech Bubble Icon (64pt)
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: "Animals" category pill — warm regularMaterial badge
            animalsPillBadge
                .padding(.bottom, 28)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // MARK: Countdown Ring
            countdownRing
                .frame(width: 180, height: 180)
                .padding(.bottom, 20)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)
                .accessibilityLabel("Time remaining: \(timeRemaining) seconds")
                .accessibilityAddTraits(.updatesFrequently)

            // MARK: Live Count — numberPop on each increment
            if mode == .timing || mode == .done {
                HStack(spacing: 6) {
                    Text("\(scorer.count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(layoutManager.accentColor)
                        .contentTransition(.numericText(value: Double(scorer.count)))
                        .motionSafe(AssessmentTheme.Motion.numberPop, value: scorer.count)
                    Text("named")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(AssessmentTheme.Content.textSecondary)
                }
                .transition(.opacity)
            }

            Spacer()
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            avatarInterrupt()
            avatarSetAssessmentPhaseType(.verbalFluency)
            avatarBeginSilenceWatch()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            phaseStartTime = Date()
            avatarSetAssessmentContext(QMCIAvatarContext.verbalFluency)
            Task {
                if !didRequestAuth {
                    _ = await speech.requestAuthorization()
                    didRequestAuth = true
                }
            }
            startPrompt()
            // Delay accessibility post until layout completes — posting
            // synchronously in onAppear targets the previous view's focused element.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIAccessibility.post(notification: .screenChanged, argument: "Verbal fluency. Listen to the question and answer aloud.")
            }
        }
        .onDisappear {
            timerActive = false
            speech.stopListening()
            rePromptUnmuteWork?.cancel()
            rePromptUnmuteWork = nil
            promptFallbackWork?.cancel()
            promptFallbackWork = nil
            closingFallbackWork?.cancel()
            closingFallbackWork = nil
            // Only persist if timing actually began (not during prompt delivery)
            if timingBegan && !didFinish { persistTelemetry() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            if mode == .prompting {
                // Prompt finished — begin the 60-second test.
                // The fallback dispatch also calls beginTiming(); the guard
                // inside beginTiming() prevents the second call from doing
                // anything if both fire.
                beginTiming()
            } else if mode == .done, closingUtteranceEpoch > 0 {
                // Closing utterance finished — advance once. Cancel the
                // fallback so it can't double-fire into Completion.
                guard !didAdvanceAfterClosing else { return }
                didAdvanceAfterClosing = true
                closingFallbackWork?.cancel()
                closingFallbackWork = nil
                layoutManager.advanceToNextPhase()
            }
        }
        .onChange(of: speech.transcript) { _, newTranscript in
            guard mode == .timing else { return }
            hasTranscriptActivity = true
            scorer.processTranscript(newTranscript)
        }
        .onReceive(
            Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
        ) { _ in
            guard timerActive, mode == .timing else { return }
            timeRemaining -= 1
            if timeRemaining <= 0 {
                finishFluency()
            } else {
                // Mid-phase silence reinforcement at the 30-second mark
                if timeRemaining == 30 {
                    avatarSetAssessmentContext(QMCIAvatarContext.verbalFluencyMidpoint)
                }
                checkRePrompt()
            }
        }
    }

    // MARK: - Countdown Ring

    @ViewBuilder
    private var countdownRing: some View {
        let progress = Double(timeRemaining) / 60.0
        let warningMode = timeRemaining <= 15
        let ringColor: Color = warningMode ? Color(hex: "#F59E0B") : layoutManager.accentColor

        ZStack {
            // Background track — thicker (6pt per brief, bumped to match new 8pt visual weight)
            Circle()
                .stroke(Color.gray.opacity(0.14), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // Active fill — 10pt, accent color, smooth countdown sweep
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.35), radius: 8, y: 0)
                .motionSafe(.linear(duration: 1), value: timeRemaining)

            // Center stack — seconds with numberPop on each tick, label below
            VStack(spacing: 2) {
                Text("\(timeRemaining)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(ringColor)
                    .contentTransition(.numericText(value: Double(timeRemaining)))
                    .scaleEffect(scaleForSecondsTick)
                    .motionSafe(AssessmentTheme.Motion.numberPop, value: timeRemaining)

                if mode == .timing {
                    Text("seconds")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AssessmentTheme.Content.textSecondary)
                }
            }
        }
    }

    /// 1.0 → 1.15 → 1.0 pulse, driven implicitly by numberPop via scaleEffect
    /// that toggles with each tick. Parity ensures the bounce lands each second.
    private var scaleForSecondsTick: CGFloat {
        reduceMotion ? 1.0 : (timeRemaining.isMultiple(of: 2) ? 1.0 : 1.08)
    }

    // MARK: - Animals pill badge

    @ViewBuilder
    private var animalsPillBadge: some View {
        let shape = Capsule()
        HStack(spacing: 10) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(layoutManager.accentColor)
            Text(LeftPaneSpeechCopy.verbalFluencyTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .assessmentGlass(in: shape, tint: layoutManager.accentColor, prominence: .regular)
        .overlay(shape.stroke(layoutManager.accentColor.opacity(0.18), lineWidth: 1))
        .assessmentShadow(AssessmentTheme.Depth.cardResting)
    }

    // MARK: - Prompt

    private func startPrompt() {
        guard !hasStarted else { return }
        hasStarted = true
        speechEpoch += 1
        let epoch = speechEpoch

        // 500ms settle, then avatar speaks the prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.speechEpoch == epoch else { return }
            avatarSpeak(LeftPaneSpeechCopy.verbalFluencyPrompt)
            layoutManager.setAvatarSpeaking()
        }

        // Fallback: if avatarDoneSpeaking never fires, begin timing after estimated TTS
        let wc = LeftPaneSpeechCopy.verbalFluencyPrompt.split(separator: " ").count
        let fallback = max(12.0, Double(wc) * 0.45 + 6.0)
        promptFallbackWork?.cancel()
        let pfWork = DispatchWorkItem { [self] in
            guard self.speechEpoch == epoch, self.mode == .prompting else { return }
            self.beginTiming()
        }
        promptFallbackWork = pfWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + fallback, execute: pfWork)
    }

    // MARK: - Timing

    private func beginTiming() {
        guard mode == .prompting else { return }
        timingBegan = true

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .timing
        }
        layoutManager.setAvatarListening()
        timerStartTime = Date()
        hasTranscriptActivity = false

        // Start ASR
        scorer.startScoring()
        speech.transcript = ""
        Task {
            do {
                try await speech.startListening()
            } catch {
                // Simulator or unauthorized — timer still runs
            }
        }

        timerActive = true
    }

    // MARK: - Re-Prompt

    private func checkRePrompt() {
        guard !rePromptUsed, mode == .timing else { return }
        guard let start = timerStartTime else { return }

        // Re-prompt fires only if 15 seconds elapsed AND the patient has
        // not produced ANY transcript activity since timing began.
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= 15, !hasTranscriptActivity {
            rePromptUsed = true
            // Mute patient mic during re-prompt to prevent avatar voice
            // from being captured by ASR.
            avatarSetMicMuted(true)
            avatarSpeak(LeftPaneSpeechCopy.verbalFluencyRePrompt)
            // Unmute after re-prompt delivery and return to listening.
            // Cancellable to prevent cross-phase audio contamination if
            // finishFluency completes before the 3s delay elapses.
            rePromptUnmuteWork?.cancel()
            let work = DispatchWorkItem { [self] in
                guard !self.didFinish else { return }
                guard self.mode == .timing else { return }
                // DailyCallManager unmutes on re-prompt replica.stopped_speaking.
                self.layoutManager.setAvatarListening()
            }
            rePromptUnmuteWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }

    // MARK: - Finish

    private func finishFluency() {
        guard mode == .timing else { return }
        didFinish = true

        rePromptUnmuteWork?.cancel()
        rePromptUnmuteWork = nil
        timerActive = false
        speech.stopListening()

        // Process the final cleaned-up transcript before persisting — ASR
        // may emit a more accurate version after stopListening().
        scorer.processTranscript(speech.transcript)

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .done
        }

        // Persist scored words
        qmciState.verbalFluencyWords = scorer.validAnimals
        qmciState.verbalFluencyTranscript = speech.transcript
        qmciState.fluencyAnimalsNamed = scorer.allWordsInOrder

        persistTelemetry()

        closingUtteranceEpoch += 1
        avatarSpeak(LeftPaneSpeechCopy.verbalFluencyClose)
        layoutManager.setAvatarSpeaking()

        // Primary advance: avatarDoneSpeaking notification (handled in onReceive).
        // Fallback: if notification never fires, advance after estimated TTS duration.
        let epoch = closingUtteranceEpoch
        let wc = LeftPaneSpeechCopy.verbalFluencyClose.split(separator: " ").count
        let fallback = max(4.0, Double(wc) * 0.45 + 2.0)
        closingFallbackWork?.cancel()
        let cfWork = DispatchWorkItem { [self] in
            guard self.closingUtteranceEpoch == epoch,
                  self.mode == .done,
                  !self.didAdvanceAfterClosing else { return }
            self.didAdvanceAfterClosing = true
            layoutManager.advanceToNextPhase()
        }
        closingFallbackWork = cfWork
        DispatchQueue.main.asyncAfter(deadline: .now() + fallback, execute: cfWork)
    }

    // MARK: - Telemetry Persistence

    private func persistTelemetry() {
        qmciState.fluencyRepetitions = scorer.repetitions
        qmciState.fluencyIntrusions = scorer.intrusions
        qmciState.fluencySuperordinateCount = scorer.superordinateCount
        qmciState.fluencyFirstWordLatency = scorer.firstWordLatency
        qmciState.fluencyMeanInterWordInterval = scorer.meanInterWordInterval
        qmciState.fluencyQuartileCounts = scorer.quartileCounts
        qmciState.fluencyMeanClusterSize = scorer.meanClusterSize
        qmciState.fluencySwitchCount = scorer.switchCount
        qmciState.fluencyRePromptUsed = rePromptUsed
        // Measure from timer start (patient-active duration), not view appearance
        if let start = timerStartTime {
            qmciState.fluencyPhaseDuration = Date().timeIntervalSince(start)
        }
    }
}

// MARK: - Preview

#Preview {
    VerbalFluencyPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: QmciState()
    )
    .background(AssessmentTheme.Content.background)
}

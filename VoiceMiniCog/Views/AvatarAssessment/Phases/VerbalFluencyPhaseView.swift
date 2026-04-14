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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

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

            // MARK: "Animals" Heading
            Text(LeftPaneSpeechCopy.verbalFluencyTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
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

            // MARK: Live Count
            if mode == .timing || mode == .done {
                Text("\(scorer.count) named")
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scorer.count)
                    .transition(.opacity)
            }

            Spacer()
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            avatarInterrupt()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            phaseStartTime = Date()
            avatarSetAssessmentContext(
                "You are a clinical neuropsychologist administering the QMCI Verbal Fluency subtest. " +
                "Read the prompt exactly as provided. After saying 'Go', remain completely silent for 60 seconds. " +
                "Do not react to what the patient says. Do not nod, acknowledge, or provide any feedback. " +
                "Do not count animals or comment on the patient's performance. " +
                "Speak only when sent echo commands."
            )
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
                // Closing utterance finished — advance. The epoch check
                // prevents a stale prompt notification from triggering
                // advance mid-test (closingUtteranceEpoch is 0 until
                // finishFluency sets it).
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
                checkRePrompt()
            }
        }
    }

    // MARK: - Countdown Ring

    @ViewBuilder
    private var countdownRing: some View {
        let progress = Double(timeRemaining) / 60.0
        let ringColor = timeRemaining <= 15 ? Color(hex: "#F59E0B") : Color(hex: "#6B7280")

        ZStack {
            // Background track
            Circle()
                .stroke(Color.gray.opacity(0.12), lineWidth: 8)

            if reduceMotion {
                // Static ring — no animation for reduced motion
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                // Animated sweep
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
            }

            // Center: remaining seconds
            VStack(spacing: 2) {
                Text("\(timeRemaining)")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(ringColor)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 1), value: timeRemaining)

                if mode == .timing {
                    Text("seconds")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AssessmentTheme.Content.textSecondary)
                }
            }
        }
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
                avatarSetMicMuted(false)
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
            guard self.closingUtteranceEpoch == epoch, self.mode == .done else { return }
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

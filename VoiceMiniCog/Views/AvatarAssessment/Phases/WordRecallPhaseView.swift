//
//  WordRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 5 — Delayed Word Recall (QMCI subtest 4, 20 pts).
//
//  Fully automated via ASR. The patient screen shows NO target words —
//  only a brain icon, calming subtitle, and 5 progress circles that fill
//  as words are detected. The avatar delivers the standardized recall
//  prompt and listens for responses.
//
//  Auto-advance rules:
//    • 60s silence → "Any others?" follow-up
//    • 30s silence after follow-up → advance
//    • All 5 words recalled → 10s grace period → advance
//    • 150s hard ceiling → advance with whatever was captured
//    • Completion phrase ("I'm done", "that's all") → follow-up
//
//  MARK: CLINICAL — No target words are shown on patient screen.
//  This preserves free-recall construct validity.
//

import SwiftUI
import Speech

// MARK: - WordRecallPhaseView

struct WordRecallPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @ObservedObject var qmciState: QmciState

    @State private var scorer: WordRecallScorer
    @State private var phase: RecallPhase = .promptDelivery
    @State private var contentVisible = false
    @State private var recallPromptSpeechEpoch = 0
    @State private var recallPromptListeningUnlocked = false

    // Timer state
    @State private var silenceSeconds: TimeInterval = 0
    @State private var hardCeilingElapsed: TimeInterval = 0
    @State private var timerActive = false

    // Speech recognition
    @State private var speechService = SpeechService()
    @State private var lastTranscriptLength = 0

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Phase State Machine

    enum RecallPhase {
        case promptDelivery   // Avatar speaking the recall prompt
        case listening        // Listening for patient's recall
        case followUp         // "Any others?" delivered, listening again
        case done             // Scoring complete, advancing
    }

    // MARK: Constants

    private let silenceBeforeFollowUp: TimeInterval = 60
    private let silenceAfterFollowUp: TimeInterval = 30
    private let allRecalledGracePeriod: TimeInterval = 10
    private let hardCeiling: TimeInterval = 150

    // MARK: Init

    init(
        layoutManager: AvatarLayoutManager,
        qmciState: QmciState
    ) {
        self.layoutManager = layoutManager
        self.qmciState = qmciState
        _scorer = State(initialValue: WordRecallScorer(targetWords: qmciState.registrationWords))
    }

    // MARK: Computed

    private var targetCount: Int { qmciState.registrationWords.count }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Brain Icon
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 18)
                .assessmentIconHeaderAccent(layoutManager.accentColor)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: Title
            Text(LeftPaneSpeechCopy.delayedRecallTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // MARK: Subtitle (non-cueing)
            Text(LeftPaneSpeechCopy.delayedRecallPatientSubtitle)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .padding(.bottom, 40)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            // MARK: Progress Circles
            progressCircles
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word recall. Listen to the question and answer aloud.")
        .onAppear(perform: onPhaseAppear)
        .onDisappear(perform: onPhaseDisappear)
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            handleAvatarDoneSpeaking()
        }
        .onChange(of: speechService.transcript) { _, newTranscript in
            handleTranscriptUpdate(newTranscript)
        }
        .task(id: timerActive) {
            guard timerActive else { return }
            await runTimerLoop()
        }
    }

    // MARK: - Progress Circles

    private var progressCircles: some View {
        HStack(spacing: 16) {
            ForEach(0..<targetCount, id: \.self) { index in
                progressCircle(filled: index < scorer.recalledCount)
            }
        }
    }

    private func progressCircle(filled: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    filled ? Color(hex: "#34C759") : Color.gray.opacity(0.25),
                    lineWidth: 2
                )
                .frame(width: 28, height: 28)

            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "#34C759"))
                    .scaleEffect(reduceMotion ? 1.0 : 1.0)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.5).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion
                ? AssessmentTheme.Anim.reducedMotion
                : .spring(response: 0.4, dampingFraction: 0.7),
            value: filled
        )
        .accessibilityHidden(true) // Don't reveal progress count audibly
    }

    // MARK: - Phase Lifecycle

    private func onPhaseAppear() {
        withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
            contentVisible = true
        }

        // Set avatar context for this phase
        avatarSetContext(
            "You are administering delayed word recall. Speak only the echo text supplied by the app. " +
            LeftPaneSpeechCopy.examinerNeverCorrectPatient
        )

        // Timer loop starts via .task(id: timerActive) when timerActive becomes true

        // Deliver the recall prompt via avatar after a 500ms settle delay
        recallPromptSpeechEpoch += 1
        let epoch = recallPromptSpeechEpoch
        recallPromptListeningUnlocked = false
        layoutManager.setAvatarSpeaking()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            avatarSpeak(LeftPaneSpeechCopy.delayedRecallPrompt)
        }

        // Fallback: unlock listening after estimated speech duration
        let wc = LeftPaneSpeechCopy.delayedRecallPrompt.split(separator: " ").count
        let fallback = max(12.0, Double(wc) * 0.35 + 5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + fallback) {
            unlockListeningIfNeeded(epoch: epoch)
        }
    }

    private func onPhaseDisappear() {
        timerActive = false
        speechService.stopListening()
        persistResults()
    }

    // MARK: - Avatar Event Handling

    private func handleAvatarDoneSpeaking() {
        guard phase == .promptDelivery || phase == .followUp else { return }
        unlockListeningIfNeeded(epoch: recallPromptSpeechEpoch)
    }

    private func unlockListeningIfNeeded(epoch: Int) {
        guard epoch == recallPromptSpeechEpoch else { return }
        guard !recallPromptListeningUnlocked else { return }
        recallPromptListeningUnlocked = true

        scorer.promptEndTime = Date()
        layoutManager.setAvatarListening()

        if phase == .promptDelivery {
            phase = .listening
        }

        // Start speech recognition
        startSpeechRecognition()

        // Start the timer loop (silence + hard ceiling + grace)
        resetSilenceTimer()
        timerActive = true
    }

    // MARK: - Speech Recognition

    private func startSpeechRecognition() {
        // Check authorization first
        Task {
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                // Microphone denied — flag for clinician review and continue
                print("[WordRecall] Speech recognition not authorized — falling back to manual")
                return
            }
            do {
                try await speechService.startListening()
            } catch {
                print("[WordRecall] Failed to start speech recognition: \(error)")
            }
        }
    }

    // MARK: - Transcript Processing

    private func handleTranscriptUpdate(_ transcript: String) {
        guard !transcript.isEmpty else { return }

        // Only process new content
        guard transcript.count > lastTranscriptLength else { return }
        lastTranscriptLength = transcript.count

        // Feed to scorer
        let previousCount = scorer.recalledCount
        scorer.processTranscript(transcript)

        // Reset silence timer on new speech
        resetSilenceTimer()

        // Check for completion phrase
        if scorer.containsCompletionPhrase(transcript) {
            handleCompletionPhrase()
            return
        }

        // All-recalled grace period is handled by the timer loop
    }

    // MARK: - Completion Logic

    private func handleCompletionPhrase() {
        guard phase == .listening else { return }
        // Patient said "I'm done" etc. → deliver follow-up
        deliverFollowUp()
    }

    private func deliverFollowUp() {
        guard phase == .listening, !scorer.anyOthersPromptUsed else {
            // Already asked, or not in listening → advance
            advancePhase()
            return
        }

        scorer.markAnyOthersPromptUsed()
        scorer.silenceBeforePromptMs = Int(silenceSeconds * 1000)
        phase = .followUp

        layoutManager.setAvatarSpeaking()
        avatarSpeak(LeftPaneSpeechCopy.delayedRecallAnyOthers)

        // After avatar finishes, resume listening with shorter silence threshold
        recallPromptSpeechEpoch += 1
        let epoch = recallPromptSpeechEpoch
        recallPromptListeningUnlocked = false

        let fallback: Double = 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + fallback) {
            guard epoch == self.recallPromptSpeechEpoch else { return }
            guard !self.recallPromptListeningUnlocked else { return }
            self.recallPromptListeningUnlocked = true
            self.layoutManager.setAvatarListening()
            self.resetSilenceTimer()
        }
    }

    // MARK: - Timer Loop (structured concurrency, avoids @Sendable closure issues)

    /// Single async loop handling silence detection, hard ceiling, and grace period.
    /// Runs as a `.task(id: timerActive)` — cancels automatically on phase exit.
    private func runTimerLoop() async {
        while !Task.isCancelled && phase != .done {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { break }

            // Hard ceiling
            hardCeilingElapsed += 1
            if hardCeilingElapsed >= hardCeiling {
                advancePhase()
                return
            }

            // Silence tracking
            silenceSeconds += 1
            scorer.updateSilence(silenceSeconds)

            let threshold: TimeInterval = (phase == .followUp)
                ? silenceAfterFollowUp
                : silenceBeforeFollowUp

            if silenceSeconds >= threshold {
                if phase == .listening {
                    deliverFollowUp()
                    // Reset silence for the post-follow-up period
                    silenceSeconds = 0
                } else {
                    advancePhase()
                    return
                }
            }

            // Grace period: all words recalled
            if scorer.recalledCount == targetCount && silenceSeconds >= allRecalledGracePeriod {
                advancePhase()
                return
            }
        }
    }

    private func resetSilenceTimer() {
        silenceSeconds = 0
        scorer.updateSilence(0)
    }

    // MARK: - Advance Phase

    private func advancePhase() {
        guard phase != .done else { return }
        phase = .done
        timerActive = false
        speechService.stopListening()
        scorer.finalizePhase()
        persistResults()
        layoutManager.advanceToNextPhase()
    }

    // MARK: - Persist Results to QmciState

    private func persistResults() {
        // Scored words
        let recalled = Array(scorer.recalledWords)
        qmciState.delayedRecallWords = recalled
        qmciState.delayedRecallTranscript = speechService.transcript

        // ASR-detected words for clinician review
        qmciState.recallASRDetectedWords = recalled

        // Telemetry
        if let latency = scorer.firstWordLatencySeconds {
            qmciState.recallFirstWordLatencyMs = Int(latency * 1000)
        }
        qmciState.recallInterWordIntervalsMs = scorer.interWordIntervalsMs
        qmciState.recallIntrusionCount = scorer.intrusions.count
        qmciState.recallIntrusions = scorer.intrusions
        qmciState.recallSemanticSubstitutions = scorer.semanticSubstitutions.map { ($0.target, $0.said) }
        qmciState.recallSemanticSubstitutionCount = scorer.semanticSubstitutions.count
        qmciState.recallTotalPhaseDurationMs = scorer.totalPhaseDurationMs
        qmciState.recallSilenceBeforePromptMs = scorer.silenceBeforePromptMs
        qmciState.recallAnyOthersPromptUsed = scorer.anyOthersPromptUsed
    }
}

// MARK: - Preview

#Preview {
    let layoutManager = AvatarLayoutManager()
    let qmciState = QmciState()
    qmciState.selectWordList()

    return WordRecallPhaseView(
        layoutManager: layoutManager,
        qmciState: qmciState
    )
    .background(AssessmentTheme.Content.background)
}

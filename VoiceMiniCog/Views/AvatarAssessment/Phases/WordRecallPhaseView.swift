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
    let qmciState: QmciState

    @State private var scorer: WordRecallScorer
    @State private var phase: RecallPhase = .promptDelivery
    @State private var contentVisible = false
    @State private var recallPromptSpeechEpoch = 1  // Inconsistency 1 fix: start at 1
    @State private var recallPromptListeningUnlocked = false

    // Timer state
    @State private var silenceSeconds: TimeInterval = 0
    @State private var hardCeilingElapsed: TimeInterval = 0
    @State private var timerActive = false

    // Speech recognition
    @State private var speechService = SpeechService()
    @State private var lastTranscriptWordCount = 0  // Bug 3 fix: track words, not chars

    // Bug 1 fix: prevent double persistResults()
    @State private var didPersist = false

    // Bug 4 fix: track when all words were recalled (wall time, not silence)
    @State private var allWordsRecalledAt: Date? = nil

    // Bug 5 fix: skip silence increment during avatar follow-up speech
    @State private var avatarIsSpeakingFollowUp = false

    // Silence reinforce: fires 3s after prompt echo lands to reinforce avatar silence
    @State private var recallSilenceWork: DispatchWorkItem?

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

            PhaseHeaderBadge(
                phaseName: "Word Recall",
                icon: "brain.head.profile",
                accentColor: AssessmentTheme.Phase.wordRecall
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20).padding(.leading, 20)

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
                    // Bug 6 fix: animate scale from 0.6 → 1.0 on fill
                    .scaleEffect(filled ? 1.0 : 0.6)
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
        .accessibilityHidden(true)
    }

    // MARK: - Phase Lifecycle

    private func onPhaseAppear() {
        avatarInterrupt()
        avatarSetMicMuted(true)   // Mute mic during prompt delivery
        withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
            contentVisible = true
        }

        scorer.startScoring()

        avatarSetAssessmentContext(QMCIAvatarContext.delayedRecall)

        // Deliver the recall prompt via avatar after a 500ms settle delay
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
        recallSilenceWork?.cancel()
        recallSilenceWork = nil
        // Bug 8 fix: guard stopListening with isListening
        if speechService.isListening {
            speechService.stopListening()
        }
        persistResults()
    }

    // MARK: - Avatar Event Handling

    private func handleAvatarDoneSpeaking() {
        // Flow 2 fix: guard by current phase/screen
        guard layoutManager.currentPhase == .wordRecall else { return }
        guard phase == .promptDelivery || phase == .followUp else { return }

        // Bug 5 fix: clear avatar-speaking flag and reset silence on follow-up done
        if avatarIsSpeakingFollowUp {
            avatarIsSpeakingFollowUp = false
            resetSilenceTimer()
        }

        unlockListeningIfNeeded(epoch: recallPromptSpeechEpoch)
    }

    private func unlockListeningIfNeeded(epoch: Int) {
        guard epoch == recallPromptSpeechEpoch else { return }
        guard !recallPromptListeningUnlocked else { return }
        recallPromptListeningUnlocked = true

        scorer.markPromptEnded()
        avatarSetMicMuted(false)
        layoutManager.setAvatarListening()

        if phase == .promptDelivery {
            phase = .listening
        }

        startSpeechRecognition()

        resetSilenceTimer()
        timerActive = true

        // Schedule silence reinforcement 3s after prompt echo lands
        recallSilenceWork?.cancel()
        let work = DispatchWorkItem { [layoutManager] in
            // Guard via class reference (live state), not struct copy
            guard layoutManager.currentPhase == .wordRecall else { return }
            avatarSetAssessmentContext(QMCIAvatarContext.delayedRecallSilenceEnforce)
        }
        recallSilenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: - Speech Recognition

    private func startSpeechRecognition() {
        Task {
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                print("[WordRecall] Speech recognition not authorized — falling back to manual")
                return
            }
            do {
                // Bug 2 fix: stop existing recognition before restarting
                if speechService.isListening { speechService.stopListening() }
                try await speechService.startListening()
            } catch {
                print("[WordRecall] Failed to start speech recognition: \(error)")
            }
        }
    }

    // MARK: - Transcript Processing

    private func handleTranscriptUpdate(_ transcript: String) {
        guard !transcript.isEmpty else { return }

        // Bug 3 fix: use word count instead of character count —
        // ASR transcript corrections can produce shorter strings
        let newWordCount = transcript.split(separator: " ").count
        guard newWordCount > lastTranscriptWordCount else { return }
        lastTranscriptWordCount = newWordCount

        scorer.processTranscript(transcript)

        // Reset silence timer on new speech
        resetSilenceTimer()

        // Bug 4 fix: track when all words were recalled by wall time
        if scorer.recalledCount == targetCount && allWordsRecalledAt == nil {
            allWordsRecalledAt = Date()
        }

        // Check for completion phrase
        if scorer.containsCompletionPhrase(transcript) {
            handleCompletionPhrase()
            return
        }
    }

    // MARK: - Completion Logic

    private func handleCompletionPhrase() {
        guard phase == .listening else { return }
        deliverFollowUp()
    }

    private func deliverFollowUp() {
        guard phase == .listening, !scorer.anyOthersPromptUsed else {
            advancePhase()
            return
        }

        // Flow 1 fix: mute mic before avatar speaks follow-up
        avatarSetMicMuted(true)

        scorer.markAnyOthersPromptUsed()
        scorer.silenceBeforePromptMs = Int(silenceSeconds * 1000)
        phase = .followUp

        // Bug 5 fix: flag that avatar is speaking so timer loop skips silence
        avatarIsSpeakingFollowUp = true
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
            self.avatarIsSpeakingFollowUp = false
            avatarSetMicMuted(false)
            self.layoutManager.setAvatarListening()
            self.resetSilenceTimer()
        }
    }

    // MARK: - Timer Loop

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

            // Flow 5 fix: check grace period FIRST and return early
            if let completedAt = allWordsRecalledAt,
               Date().timeIntervalSince(completedAt) >= allRecalledGracePeriod {
                advancePhase()
                return
            }

            // Bug 5 fix: skip silence increment when avatar is speaking follow-up
            if !avatarIsSpeakingFollowUp {
                silenceSeconds += 1
            }

            let threshold: TimeInterval = (phase == .followUp)
                ? silenceAfterFollowUp
                : silenceBeforeFollowUp

            if silenceSeconds >= threshold {
                if phase == .listening {
                    deliverFollowUp()
                    silenceSeconds = 0
                } else {
                    advancePhase()
                    return
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceSeconds = 0
    }

    // MARK: - Advance Phase

    private func advancePhase() {
        guard phase != .done else { return }
        phase = .done
        timerActive = false
        recallSilenceWork?.cancel()
        recallSilenceWork = nil
        speechService.stopListening()

        // Flow 3 fix: write silenceBeforePromptMs if follow-up was never triggered
        if !scorer.anyOthersPromptUsed {
            scorer.silenceBeforePromptMs = Int(silenceSeconds * 1000)
        }

        // Process final cleaned-up ASR transcript before persisting
        scorer.processTranscript(speechService.transcript)
        persistResults()
        layoutManager.advanceToNextPhase()
    }

    // MARK: - Persist Results to QmciState

    private func persistResults() {
        // Bug 1 fix: prevent double persist
        guard !didPersist else { return }
        didPersist = true

        // Bug 7 fix: sort for deterministic order
        let recalled = scorer.recalledWords.sorted()
        qmciState.delayedRecallWords = recalled
        qmciState.delayedRecallTranscript = speechService.transcript

        // ASR-detected words for clinician review
        qmciState.recallASRDetectedWords = recalled

        // Telemetry
        if let latency = scorer.firstWordLatencySeconds {
            qmciState.recallFirstWordLatencyMs = Int(latency * 1000)
        }
        qmciState.recallInterWordIntervalsMs = scorer.interWordIntervalsMs
        qmciState.recallIntrusions = scorer.intrusions
        qmciState.recallSemanticSubstitutions = scorer.semanticSubstitutions.map { SemanticSubstitution(target: $0.target, substitution: $0.said) }
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

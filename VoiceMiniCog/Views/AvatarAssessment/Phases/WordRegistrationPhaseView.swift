//
//  WordRegistrationPhaseView.swift
//  VoiceMiniCog
//
//  Phase 5 — Word Registration. The avatar reads 5 words aloud across up to
//  3 trials. Per QMCI protocol, only Trial 1 counts toward the 5-point score;
//  Trials 2 and 3 exist to help the patient learn the words for the Delayed
//  Recall subtest later. The flow is fully hands-free and timed:
//
//    Trial N (N = 1…3):
//      1. Avatar reads the 5 words (intro speech for Trial 1, retry speech
//         for Trials 2 & 3) while the chips reveal progressively (1.5 s each).
//      2. After the reveal finishes, a ~8 s "Listening for your response…"
//         pause gives the patient time to repeat the words back.
//      3. If more trials remain, advance to the next trial (resetting chips).
//         Otherwise, speak the "Remember these words" prompt and let the
//         parent layout manager advance to the next phase.
//
//  Total duration is approximately 45–60 s depending on TTS cadence.
//

import SwiftUI

// MARK: - WordRegistrationPhaseView

struct WordRegistrationPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @ObservedObject var qmciState: QmciState

    // Trial bookkeeping
    @State private var currentTrial: Int = 0           // 1...totalTrials once running
    @State private var revealedCount: Int = 0
    @State private var isListeningPause: Bool = false  // Shows "Listening for your response…"
    @State private var isFinalRemember: Bool = false   // Shows final "Remember these words"
    @State private var hasStarted: Bool = false
    @State private var contentVisible: Bool = false

    // Speech recognition for capturing patient responses during the listening pause.
    // `SpeechService` is an `@Observable` class, so `@State` is the correct wrapper
    // to hold it in a SwiftUI view on iOS 17+.
    @State private var speech = SpeechService()
    @State private var didRequestAuth: Bool = false

    /// Trial whose word-list echo must finish before the listening pause (with chip reveal).
    @State private var listeningGateTrial: Int = 0
    @State private var chipsRevealCompleteForGate = false
    @State private var avatarPlaybackCompleteForGate = false
    @State private var trialSpeechEpoch = 0

    // Timing constants (seconds)
    private let totalTrials: Int = 3
    private let wordRevealInterval: Double = 1.5       // seconds between chip reveals
    private let postSpeechSettle: Double = 1.0         // small buffer after last chip before listening pause
    private let listeningPauseDuration: Double = 8.0   // patient-response window
    private let retryLeadIn: Double = 0.4              // brief gap before next trial's speech

    private var words: [String] { qmciState.registrationWords }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Ear Icon
            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentIconHeaderAccent(layoutManager.accentColor)

            // MARK: Title
            Text(LeftPaneSpeechCopy.wordRegistrationTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: Trial Counter / Status
            Text(statusText)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
                .animation(.easeInOut(duration: 0.25), value: isListeningPause)
                .animation(.easeInOut(duration: 0.25), value: currentTrial)
                .animation(.easeInOut(duration: 0.25), value: isFinalRemember)

            // MARK: Word Chips
            if !words.isEmpty {
                HStack(spacing: 10) {
                    ForEach(0..<words.count, id: \.self) { index in
                        WordChip(
                            word: words[index],
                            isRevealed: index < revealedCount,
                            accentColor: layoutManager.accentColor
                        )
                    }
                }
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)
            }

            Spacer()

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetContext("You are a clinical neuropsychologist administering the QMCI Word Registration subtest. This test has up to 3 trials of the same 5 words to help the patient learn them. Read the five words slowly and clearly, one per second, exactly as provided via echo commands. Do not add any words of your own. Do not provide feedback on the patient's recall. If the patient speaks between words, respond briefly: 'Let us continue.' Maintain a calm, professional tone throughout.")
            // Request speech recognition authorization in the background so the
            // avatar flow is not blocked. On simulator or denied devices the
            // listening pause will simply capture nothing.
            Task {
                if !didRequestAuth {
                    _ = await speech.requestAuthorization()
                    didRequestAuth = true
                }
            }
            if words.isEmpty {
                qmciState.selectWordList()
            }
            startTrialSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            guard !isFinalRemember else { return }
            guard currentTrial == listeningGateTrial, currentTrial >= 1 else { return }
            if !avatarPlaybackCompleteForGate {
                avatarPlaybackCompleteForGate = true
                maybeBeginListeningPauseForCurrentTrial()
            }
        }
    }

    // MARK: - Status / UI Helpers

    private var statusText: String {
        if isFinalRemember {
            return "Remember these words"
        }
        if isListeningPause {
            return "Listening for your response..."
        }
        if currentTrial >= 1 && currentTrial <= totalTrials {
            return "Trial \(currentTrial) of \(totalTrials)"
        }
        return LeftPaneSpeechCopy.wordRegistrationSubtitle
    }

    private var statusColor: Color {
        if isListeningPause {
            return layoutManager.accentColor
        }
        return AssessmentTheme.Content.textSecondary
    }

    // MARK: - Trial Sequencing

    /// Kicks off the 3-trial sequence. Guarded so it only runs once per phase
    /// appearance (SwiftUI may call onAppear multiple times).
    private func startTrialSequence() {
        guard !hasStarted else { return }
        hasStarted = true
        runTrial(1)
    }

    /// Runs a single trial: resets chips, increments attempt counter, speaks
    /// the appropriate prompt, reveals chips progressively, then schedules the
    /// listening pause. When the trial count is exhausted, speaks the final
    /// "remember" prompt and advances to the next phase.
    private func runTrial(_ trial: Int) {
        guard trial <= totalTrials else {
            finishRegistration()
            return
        }

        // Reset UI for this trial
        listeningGateTrial = trial
        chipsRevealCompleteForGate = false
        avatarPlaybackCompleteForGate = false
        trialSpeechEpoch += 1
        let speechEpoch = trialSpeechEpoch

        withAnimation(.easeOut(duration: 0.2)) {
            revealedCount = 0
            isListeningPause = false
            currentTrial = trial
        }

        // Track QMCI attempts — only Trial 1 affects scoring, but the model
        // records the total number of trials administered.
        qmciState.registrationAttempts = trial

        // Ensure the per-trial recalled-words bucket exists for this trial so
        // downstream persistence can index into `registrationTrialWords[trial-1]`.
        // The structure is initialized to 3 empty inner arrays by QmciState;
        // here we just guarantee the trial's slot is reset if this view is
        // re-entered mid-session.
        let trialIdx = trial - 1
        if qmciState.registrationTrialWords.indices.contains(trialIdx) {
            qmciState.registrationTrialWords[trialIdx] = []
        }

        // Make sure any lingering recognition session from a previous trial is
        // torn down and the live transcript is cleared. Do NOT start listening
        // here — the avatar is about to speak the word list, and we don't want
        // to capture the avatar's own voice as patient speech. The actual
        // `startListening()` call happens inside `beginListeningPause(after:)`.
        speech.stopListening()
        speech.transcript = ""

        // Avatar speaks: intro narration for Trial 1, retry phrasing otherwise.
        let speechText: String
        if trial == 1 {
            speechText = LeftPaneSpeechCopy.wordRegistrationNarration(words: words)
        } else {
            speechText = LeftPaneSpeechCopy.wordRegistrationRetry(words: words)
        }
        avatarSpeak(speechText)

        // If Tavus never sends `avatarDoneSpeaking`, still allow the listening gate to open.
        let wc = speechText.split(separator: " ").count
        let avatarFallback = max(22.0, Double(wc) * 0.32 + 12.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + avatarFallback) {
            guard self.trialSpeechEpoch == speechEpoch else { return }
            guard self.currentTrial == trial else { return }
            if !self.avatarPlaybackCompleteForGate {
                self.avatarPlaybackCompleteForGate = true
                self.maybeBeginListeningPauseForCurrentTrial()
            }
        }

        // Progressive chip reveal — one chip per `wordRevealInterval` seconds.
        for i in 0..<words.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * wordRevealInterval) {
                // Ignore stale reveals if the user somehow re-entered the phase.
                guard self.currentTrial == trial else { return }
                withAnimation(AssessmentTheme.Anim.chipAppear) {
                    self.revealedCount = i + 1
                }
            }
        }

        // Schedule the listening pause after the last chip is revealed.
        let speechDuration = Double(words.count) * wordRevealInterval + postSpeechSettle
        DispatchQueue.main.asyncAfter(deadline: .now() + speechDuration) {
            guard self.currentTrial == trial else { return }
            self.chipsRevealCompleteForGate = true
            self.maybeBeginListeningPauseForCurrentTrial()
        }
    }

    /// Opens the patient-response window only after chip reveal AND avatar audio have finished.
    private func maybeBeginListeningPauseForCurrentTrial() {
        let trial = listeningGateTrial
        guard trial >= 1, currentTrial == trial else { return }
        guard chipsRevealCompleteForGate, avatarPlaybackCompleteForGate else { return }
        guard !isListeningPause else { return }
        beginListeningPause(after: trial)
    }

    /// Shows "Listening for your response…" then either advances to the next
    /// trial or finishes the subtest.
    private func beginListeningPause(after trial: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isListeningPause = true
        }

        // Begin live speech-to-text capture for this trial. On the iOS
        // simulator `SpeechService.startListening()` short-circuits and never
        // captures audio, so the trial words simply stay empty — matching the
        // prior behavior.
        Task {
            do {
                speech.transcript = ""
                try await speech.startListening()
            } catch {
                // Simulator, unauthorized, or audio engine failure — leave the
                // transcript empty and let the pause elapse normally.
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + listeningPauseDuration) {
            guard self.currentTrial == trial else { return }

            // Stop capture and parse the accumulated transcript into matched
            // target words using the shared scoring helper.
            self.speech.stopListening()
            let result = scoreWordRecall(
                transcript: self.speech.transcript,
                wordList: self.qmciState.registrationWords
            )
            let trialIdx = trial - 1
            if self.qmciState.registrationTrialWords.indices.contains(trialIdx) {
                self.qmciState.registrationTrialWords[trialIdx] = result.recalled
            }
            if trial == 1 {
                // Mirror Trial 1 into the legacy scored field so existing
                // scoring tests and `QMCIScoringEngine.registrationScore`
                // continue to work. Trials 2 and 3 deliberately do NOT
                // overwrite this field — only Trial 1 counts toward the score.
                self.qmciState.registrationRecalledWords = result.recalled
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                self.isListeningPause = false
            }
            if trial < self.totalTrials {
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retryLeadIn) {
                    self.runTrial(trial + 1)
                }
            } else {
                self.finishRegistration()
            }
        }
    }

    /// Final step — avatar reminds the patient to remember the words, then the
    /// layout manager advances to the next phase after the prompt finishes.
    private func finishRegistration() {
        // Safety net: make sure the recognizer is torn down if the patient is
        // still speaking when the final trial ends.
        speech.stopListening()

        withAnimation(.easeInOut(duration: 0.25)) {
            isFinalRemember = true
        }
        avatarSpeak(LeftPaneSpeechCopy.wordRegistrationRemember)

        // Give TTS a moment to deliver the remember prompt before advancing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            layoutManager.advanceToNextPhase()
        }
    }
}

// MARK: - WordChip

private struct WordChip: View {

    let word: String
    let isRevealed: Bool
    let accentColor: Color

    var body: some View {
        Text(isRevealed ? word : "...")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(
                isRevealed
                    ? AssessmentTheme.Content.textPrimary
                    : AssessmentTheme.Content.textSecondary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isRevealed
                    ? accentColor.opacity(0.12)
                    : Color.gray.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isRevealed ? 1.0 : 0.9)
            .animation(AssessmentTheme.Anim.chipAppear, value: isRevealed)
    }
}

// MARK: - Preview

#Preview {
    let layoutManager = AvatarLayoutManager()
    let qmciState = QmciState()
    qmciState.selectWordList()

    return WordRegistrationPhaseView(
        layoutManager: layoutManager,
        qmciState: qmciState
    )
    .background(AssessmentTheme.Content.background)
}

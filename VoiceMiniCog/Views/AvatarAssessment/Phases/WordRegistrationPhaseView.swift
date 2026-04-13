//
//  WordRegistrationPhaseView.swift
//  VoiceMiniCog
//
//  Phase 5 — Word Registration (auditory encoding only).
//
//  CLINICAL-UI: The patient screen shows NO words. The 5 target words are
//  spoken by the avatar and encoded through the auditory channel only.
//  Displaying words would engage visual word-form processing, inflate
//  registration performance, and contaminate the downstream Delayed Recall
//  phase — invalidating the entire memory subscale against QMCI norms.
//
//  Patient panel layout:
//    • Ear icon (64pt) + "Listen" heading
//    • Audio-wave animation (pulses while avatar speaks)
//    • 5 anonymous progress circles (fill as words are correctly repeated)
//    • No buttons, no trial counter, no words
//
//  Protocol (up to 3 trials):
//    Trial 1: Avatar speaks intro + 5 words → patient repeats → score
//    Trial 2 (if <5): Avatar re-presents words → patient repeats → score
//    Trial 3 (if <5): Same → score → advance regardless
//    Total ceiling: 4 minutes.
//

import SwiftUI

// MARK: - WordRegistrationPhaseView

struct WordRegistrationPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @ObservedObject var qmciState: QmciState

    // Phase state machine
    private enum PhaseMode {
        case speaking   // Avatar is delivering words — wave pulses
        case listening  // Patient repeating — circles fill
        case done       // All trials complete, advancing
    }

    @State private var mode: PhaseMode = .speaking
    @State private var currentTrial: Int = 0
    @State private var currentTrialRecalled: [String] = []
    @State private var contentVisible: Bool = false
    @State private var hasStarted: Bool = false

    // Bug 2 fix: synchronous finish guard — checked before any async/animated work.
    @State private var didFinish: Bool = false

    // Timing
    @State private var phaseStartTime: Date = Date()
    @State private var listeningStartTime: Date? = nil
    // Bug 7/8 fix: nil until first transcript change, not Date() at listening start.
    @State private var lastTranscriptChangeTime: Date? = nil
    @State private var silenceTimer: Timer? = nil

    // Speech recognition
    @State private var speech = SpeechService()
    @State private var didRequestAuth: Bool = false
    @State private var previousTranscript: String = ""

    // Bug 6 fix: monotonic epoch counter (never set to currentTrial).
    @State private var trialSpeechEpoch: Int = 0

    /// Tavus delivers registration as several short echoes; resume next chunk on `avatarDoneSpeaking`.
    @State private var registrationEchoResume: (() -> Void)?
    @State private var isChainingRegistrationEchos = false
    @State private var trialOrchestration: Task<Void, Never>?

    // Bug 9 fix: stored safety task handle for cancellation.
    @State private var echoSafetyTask: Task<Void, Never>?
    // Bug 10 fix: cancellable fallback work item.
    @State private var chainFallbackWork: DispatchWorkItem?

    // Timing constants
    private let totalTrials = 3
    /// Seconds after the last transcript change before treating the patient as done speaking.
    private let silenceThreshold: TimeInterval = 4
    /// Minimum time before silence detection activates (Bug 7: prevents ASR init delay from ending trial).
    private let minimumListenWindow: TimeInterval = 8
    private let maxListeningPerTrial: TimeInterval = 45
    private let phaseCeiling: TimeInterval = 240      // 4 minutes total
    private let retryLeadIn: TimeInterval = 0.6

    private var words: [String] { qmciState.registrationWords }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Ear Icon (64pt)
            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 16)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: "Listen" Heading
            Text(LeftPaneSpeechCopy.wordRegistrationTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // MARK: Audio Wave (active while avatar speaks)
            WaveformBars(
                isActive: mode == .speaking,
                color: layoutManager.accentColor
            )
            .frame(height: 32)
            .padding(.bottom, 28)
            .opacity(mode == .speaking ? 1.0 : 0.25)
            .animation(.easeInOut(duration: 0.4), value: mode == .speaking)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            // MARK: Progress Circles (5 anonymous slots)
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { index in
                    RegistrationProgressCircle(
                        filled: index < currentTrialRecalled.count,
                        accentColor: Color(hex: "#34C759")
                    )
                }
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            Spacer()
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            phaseStartTime = Date()
            avatarSetAssessmentContext(
                "You are a clinical neuropsychologist administering the QMCI Word Registration subtest. " +
                "Speak ONLY the exact text sent via echo commands, one short echo at a time. " +
                "Do not add words between echoes. Do not provide feedback on the patient's recall. " +
                "If the patient speaks between echoes, respond briefly: 'Let us continue.' " +
                "Maintain a calm, professional tone throughout."
            )
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
        .onDisappear {
            trialOrchestration?.cancel()
            trialOrchestration = nil
            echoSafetyTask?.cancel()
            echoSafetyTask = nil
            chainFallbackWork?.cancel()
            chainFallbackWork = nil
            registrationEchoResume = nil
            silenceTimer?.invalidate()
            speech.stopListening()
            qmciState.registrationPhaseDuration = Date().timeIntervalSince(phaseStartTime)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            if isChainingRegistrationEchos {
                let resume = registrationEchoResume
                registrationEchoResume = nil
                resume?()
                return
            }
            // Bug 1 fix: don't open listening if we're finishing up.
            guard !didFinish else { return }
            // Bug 6 fix: compare against captured epoch, not currentTrial.
            guard mode == .speaking, trialSpeechEpoch >= 1 else { return }
            beginListening()
        }
        .onChange(of: speech.transcript) { _, newTranscript in
            guard mode == .listening else { return }
            applyTranscriptUpdate(newTranscript)
        }
    }

    /// Maps scorer output (lowercased substrings) onto the presented `words` casing and list order.
    private func canonicalRecalled(from matchedLower: [String]) -> [String] {
        let matched = Set(matchedLower)
        return words.filter { matched.contains($0.lowercased()) }
    }

    private func registrationScore(transcript: String)
        -> (count: Int, recalled: [String], intrusions: [String], repetitions: Int) {
        let raw = scoreWordRecall(transcript: transcript, wordList: words)
        let recalled = canonicalRecalled(from: raw.recalled)
        return (recalled.count, recalled, raw.intrusions, raw.repetitions)
    }

    // MARK: - Trial Sequencing

    private func startTrialSequence() {
        guard !hasStarted else { return }
        hasStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.runTrial(1)
        }
    }

    private func runTrial(_ trial: Int) {
        guard !didFinish else { return }
        guard trial <= totalTrials else {
            finishRegistration()
            return
        }

        // Check ceiling
        if Date().timeIntervalSince(phaseStartTime) >= phaseCeiling {
            qmciState.registrationCeilingHit = true
            finishRegistration()
            return
        }

        // Bug 6 fix: monotonic epoch increment.
        trialSpeechEpoch += 1

        // Bug 8 fix: reset lastTranscriptChangeTime so stale timestamps don't trigger silence.
        lastTranscriptChangeTime = nil

        withAnimation(.easeOut(duration: 0.25)) {
            currentTrialRecalled = []
            mode = .speaking
            currentTrial = trial
        }

        qmciState.registrationAttempts = trial
        let trialIdx = trial - 1
        if qmciState.registrationTrialWords.indices.contains(trialIdx) {
            qmciState.registrationTrialWords[trialIdx] = []
        }

        speech.stopListening()
        speech.transcript = ""
        previousTranscript = ""

        layoutManager.setAvatarSpeaking()

        // Cancel orphaned safety task from previous trial — prevents a stale
        // 55-second timeout from nilling registrationEchoResume and cancelling
        // echoSafetyTask after they've been reassigned to the new trial.
        echoSafetyTask?.cancel()
        echoSafetyTask = nil

        // Set isChainingRegistrationEchos SYNCHRONOUSLY before creating the
        // Task. The Task body executes asynchronously on the main actor's
        // cooperative executor; a WKScriptMessageHandler callback delivering a
        // stale avatarDoneSpeaking can run between runTrial returning and the
        // Task body starting. Without this guard, that stale notification
        // passes the (mode == .speaking, trialSpeechEpoch >= 1) check and
        // calls beginListening() prematurely — desynchronising the echo chain
        // and triggering cascading state corruption through orphaned safety
        // tasks.
        isChainingRegistrationEchos = true
        registrationEchoResume = nil

        trialOrchestration?.cancel()
        trialOrchestration = Task { @MainActor in
            await self.runRegistrationEchoChain(trial: trial)
        }

        // Bug 10 fix: use cancellable DispatchWorkItem.
        chainFallbackWork?.cancel()
        let work = DispatchWorkItem { [self] in
            guard self.trialSpeechEpoch >= 1, self.mode == .speaking, !self.didFinish else { return }
            self.trialOrchestration?.cancel()
            self.trialOrchestration = nil
            self.isChainingRegistrationEchos = false
            self.registrationEchoResume = nil
            self.beginListening()
        }
        chainFallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    /// Plays intro → lead-in → each word → closing using separate Tavus echoes.
    @MainActor
    private func runRegistrationEchoChain(trial: Int) async {
        // isChainingRegistrationEchos is already set true in runTrial
        // (synchronously, before this Task was created) to close the race
        // window with stale avatarDoneSpeaking notifications.

        if trial == 1 {
            await playRegistrationEchoSegment(LeftPaneSpeechCopy.wordRegistrationIntro)
            try? await Task.sleep(for: .milliseconds(500))
            await playRegistrationEchoSegment(LeftPaneSpeechCopy.wordRegistrationWordsLeadIn)
            try? await Task.sleep(for: .milliseconds(450))
            for w in words {
                if Task.isCancelled { break }
                await playRegistrationEchoSegment(w + ".")
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !Task.isCancelled {
                await playRegistrationEchoSegment(LeftPaneSpeechCopy.wordRegistrationRepeat)
            }
        } else {
            await playRegistrationEchoSegment(LeftPaneSpeechCopy.wordRegistrationRetryLeadIn)
            try? await Task.sleep(for: .milliseconds(500))
            for w in words {
                if Task.isCancelled { break }
                await playRegistrationEchoSegment(w + ".")
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !Task.isCancelled {
                await playRegistrationEchoSegment(LeftPaneSpeechCopy.wordRegistrationRetryClosing)
            }
        }

        // Bug 11 fix: clear chaining flag before calling beginListening.
        isChainingRegistrationEchos = false
        registrationEchoResume = nil

        guard !Task.isCancelled, !didFinish else { return }
        beginListening()
    }

    // Bug 9 fix: store and cancel safety task.
    @MainActor
    private func playRegistrationEchoSegment(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Both call sites (avatarDoneSpeaking onReceive + safety Task) run
            // on MainActor, so MainActor.assumeIsolated is correct here. The
            // nested function inherits the nonisolated context of the
            // continuation closure — assumeIsolated bridges back to @MainActor
            // without introducing async hops that would break the
            // synchronous resume/cancel coordination.
            MainActor.assumeIsolated {
                var didResume = false
                let finish = { [self] in
                    if didResume { return }
                    didResume = true
                    registrationEchoResume = nil
                    echoSafetyTask?.cancel()
                    echoSafetyTask = nil
                    continuation.resume()
                }
                registrationEchoResume = finish
                avatarSpeak(text)
                echoSafetyTask?.cancel()
                echoSafetyTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(55))
                    finish()
                }
            }
        }
    }

    // MARK: - Listening Phase

    private func beginListening() {
        guard mode == .speaking, !didFinish else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .listening
        }
        layoutManager.setAvatarListening()

        listeningStartTime = Date()
        // Bug 7 fix: don't set lastTranscriptChangeTime here — let first transcript change set it.
        // This prevents silence detection from firing before any speech is possible.

        // Start ASR
        Task {
            do {
                speech.transcript = ""
                previousTranscript = ""
                try await speech.startListening()
            } catch {
                // Simulator or unauthorized — listening window still elapses
            }
        }

        // Start silence/timeout monitor (common mode so it keeps firing during scrolling / UI).
        silenceTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            self.checkListeningTimeout()
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    private func applyTranscriptUpdate(_ transcript: String) {
        guard transcript != previousTranscript else { return }
        previousTranscript = transcript
        lastTranscriptChangeTime = Date()

        let result = registrationScore(transcript: transcript)
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
            currentTrialRecalled = result.recalled
        }

        if currentTrial == 1 && !result.recalled.isEmpty && qmciState.registrationFirstWordLatency == nil {
            if let start = listeningStartTime {
                qmciState.registrationFirstWordLatency = Date().timeIntervalSince(start)
            }
        }

        let lower = transcript.lowercased()
        let donePhrases = ["i'm done", "im done", "that's all", "thats all",
                           "that's it", "thats it", "i can't remember",
                           "i cant remember", "nothing else", "no more"]
        if donePhrases.contains(where: { lower.contains($0) }) {
            endListeningForTrial()
            return
        }

        if result.recalled.count >= 5 {
            endListeningForTrial()
        }
    }

    private func checkListeningTimeout() {
        guard mode == .listening, !didFinish else {
            silenceTimer?.invalidate()
            return
        }

        // Poll ASR transcript (workaround for @Observable not always driving onChange).
        applyTranscriptUpdate(speech.transcript)

        // Phase ceiling
        if Date().timeIntervalSince(phaseStartTime) >= phaseCeiling {
            qmciState.registrationCeilingHit = true
            silenceTimer?.invalidate()
            speech.stopListening()
            finishRegistration()
            return
        }

        // Per-trial max
        if let start = listeningStartTime,
           Date().timeIntervalSince(start) >= maxListeningPerTrial {
            endListeningForTrial()
            return
        }

        // Bug 7 fix: skip silence detection until minimum listen window has elapsed
        // and until at least one transcript change has occurred.
        guard let start = listeningStartTime,
              Date().timeIntervalSince(start) >= minimumListenWindow else { return }
        guard let lastChange = lastTranscriptChangeTime else { return }

        if Date().timeIntervalSince(lastChange) >= silenceThreshold {
            endListeningForTrial()
        }
    }

    private func endListeningForTrial() {
        guard mode == .listening, !didFinish else { return }

        silenceTimer?.invalidate()
        speech.stopListening()

        // Persist trial results
        let result = registrationScore(transcript: speech.transcript)
        let trialIdx = currentTrial - 1
        if qmciState.registrationTrialWords.indices.contains(trialIdx) {
            qmciState.registrationTrialWords[trialIdx] = result.recalled
        }

        // Bug 3 fix: always update to best trial performance (not just Trial 1).
        if result.recalled.count > qmciState.registrationRecalledWords.count {
            qmciState.registrationRecalledWords = result.recalled
        }

        // Accumulate intrusions and repetitions
        qmciState.registrationIntrusions.append(contentsOf: result.intrusions)
        qmciState.registrationRepetitionCount += result.repetitions

        // Trial decision logic
        let trial = currentTrial
        if result.recalled.count >= 5 {
            // All 5 correct — skip remaining trials.
            // Bug 1 fix: set isChainingRegistrationEchos so avatarDoneSpeaking
            // doesn't open a second listening session during the closure speech.
            isChainingRegistrationEchos = true
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = .speaking
            }
            avatarSpeak(LeftPaneSpeechCopy.wordRegistrationAllCorrect)
            layoutManager.setAvatarSpeaking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.isChainingRegistrationEchos = false
                self.finishRegistration()
            }
        } else if trial < totalTrials {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryLeadIn) {
                self.runTrial(trial + 1)
            }
        } else {
            finishRegistration()
        }
    }

    // MARK: - Finish

    private func finishRegistration() {
        // Bug 2 fix: synchronous guard before any async/animated work.
        guard !didFinish else { return }
        didFinish = true

        silenceTimer?.invalidate()
        chainFallbackWork?.cancel()
        trialOrchestration?.cancel()
        echoSafetyTask?.cancel()
        speech.stopListening()

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .done
        }

        qmciState.registrationPhaseDuration = Date().timeIntervalSince(phaseStartTime)

        avatarSpeak(LeftPaneSpeechCopy.wordRegistrationRemember)
        layoutManager.setAvatarSpeaking()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            layoutManager.advanceToNextPhase()
        }
    }
}

// MARK: - RegistrationProgressCircle

/// Anonymous progress circle — shows count only, no word labels.
/// Fills with a green check when a word is correctly recalled.
private struct RegistrationProgressCircle: View {
    let filled: Bool
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                .frame(width: 36, height: 36)

            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentColor)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: filled)
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

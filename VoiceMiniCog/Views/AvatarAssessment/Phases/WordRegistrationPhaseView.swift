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
    let qmciState: QmciState

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

    // Synchronous finish guard — checked before any async/animated work.
    @State private var didFinish: Bool = false

    // Timing
    @State private var phaseStartTime: Date = Date()
    @State private var listeningStartTime: Date? = nil
    // nil until first transcript change — prevents silence detection firing before any speech.
    @State private var lastTranscriptChangeTime: Date? = nil
    @State private var silenceTimer: Timer? = nil

    // Speech recognition
    @StateObject private var speech = SpeechService()
    @State private var didRequestAuth: Bool = false
    @State private var previousTranscript: String = ""

    // Monotonic epoch counter (never set equal to currentTrial).
    @State private var trialSpeechEpoch: Int = 0

    /// Tavus delivers registration as several short echoes; resume next chunk on `avatarDoneSpeaking`.
    @State private var registrationEchoResume: (() -> Void)?
    @State private var isChainingRegistrationEchos = false
    @State private var trialOrchestration: Task<Void, Never>?

    // Stored safety task handle for cancellation.
    @State private var echoSafetyTask: Task<Void, Never>?
    // Cancellable fallback work item for the echo-chain 120s watchdog.
    @State private var chainFallbackWork: DispatchWorkItem?
    // B5 fix: cancellable handle for the advanceToNextPhase dispatch.
    @State private var advanceWork: DispatchWorkItem?
    // B10 fix: cancellable handle for the retry-trial lead-in dispatch.
    @State private var retryWork: DispatchWorkItem?

    // Timing constants
    private let totalTrials = 3
    /// Seconds after the last transcript change before treating the patient as done speaking.
    private let silenceThreshold: TimeInterval = 4
    /// Minimum listen window before silence detection activates (prevents ASR init delay from ending trial).
    private let minimumListenWindow: TimeInterval = 8
    private let maxListeningPerTrial: TimeInterval = 45
    private let phaseCeiling: TimeInterval = 240      // 4 minutes total
    private let retryLeadIn: TimeInterval = 0.6

    private var words: [String] { qmciState.registrationWords }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            PhaseHeaderBadge(
                phaseName: "Word Registration",
                icon: "brain",
                accentColor: AssessmentTheme.Phase.registration
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20).padding(.leading, 20)

            Spacer()

            // MARK: Ear Icon (64pt)
            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 16)
                .accessibilityHidden(true)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: "Listen" Heading
            Text(LeftPaneSpeechCopy.wordRegistrationTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
                .accessibilityAddTraits(.isHeader)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mode == .speaking ? "Avatar is speaking words" : "Waiting")
            .accessibilityAddTraits(.updatesFrequently)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            // MARK: Progress Circles (5 anonymous slots)
            HStack(spacing: 14) {
                ForEach(0..<words.count, id: \.self) { index in
                    RegistrationProgressCircle(
                        filled: index < currentTrialRecalled.count,
                        accentColor: Color(hex: "#34C759")
                    )
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(currentTrialRecalled.count) of \(words.count) words recalled")
            .accessibilityAddTraits(.updatesFrequently)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            Spacer()
            Spacer().frame(height: 16)
        }
        .onAppear {
            avatarInterrupt()
            // B21 fix: put avatar into a defined waiting state immediately so
            // the 0.5s gap before runTrial(1) doesn't leave it in limbo.
            layoutManager.avatarBehavior = .waiting

            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            phaseStartTime = Date()
            avatarSetAssessmentContext(QMCIAvatarContext.wordRegistrationWithTrial(1, previousScore: nil))
            Task {
                if !didRequestAuth {
                    _ = await speech.requestAuthorization()
                    didRequestAuth = true
                }
            }
            if words.isEmpty {
                qmciState.selectWordList()
            }
            // B11 fix: pre-populate registrationTrialWords with 3 empty slots
            // so bounds-checked writes in runTrial/endListeningForTrial never
            // silently no-op on an under-sized array.
            if qmciState.registrationTrialWords.count < totalTrials {
                qmciState.registrationTrialWords = Array(repeating: [], count: totalTrials)
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
            advanceWork?.cancel()           // B5 fix
            advanceWork = nil
            retryWork?.cancel()             // B10 fix
            retryWork = nil
            registrationEchoResume = nil
            silenceTimer?.invalidate()
            silenceTimer = nil              // B9 fix
            speech.stopListening()
            // B20 fix: only persist duration here (single authoritative write).
            // finishRegistration() no longer writes registrationPhaseDuration.
            qmciState.registrationPhaseDuration = Date().timeIntervalSince(phaseStartTime)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            if isChainingRegistrationEchos {
                let resume = registrationEchoResume
                registrationEchoResume = nil
                resume?()
                return
            }
            guard !didFinish else { return }
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
        trialOrchestration = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !didFinish else { return }
            runTrial(1)
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

        // Monotonic epoch increment for stale-notification rejection.
        trialSpeechEpoch += 1

        // Reset so stale timestamps don't trigger premature silence detection.
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
        // B7 fix: reset transcript state synchronously (before the async Task
        // in beginListening), so the timer-driven applyTranscriptUpdate poll
        // never sees a stale transcript from the previous trial.
        speech.transcript = ""
        previousTranscript = ""

        layoutManager.setAvatarSpeaking()

        // Cancel orphaned safety task from previous trial.
        echoSafetyTask?.cancel()
        echoSafetyTask = nil

        // Set isChainingRegistrationEchos SYNCHRONOUSLY before creating the
        // Task to close the race window with stale avatarDoneSpeaking notifications.
        isChainingRegistrationEchos = true
        registrationEchoResume = nil

        trialOrchestration?.cancel()
        trialOrchestration = Task { @MainActor in
            await self.runRegistrationEchoChain(trial: trial)
        }

        // 120s fallback watchdog.
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

    /// Sends the full word-registration script as a single SSML echo.
    ///
    /// **Why single-echo?**  The previous multi-segment chain (`playRegistrationEchoSegment`
    /// per word) released `echoInFlight` between segments. During that gap the bridge's
    /// auto-interrupt logic could fire (ambient mic noise → VAD → `user.stopped_speaking` →
    /// interrupt), silently disrupting Tavus's TTS pipeline and causing the avatar to go mute.
    ///
    /// A single `<speak>` block with `<break>` tags keeps `echoInFlight = true` throughout,
    /// the mic stays muted, and auto-interrupts cannot fire — matching the pattern already
    /// used successfully by `WelcomePhaseView.introScriptForEcho`.
    @MainActor
    private func runRegistrationEchoChain(trial: Int) async {
        let echoText = LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: trial)

        // Send the single combined echo and wait for avatarDoneSpeaking.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
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
                avatarSpeak(echoText)
                echoSafetyTask?.cancel()
                // SSML echo may take 15-25s for intro + 5 words + pauses;
                // 45s safety matches the bridge's long-form watchdog.
                echoSafetyTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(45))
                    finish()
                }
            }
        }

        isChainingRegistrationEchos = false
        registrationEchoResume = nil

        guard !Task.isCancelled, !didFinish else { return }
        beginListening()
    }

    // MARK: - Listening Phase

    private func beginListening() {
        guard mode == .speaking, !didFinish else { return }

        avatarSetMicMuted(false)

        // Failsafe: force mic open after 800ms in case Daily's gate didn't release
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard mode == .listening, !didFinish else { return }
            avatarSetMicMuted(false)
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .listening
        }
        layoutManager.setAvatarListening()

        listeningStartTime = Date()

        // B7 fix: transcript state is reset synchronously in runTrial before
        // reaching here, so we only need to (re)start ASR.
        Task {
            do {
                try await speech.startListening()
            } catch {
                // Simulator or unauthorized — listening window still elapses normally.
            }
        }

        // Start silence/timeout monitor (.common mode keeps firing during scroll/UI).
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
            silenceTimer = nil  // B9 fix
            return
        }

        applyTranscriptUpdate(speech.transcript)
        guard mode == .listening, !didFinish else { return }

        // Phase ceiling
        if Date().timeIntervalSince(phaseStartTime) >= phaseCeiling {
            qmciState.registrationCeilingHit = true
            silenceTimer?.invalidate()
            silenceTimer = nil  // B9 fix
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
        silenceTimer = nil  // B9 fix

        withAnimation(.easeInOut(duration: 0.15)) {
            mode = .speaking
        }
        layoutManager.avatarBehavior = .waiting

        let frozenTranscript = speech.transcript
        speech.stopListening()

        let result = registrationScore(transcript: frozenTranscript)
        let trialIdx = currentTrial - 1
        if qmciState.registrationTrialWords.indices.contains(trialIdx) {
            qmciState.registrationTrialWords[trialIdx] = result.recalled
        }

        if result.recalled.count > qmciState.registrationRecalledWords.count {
            qmciState.registrationRecalledWords = result.recalled
        }

        // Accumulate intrusions across trials, deduplicating to prevent inflated
        // intrusion scores (e.g., "face" said on every trial counted only once).
        let newIntrusions = result.intrusions.filter {
            !qmciState.registrationIntrusions.contains($0)
        }
        qmciState.registrationIntrusions.append(contentsOf: newIntrusions)
        qmciState.registrationRepetitionCount += result.repetitions

        let trial = currentTrial
        if result.recalled.count >= 5 {
            isChainingRegistrationEchos = true
            avatarSpeak(LeftPaneSpeechCopy.wordRegistrationAllCorrect)
            layoutManager.setAvatarSpeaking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.isChainingRegistrationEchos = false
                self.finishRegistration()
            }
        } else if trial < totalTrials {
            // Send updated context with trial number and previous score
            let nextTrial = trial + 1
            let prevScore = result.recalled.count
            avatarSetAssessmentContext(
                QMCIAvatarContext.wordRegistrationWithTrial(nextTrial, previousScore: prevScore)
            )
            // B10 fix: use cancellable DispatchWorkItem for retry lead-in.
            retryWork?.cancel()
            let work = DispatchWorkItem { [self] in
                guard !self.didFinish else { return }
                self.runTrial(nextTrial)
            }
            retryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + retryLeadIn, execute: work)
        } else {
            finishRegistration()
        }
    }

    // MARK: - Finish

    private func finishRegistration() {
        guard !didFinish else { return }
        didFinish = true

        silenceTimer?.invalidate()
        silenceTimer = nil          // B9 fix
        chainFallbackWork?.cancel()
        retryWork?.cancel()         // B10 fix
        trialOrchestration?.cancel()
        echoSafetyTask?.cancel()
        speech.stopListening()

        withAnimation(.easeInOut(duration: 0.25)) {
            mode = .done
        }

        // B20 fix: registrationPhaseDuration is written once — in onDisappear —
        // which captures the true dismissal time regardless of code path.

        avatarSpeak(LeftPaneSpeechCopy.wordRegistrationRemember)
        layoutManager.setAvatarSpeaking()

        // B5 fix: use cancellable DispatchWorkItem so onDisappear can cancel
        // the advance if the view is dismissed before the delay elapses.
        advanceWork?.cancel()
        let work = DispatchWorkItem { [self] in
            layoutManager.advanceToNextPhase()
        }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }
}

// MARK: - RegistrationProgressCircle

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

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

    /// Count of bubbles displayed as "filled" on the patient screen.
    /// Only ever increments from real ASR word detection during the
    /// .listening window — never spontaneously while the avatar speaks.
    /// On .done, forced to 5 for the celebratory memory-lock moment.
    @State private var visualFilledCount: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    // Observer + watchdog for the closing-line gating in finishRegistration.
    @State private var closingDoneObserver: NSObjectProtocol?
    @State private var closingWatchdogWork: DispatchWorkItem?
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

            // MARK: Phase label (leading, plain text — no pill)
            HStack {
                Text("Word Learning  •  Remember these")
                    .font(.subheadline)
                    .foregroundStyle(layoutManager.accentColor)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .opacity(contentVisible ? 1 : 0)
            .animation(reduceMotion ? .none : .easeOut(duration: 0.4), value: contentVisible)

            Spacer()

            // MARK: Central content — crossfade between Listening and Registered
            Group {
                if mode == .done {
                    memoryLockMoment
                } else {
                    listeningCentralBlock
                }
            }
            .animation(
                reduceMotion ? .none : .easeInOut(duration: 0.35),
                value: mode
            )

            Spacer()
            Spacer().frame(height: 16)
        }
        .onAppear {
            avatarInterrupt()
            avatarSetAssessmentPhaseType(.wordRegistration)
            avatarBeginSilenceWatch()
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
            closingWatchdogWork?.cancel()
            closingWatchdogWork = nil
            if let obs = closingDoneObserver {
                NotificationCenter.default.removeObserver(obs)
                closingDoneObserver = nil
            }
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
        .onChange(of: mode) { _, newMode in
            // Bubbles only ever fill from real ASR word detection — never
            // spontaneously while the avatar is speaking. On mode change
            // we just re-sync the count to the scorer's ground truth.
            switch newMode {
            case .speaking:
                // New trial — clear everything. Bubbles stay empty until
                // the patient actually says words in the next listening
                // window.
                visualFilledCount = 0
            case .listening:
                visualFilledCount = currentTrialRecalled.count
            case .done:
                withAnimation(AssessmentTheme.Motion.celebrationBounce) {
                    visualFilledCount = 5
                }
            }
        }
        .onChange(of: currentTrialRecalled.count) { _, newCount in
            guard mode == .listening else { return }
            withAnimation(AssessmentTheme.Motion.celebrationBounce) {
                visualFilledCount = newCount
            }
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

        // Mic unmute is handled by DailyCallManager.handleReplicaStoppedSpeaking
        // when the word-list echo finishes; watchdog covers dropped events.

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

        // Gate phase advance on Tavus confirming the closing line finished,
        // not a fixed 4s delay. The next phase calls avatarInterrupt() in its
        // onAppear, which would chop the closing utterance if we advance early.
        // Watchdog (8s) covers the case where stopped_speaking is never delivered.
        advanceWork?.cancel()
        closingWatchdogWork?.cancel()
        if let obs = closingDoneObserver {
            NotificationCenter.default.removeObserver(obs)
            closingDoneObserver = nil
        }

        var didAdvance = false
        let advance: () -> Void = { [self] in
            if didAdvance { return }
            didAdvance = true
            closingWatchdogWork?.cancel()
            closingWatchdogWork = nil
            if let obs = closingDoneObserver {
                NotificationCenter.default.removeObserver(obs)
                closingDoneObserver = nil
            }
            layoutManager.advanceToNextPhase()
        }

        closingDoneObserver = NotificationCenter.default.addObserver(
            forName: .avatarDoneSpeaking, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { advance() }
        }

        let watchdog = DispatchWorkItem { advance() }
        closingWatchdogWork = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: watchdog)

        // Keep advanceWork populated for onDisappear cancellation symmetry.
        advanceWork = watchdog
    }
}

// MARK: - Listening central block

extension WordRegistrationPhaseView {

    /// State 1 — avatar is speaking the words. Title + subtitle + 5
    /// bubbles (fill staggered as the avatar speaks) + 5-bar waveform.
    @ViewBuilder
    fileprivate var listeningCentralBlock: some View {
        VStack(spacing: 0) {
            Text("Listen carefully.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text("You'll be asked to recall these words later.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 40)

            Spacer().frame(height: 32)

            WordLearningBubbleRow(
                filledCount: visualFilledCount,
                accent: layoutManager.accentColor
            )

            Spacer().frame(height: 24)

            WordLearningWaveform(
                isActive: mode == .speaking || mode == .listening,
                color: layoutManager.accentColor
            )
            .frame(height: 32)
        }
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 10)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.4), value: contentVisible)
    }

    /// State 2 — words registered. Large seal with .bounce + one-shot
    /// glow ring + "5 words registered" + subtitle + all bubbles filled.
    @ViewBuilder
    fileprivate var memoryLockMoment: some View {
        MemoryLockMoment(accent: layoutManager.accentColor)
    }
}

// MARK: - WordLearningBubbleRow

/// Horizontal row of 5 learning bubbles. Each bubble:
///   • Empty:  accent 12% fill + 1.5pt accent stroke, no checkmark.
///   • Filled: accent 40% fill + 1.5pt accent stroke + white checkmark,
///             celebrationBounce pop on flip.
/// On first appear the entire row stagger-scales in (0.08s per bubble).
private struct WordLearningBubbleRow: View {
    let filledCount: Int
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedCount: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { index in
                WordLearningBubble(
                    filled: index < filledCount,
                    accent: accent,
                    visible: index < appearedCount
                )
            }
        }
        .onAppear {
            if reduceMotion {
                appearedCount = 5
                return
            }
            // Stagger the row's entry reveal once.
            Task { @MainActor in
                for i in 1...5 {
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(AssessmentTheme.Motion.celebrationBounce) {
                        appearedCount = i
                    }
                }
            }
        }
    }
}

private struct WordLearningBubble: View {
    let filled: Bool
    let accent: Color
    let visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? accent.opacity(0.40) : accent.opacity(0.12))
                .frame(width: 52, height: 52)
            Circle()
                .strokeBorder(accent, lineWidth: 1.5)
                .frame(width: 52, height: 52)
            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .scaleEffect(visible || reduceMotion ? 1.0 : 0.75)
        .opacity(visible ? 1 : 0)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : AssessmentTheme.Motion.celebrationBounce,
            value: filled
        )
    }
}

// MARK: - WordLearningWaveform

/// 5-bar accent-tinted waveform. TimelineView-driven sine amplitudes at
/// staggered phase shifts; fades opacity based on `isActive`. Reduce-motion
/// renders static capsules.
private struct WordLearningWaveform: View {
    let isActive: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: 5, height: CGFloat(12 + (i % 3) * 8))
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            let phaseShift = Double(i) * 0.4
                            let amp = (sin(t * 3.2 - phaseShift) + 1) / 2
                            Capsule()
                                .fill(color)
                                .frame(width: 5, height: CGFloat(8 + amp * 22))
                        }
                    }
                }
            }
        }
        .opacity(isActive ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .accessibilityLabel("Avatar speaking")
    }
}

// MARK: - MemoryLockMoment

/// State 2 centerpiece — the "these are locked in" moment. Seal SF Symbol
/// with native `.bounce` effect, a one-shot radial glow pulse behind it,
/// staggered text reveal, and the 5 bubbles shown fully filled.
private struct MemoryLockMoment: View {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sealVisible: Bool = false
    @State private var textVisible: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseAlpha: Double = 0.2

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(accent)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulseScale)
                        .opacity(pulseAlpha)
                        .blur(radius: 6)
                }

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(sealVisible ? 1.0 : 0.8)
                    .opacity(sealVisible ? 1 : 0)
                    .symbolEffect(.bounce, options: .nonRepeating, value: sealVisible)
            }
            .frame(width: 88, height: 88)

            Text("5 words registered")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.primary)
                .opacity(textVisible ? 1 : 0)
                .offset(y: textVisible ? 0 : 8)

            Text("We'll come back to these after the clock test.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(textVisible ? 1 : 0)
                .offset(y: textVisible ? 0 : 8)

            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    WordLearningBubble(filled: true, accent: accent, visible: true)
                }
            }
            .padding(.top, 12)
            .opacity(textVisible ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                sealVisible = true
                textVisible = true
                return
            }
            // Seal fades + scales in (one-shot bounce fires automatically
            // when sealVisible flips because of the value: param above).
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) {
                sealVisible = true
            }
            // One-shot glow pulse: scale 1.0 → 1.3, opacity 0.2 → 0, easeOut 0.8s
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                pulseScale = 1.3
                pulseAlpha = 0.0
            }
            // Text slides up after the seal settles.
            withAnimation(.easeOut(duration: 0.35).delay(0.9)) {
                textVisible = true
            }
        }
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

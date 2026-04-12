//
//  WordRegistrationPhaseView.swift
//  VoiceMiniCog
//
//  QMCI Word Registration — up to 3 trials, auditory presentation only (no on-screen
//  words during avatar delivery), then listening with per-word chip reveal driven
//  by live STT. Advances automatically to clock drawing when 5/5 on any trial or
//  after 3 trials (no mid-phase skip control here).
//

import SwiftUI

// MARK: - WordRegistrationPhaseView

struct WordRegistrationPhaseView: View {

    let layoutManager: AvatarLayoutManager
    @ObservedObject var qmciState: QmciState

    private let totalTrials: Int = 3
    /// Pause after full intro echo before "The words are…"
    private let introToLeadInPauseNs: UInt64 = 800_000_000
    /// Target gap after each spoken word (post `replica.stopped`) before next echo
    private let interWordPauseNs: UInt64 = 850_000_000
    /// Tail after 5th word before opening the mic
    private let postLastWordTailNs: UInt64 = 500_000_000
    /// Patient response window once listening starts
    private let listeningDurationNs: UInt64 = 15_000_000_000
    private let retryLeadInNs: UInt64 = 400_000_000

    @State private var currentTrial: Int = 0
    @State private var contentVisible = false
    @State private var hasStarted = false
    @State private var isListening = false
    @State private var isFinalRemember = false
    @State private var chipRevealed: [Bool] = []
    @State private var speech = SpeechService()
    @State private var didRequestAuth = false
    @State private var trialTask: Task<Void, Never>?
    /// Resumes the active `playEcho` continuation when Tavus finishes the current echo.
    @State private var echoCompletionHandler: (() -> Void)?

    private var words: [String] { qmciState.registrationWords }

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentIconHeaderAccent(layoutManager.accentColor)

            Text(LeftPaneSpeechCopy.wordRegistrationTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            Text(statusLine)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
                .animation(.easeInOut(duration: 0.25), value: isListening)
                .animation(.easeInOut(duration: 0.25), value: isFinalRemember)

            if isListening, !words.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        ListeningWordChip(
                            word: word,
                            isRevealed: index < chipRevealed.count ? chipRevealed[index] : false,
                            accentColor: layoutManager.accentColor
                        )
                    }
                }
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)
            }

            Spacer()
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetContext(
                "You are a clinical neuropsychologist administering the QMCI Word Registration subtest. " +
                "Speak ONLY the exact text sent via echo commands, one echo at a time. " +
                "Do not add words, do not list the five words until the separate word echoes arrive. " +
                "Speak at a calm, measured pace. While the patient repeats words from memory, stay completely silent — do not interject. " +
                LeftPaneSpeechCopy.examinerNeverCorrectPatient
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
            chipRevealed = Array(repeating: false, count: max(5, words.count))
            startRegistrationIfNeeded()
        }
        .onDisappear {
            trialTask?.cancel()
            trialTask = nil
            speech.stopListening()
            echoCompletionHandler = nil
        }
        .onChange(of: speech.transcript) { _, newValue in
            guard isListening, !words.isEmpty else { return }
            updateChipReveal(fromTranscript: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            let finish = echoCompletionHandler
            echoCompletionHandler = nil
            finish?()
        }
    }

    // MARK: - Status

    private var statusLine: String {
        if isFinalRemember {
            return "Remember these words"
        }
        if isListening {
            return "Listening… repeat the words you remember."
        }
        return LeftPaneSpeechCopy.wordRegistrationSubtitle
    }

    private var statusColor: Color {
        if isListening || isFinalRemember {
            return layoutManager.accentColor
        }
        return AssessmentTheme.Content.textSecondary
    }

    // MARK: - Lifecycle

    private func startRegistrationIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        trialTask?.cancel()
        trialTask = Task { @MainActor in
            await runTrialLoop()
        }
    }

    // MARK: - Trial loop

    @MainActor
    private func runTrialLoop() async {
        for trial in 1...totalTrials {
            if Task.isCancelled { return }
            currentTrial = trial
            qmciState.registrationAttempts = trial
            let trialIdx = trial - 1
            if qmciState.registrationTrialWords.indices.contains(trialIdx) {
                qmciState.registrationTrialWords[trialIdx] = []
            }

            isListening = false
            chipRevealed = Array(repeating: false, count: words.count)
            speech.stopListening()
            speech.transcript = ""

            layoutManager.setAvatarSpeaking()

            if trial == 1 {
                await playEcho(LeftPaneSpeechCopy.wordRegistrationSpokenIntro)
                try? await Task.sleep(nanoseconds: introToLeadInPauseNs)
            } else {
                await playEcho(LeftPaneSpeechCopy.wordRegistrationRetryIntro)
                try? await Task.sleep(nanoseconds: introToLeadInPauseNs)
            }

            if Task.isCancelled { return }

            await playEcho(LeftPaneSpeechCopy.wordRegistrationWordsAre)

            for (idx, word) in words.enumerated() {
                if Task.isCancelled { return }
                await playEcho(word + ".")
                if idx < words.count - 1 {
                    try? await Task.sleep(nanoseconds: interWordPauseNs)
                }
            }

            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: postLastWordTailNs)

            let outcome = await runListeningPhase(trial: trial)
            if outcome.count >= 5 {
                await finishRegistrationFlow()
                return
            }

            if trial >= totalTrials {
                await finishRegistrationFlow()
                return
            }

            try? await Task.sleep(nanoseconds: retryLeadInNs)
        }
    }

    /// Starts STT, waits `listeningDuration`, returns fuzzy match count and recalled list.
    @MainActor
    private func runListeningPhase(trial: Int) async -> (count: Int, recalled: [String]) {
        isListening = true
        layoutManager.setAvatarListening()
        speech.transcript = ""

        do {
            try await speech.startListening()
        } catch {
            // Simulator / denied mic — still wait full window
        }

        try? await Task.sleep(nanoseconds: listeningDurationNs)

        speech.stopListening()
        isListening = false
        layoutManager.setAvatarSpeaking()

        let result = scoreWordRegistrationRecall(
            transcript: speech.transcript,
            wordList: qmciState.registrationWords
        )
        let trialIdx = trial - 1
        if qmciState.registrationTrialWords.indices.contains(trialIdx) {
            qmciState.registrationTrialWords[trialIdx] = result.recalled
        }
        if trial == 1 {
            qmciState.registrationRecalledWords = result.recalled
        }
        return (result.count, result.recalled)
    }

    @MainActor
    private func updateChipReveal(fromTranscript transcript: String) {
        let result = scoreWordRegistrationRecall(transcript: transcript, wordList: words)
        let matched = Set(result.recalled.map { $0.lowercased() })
        var next = chipRevealed
        if next.count != words.count {
            next = Array(repeating: false, count: words.count)
        }
        for (i, w) in words.enumerated() {
            if matched.contains(w.lowercased()) {
                next[i] = true
            }
        }
        withAnimation(.easeOut(duration: 0.25)) {
            chipRevealed = next
        }
    }

    // MARK: - Echo sequencing (one Tavus echo at a time)

    @MainActor
    private func playEcho(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var didFinish = false
            func finish() {
                if didFinish { return }
                didFinish = true
                echoCompletionHandler = nil
                continuation.resume()
            }
            echoCompletionHandler = { finish() }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                finish()
            }
            avatarSpeak(text)
        }
    }

    // MARK: - Completion

    @MainActor
    private func finishRegistrationFlow() async {
        trialTask?.cancel()
        trialTask = nil
        speech.stopListening()

        withAnimation(.easeInOut(duration: 0.25)) {
            isFinalRemember = true
        }
        layoutManager.setAvatarSpeaking()
        await playEcho(LeftPaneSpeechCopy.wordRegistrationRemember)
        layoutManager.advanceToNextPhase()
    }
}

// MARK: - Listening chip (fades in when matched)

private struct ListeningWordChip: View {
    let word: String
    let isRevealed: Bool
    let accentColor: Color

    var body: some View {
        Text(isRevealed ? word : " ")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(
                isRevealed
                    ? AssessmentTheme.Content.textPrimary
                    : AssessmentTheme.Content.textSecondary.opacity(0.25)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isRevealed
                    ? accentColor.opacity(0.12)
                    : Color.gray.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isRevealed ? 1 : 0.35)
            .animation(.easeOut(duration: 0.35), value: isRevealed)
            .frame(minWidth: 44)
    }
}

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

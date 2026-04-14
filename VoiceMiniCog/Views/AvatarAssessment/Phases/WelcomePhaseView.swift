//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. The avatar speaks a short, plain-language intro
//  describing each task (not its clinical name) for patient-friendly pacing.
//  Subtest rows reveal in sync with each activity description, timed dynamically
//  from the script using a speech-rate model anchored to
//  conversation.replica.started_speaking (with a delayed fallback).
//  Begin button appears as she says "press Begin Assessment".
//

import SwiftUI

// MARK: - Speech Timing Model

/// Computes reveal delays from the **plain** intro script (no SSML) so row reveals
/// stay aligned with slower, clinician-paced delivery on the welcome screen.
private struct SpeechTimingModel {

    /// ~0.85× prior default — targets ~130–140 wpm for older adults / MCI-friendly pacing.
    static let secsPerWord: Double = 0.47
    /// Default gap when no per-boundary override applies.
    static let sentencePause: Double = 0.50
    /// How far ahead of the activity description to reveal the row (seconds).
    static let revealLeadTime: Double = 0.18

    /// Pause (seconds) after sentence boundary `boundaryIndex`.
    static func welcomeBoundaryPause(boundaryIndex: Int, sentenceCount: Int) -> Double {
        let lastBoundary = sentenceCount - 2
        switch boundaryIndex {
        case 0: return 0.70  // greeting → overview
        case 1: return 0.90  // overview → first task
        case lastBoundary where lastBoundary >= 2: return 1.00  // final task → closing
        default: return 0.50 // between subtest lines
        }
    }

    /// Returns the estimated time offset (seconds from speech start) for each landmark phrase.
    /// Pass `applyLeadTime: true` for subtest reveals, `false` for the Begin button.
    static func landmarkOffsets(
        script: String,
        landmarks: [String],
        applyLeadTime: Bool = true,
        useWelcomePacing: Bool = false
    ) -> [Double] {
        // Bug 4 fix: handle "!", newlines, and edge-case delimiters robustly.
        let sentences = script
            .components(separatedBy: CharacterSet(charactersIn: ".?!"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var cumulative: Double = 0
        var wordTimings: [(word: String, time: Double)] = []

        for (sIdx, sentence) in sentences.enumerated() {
            let words = sentence.split(separator: " ").map(String.init)
            for word in words {
                wordTimings.append((word: word, time: cumulative))
                cumulative += secsPerWord
            }
            if sIdx < sentences.count - 1 {
                let pause = useWelcomePacing
                    ? welcomeBoundaryPause(boundaryIndex: sIdx, sentenceCount: sentences.count)
                    : sentencePause
                cumulative += pause
            }
        }

        let lead = applyLeadTime ? revealLeadTime : 0
        return landmarks.map { landmark in
            let target = landmark.lowercased()
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "—", with: "")
            let targetWords = target.split(separator: " ").map(String.init)
            guard let firstTarget = targetWords.first else { return cumulative }

            for (i, entry) in wordTimings.enumerated() {
                let clean = entry.word.lowercased()
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "—", with: "")
                if clean == firstTarget {
                    let slice = wordTimings[i..<min(i + targetWords.count, wordTimings.count)]
                    let sliceWords = slice.map {
                        $0.word.lowercased()
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: ",", with: "")
                    }
                    if sliceWords == targetWords {
                        return max(0, entry.time - lead)
                    }
                }
            }
            // Bug 5 fix: mid-script fallback instead of end-of-script.
            #if DEBUG
            assertionFailure("SpeechTimingModel: landmark '\(landmark)' not found in script")
            #endif
            return cumulative * 0.5
        }
    }
}

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager
    var onGoToMainMenu: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false
    @State private var echoSent = false
    @State private var revealSequenceScheduled = false
    @State private var didAnchorRevealsToSpeaking = false
    // Flow 1 fix: used to short-circuit the fallback timer.
    @State private var welcomeIntroReplicaStarted = false
    // Flow 2 fix: track work items so catch-up can cancel pending reveal timers.
    @State private var revealWorkItems: [DispatchWorkItem] = []

    // MARK: - Intro Script (plain language, not clinical names)

    /// Exact spoken wording (no SSML) — used for timing calculations + reduce-motion path.
    /// Uses plain-language task descriptions instead of clinical names for patient comprehension.
    /// Clinical note: Qmci uses 5-word registration lists (O'Caoimh 2012), not 3.
    private let introScriptPlain = """
        Welcome to your Brain Health Check. We'll do six short activities together. \
        First, I'll ask you a few simple questions, like today's date and where we are. \
        Then, I'll say five words for you to try to remember. \
        Next, I'll ask you to draw a clock showing a specific time. \
        After that, I'll ask you to name as many animals as you can in one minute. \
        Then, I'll read you a short story and ask what you remember. \
        And finally, I'll ask you to recall those five words from earlier. \
        When you're ready, press Begin Assessment.
        """

    /// SSML-enhanced version for Tavus/ElevenLabs.
    private var introScriptForEcho: String {
        """
        <speak>\
        Welcome to your Brain Health Check.<break time="700ms"/> \
        We'll do six short activities together.<break time="900ms"/> \
        First, I'll ask you a few simple questions, like today's date and where we are.<break time="500ms"/> \
        Then, I'll say five words for you to try to remember.<break time="500ms"/> \
        Next, I'll ask you to draw a clock showing a specific time.<break time="500ms"/> \
        After that, I'll ask you to name as many animals as you can in one minute.<break time="500ms"/> \
        Then, I'll read you a short story and ask what you remember.<break time="500ms"/> \
        And finally, I'll ask you to recall those five words from earlier.<break time="1000ms"/> \
        When you're ready, press Begin Assessment.\
        </speak>
        """
    }

    // MARK: - Computed Reveal Timings

    /// Landmark phrases that match the *first distinctive words* of each task description.
    /// These must appear verbatim in introScriptPlain.
    private var revealLandmarks: [String] {
        [
            "I'll ask you a few simple questions",
            "I'll say five words",
            "I'll ask you to draw a clock",
            "I'll ask you to name as many animals",
            "I'll read you a short story",
            "I'll ask you to recall those five words"
        ]
    }

    private var revealDelays: [Double] {
        SpeechTimingModel.landmarkOffsets(
            script: introScriptPlain,
            landmarks: revealLandmarks,
            applyLeadTime: true,
            useWelcomePacing: true
        )
    }

    private var beginButtonDelay: Double {
        SpeechTimingModel.landmarkOffsets(
            script: introScriptPlain,
            landmarks: ["press Begin Assessment"],
            applyLeadTime: false,
            useWelcomePacing: true
        ).first ?? 22.0
    }

    /// 4s chosen to be slightly longer than Tavus round-trip + replica.started_speaking latency
    /// on a typical LTE connection (~2–3s) while staying well under the first reveal delay.
    private let revealFallbackDelay: Double = 4.0

    var body: some View {
        VStack(spacing: 0) {
            PhaseHeaderBadge(
                phaseName: "Welcome",
                icon: "waveform",
                accentColor: AssessmentTheme.Phase.welcome
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20).padding(.leading, 20)

            Spacer()

            // MARK: Header
            Group {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(layoutManager.accentColor)
                    .assessmentIconHeaderAccent(layoutManager.accentColor)
                    .padding(.bottom, 14)

                Text(LeftPaneSpeechCopy.welcomeTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AssessmentTheme.Content.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)

                Text(LeftPaneSpeechCopy.welcomeSubtitle)
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .opacity(headerVisible ? 1 : 0)
            .offset(y: headerVisible ? 0 : 10)

            // MARK: Subtest List
            VStack(spacing: 0) {
                ForEach(Array(QmciSubtest.allCases.enumerated()), id: \.element) { index, subtest in
                    SubtestRow(subtest: subtest, accentColor: layoutManager.accentColor)
                        .opacity(index < revealedSubtests ? 1 : 0)
                        .offset(x: index < revealedSubtests ? 0 : -20)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.78),
                            value: revealedSubtests
                        )

                    if index < QmciSubtest.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                            .opacity(index < revealedSubtests - 1 ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: revealedSubtests)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(AssessmentTheme.Content.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                radius: 12, y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .opacity(headerVisible ? 1 : 0)

            Spacer()

            // MARK: Begin Assessment Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                layoutManager.advanceToNextPhase()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Begin Assessment")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(layoutManager.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: layoutManager.accentColor.opacity(0.35), radius: 8, y: 4)
                // Bug 1 fix: separate opacity/offset (driven by showBeginButton) from
                // scale bounce (driven by buttonBounce, set 150ms later).
                .scaleEffect(buttonBounce ? 1.0 : 0.92)
                .opacity(showBeginButton ? 1 : 0)
                .offset(y: showBeginButton ? 0 : 10)
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .disabled(!showBeginButton)
            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showBeginButton)
            .animation(.spring(response: 0.4, dampingFraction: 0.5), value: buttonBounce)

            // MARK: Go to Main Menu
            // Flow 3 fix: disabled until intro completes so user can't interrupt avatar mid-speech.
            Button { onGoToMainMenu?() } label: {
                Text("Go to Main Menu")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MCDesign.Colors.primary500)
            }
            .disabled(!showBeginButton)
            .opacity(showBeginButton ? 1.0 : 0.4)
            .padding(.top, 12)

            Spacer().frame(height: 16)
        }
        .onAppear {
            #if DEBUG
            assert(
                QmciSubtest.allCases.count == 6,
                "introScriptPlain says 'six activities' but QmciSubtest.allCases.count is \(QmciSubtest.allCases.count)"
            )
            #endif

            withAnimation(.easeOut(duration: 0.4)) { headerVisible = true }

            // Flow 4 fix: guard echo + context send so re-appear doesn't replay.
            guard !echoSent else { return }
            echoSent = true
            avatarSetContext(QMCIAvatarContext.welcome)
            avatarSpeak(introScriptForEcho)

            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        revealedSubtests = QmciSubtest.allCases.count
                        showBeginButton = true
                        buttonBounce = true
                    }
                }
                return
            }

            // Flow 1 fix: use welcomeIntroReplicaStarted to short-circuit fallback.
            DispatchQueue.main.asyncAfter(deadline: .now() + revealFallbackDelay) {
                guard !welcomeIntroReplicaStarted && !didAnchorRevealsToSpeaking else { return }
                didAnchorRevealsToSpeaking = true
                startRevealSequence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarStartedSpeaking)) { _ in
            // Bug 3 fix: skip on reduce-motion path — subtests already fully revealed.
            guard !reduceMotion else { return }
            if layoutManager.currentPhase == .welcome {
                welcomeIntroReplicaStarted = true
            }
            guard !didAnchorRevealsToSpeaking else { return }
            didAnchorRevealsToSpeaking = true
            startRevealSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Bug 3 fix: skip on reduce-motion path.
            guard !reduceMotion else { return }
            catchUpRevealsAfterSpeechEnded()
        }
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        guard !revealSequenceScheduled else { return }
        revealSequenceScheduled = true

        let rowSpring = Animation.spring(response: 0.45, dampingFraction: 0.78)
        for (index, delay) in revealDelays.enumerated() {
            // Flow 2 fix: store work items so catch-up can cancel pending timers.
            let item = DispatchWorkItem {
                // Bug 2 fix: max() prevents stale timers from regressing the count.
                withAnimation(rowSpring) {
                    revealedSubtests = max(revealedSubtests, index + 1)
                }
            }
            revealWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        // Bug 1 fix: show button first, bounce 150ms later.
        let buttonItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                showBeginButton = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    buttonBounce = true
                }
            }
        }
        revealWorkItems.append(buttonItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + beginButtonDelay, execute: buttonItem)
    }

    private func catchUpRevealsAfterSpeechEnded() {
        guard revealSequenceScheduled else { return }
        let total = QmciSubtest.allCases.count
        guard revealedSubtests < total || !showBeginButton else { return }

        // Flow 2 fix: cancel pending reveal timers before queuing catch-up stagger.
        revealWorkItems.forEach { $0.cancel() }
        revealWorkItems.removeAll()

        let rowSpring = Animation.spring(response: 0.4, dampingFraction: 0.82)
        let start = revealedSubtests
        if start < total {
            for offset in 0..<(total - start) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(offset)) {
                    withAnimation(rowSpring) {
                        // Bug 2 fix: max() guards against residual race conditions.
                        revealedSubtests = max(revealedSubtests, start + offset + 1)
                    }
                }
            }
        }
        let rowsCatchUpDuration = 0.06 * Double(max(0, total - start))
        DispatchQueue.main.asyncAfter(deadline: .now() + rowsCatchUpDuration + 0.08) {
            guard !showBeginButton else { return }
            // Bug 1 fix: stagger button appearance from bounce.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                showBeginButton = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    buttonBounce = true
                }
            }
        }
    }
}

// MARK: - SubtestRow

private struct SubtestRow: View {
    let subtest: QmciSubtest
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: subtest.iconName)
                .font(.system(size: 16))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            Text(subtest.displayName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)

            Spacer()

            // Hide "0 pts" which would confuse patients.
            if subtest.maxScore > 0 {
                Text("\(subtest.maxScore) pts")
                    .font(.system(size: 13))
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    WelcomePhaseView(layoutManager: AvatarLayoutManager())
        .background(AssessmentTheme.Content.background)
}

//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. The avatar speaks a short, tight intro.
//  Subtest rows reveal in sync with each activity name (timed from
//  conversation.replica.started_speaking, with a delayed fallback if needed).
//  Begin button appears as she says "press Begin Assessment".
//

import SwiftUI

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager
    var onGoToMainMenu: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false
    @State private var echoSent = false
    /// Timed reveal sequence has been scheduled (from replica.started_speaking or fallback).
    @State private var revealSequenceScheduled = false
    /// First `avatarStartedSpeaking` for this view — used to ignore duplicate Tavus events.
    @State private var didAnchorRevealsToSpeaking = false

    // MARK: - Intro Script (single echo)

    private let introScript = "Welcome to your Brain Health Check. We'll go through six quick activities together. First, Orientation. Then, Word Learning. Next, Clock Drawing. After that, Verbal Fluency. Then Story Recall. And finally, Word Recall. When you're ready, press Begin Assessment."

    // MARK: - Reveal Timings (seconds after replica.started_speaking or fallback anchor)
    // Calibrated so each row appears as she begins each activity name (Tavus echo pacing).
    // Script reference (approximate):
    //   ~5.0s  "First, Orientation."
    //   ~6.6s  "Then, Word Learning."
    //   ~8.1s  "Next, Clock Drawing."
    //   ~9.6s  "After that, Verbal Fluency."
    //  ~11.1s  "Then Story Recall."
    //  ~12.6s  "And finally, Word Recall."
    //  ~14.2s  "When you're ready, press Begin Assessment."
    private let revealDelays: [Double] = [
        5.05,  // Orientation
        6.55,  // Word Learning
        8.05,  // Clock Drawing
        9.55,  // Verbal Fluency
        11.05, // Story Recall
        12.55, // Word Recall
    ]
    private let beginButtonDelay: Double = 14.65
    /// If the bridge never posts `avatarStartedSpeaking`, still run the timed sequence.
    private let revealFallbackDelay: Double = 4.0

    var body: some View {
        VStack(spacing: 0) {

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

            // MARK: Subtest List — card shell is always visible, rows reveal one by one
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
                .scaleEffect(showBeginButton ? (buttonBounce ? 1.0 : 0.85) : 0.85)
                .opacity(showBeginButton ? 1 : 0)
                .offset(y: showBeginButton ? 0 : 10)
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .disabled(!showBeginButton)
            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showBeginButton)

            // MARK: Go to Main Menu
            Button { onGoToMainMenu?() } label: {
                Text("Go to Main Menu")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MCDesign.Colors.primary500)
            }
            .padding(.top, 12)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { headerVisible = true }

            avatarSetContext("You are a calm, professional clinical neuropsychologist. Speak exactly the text sent via echo. Do not add your own introduction, do not paraphrase. Speak at a moderate pace with natural pauses.")

            if reduceMotion {
                if !echoSent {
                    echoSent = true
                    avatarSpeak(introScript)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        revealedSubtests = QmciSubtest.allCases.count
                        showBeginButton = true
                        buttonBounce = true
                    }
                }
                return
            }

            // Send the single echo — reveals anchor to replica.started_speaking (or fallback)
            if !echoSent {
                echoSent = true
                avatarSpeak(introScript)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + revealFallbackDelay) {
                if !didAnchorRevealsToSpeaking {
                    didAnchorRevealsToSpeaking = true
                    startRevealSequence()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarStartedSpeaking)) { _ in
            guard !didAnchorRevealsToSpeaking else { return }
            didAnchorRevealsToSpeaking = true
            startRevealSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // If speech ends before timers finish, catch up with a short stagger instead of one pop.
            catchUpRevealsAfterSpeechEnded()
        }
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        guard !revealSequenceScheduled else { return }
        revealSequenceScheduled = true

        let rowSpring = Animation.spring(response: 0.45, dampingFraction: 0.78)
        for (index, delay) in revealDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(rowSpring) {
                    revealedSubtests = index + 1
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + beginButtonDelay) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                showBeginButton = true
                buttonBounce = true
            }
        }
    }

    private func catchUpRevealsAfterSpeechEnded() {
        guard revealSequenceScheduled else { return }
        let total = QmciSubtest.allCases.count
        guard revealedSubtests < total || !showBeginButton else { return }

        let rowSpring = Animation.spring(response: 0.4, dampingFraction: 0.82)
        let start = revealedSubtests
        if start < total {
            for offset in 0..<(total - start) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(offset)) {
                    withAnimation(rowSpring) {
                        revealedSubtests = min(start + offset + 1, total)
                    }
                }
            }
        }
        let rowsCatchUpDuration = 0.06 * Double(max(0, total - start))
        DispatchQueue.main.asyncAfter(deadline: .now() + rowsCatchUpDuration + 0.08) {
            if !showBeginButton {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                    showBeginButton = true
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

            Text("\(subtest.maxScore) pts")
                .font(.system(size: 13))
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    WelcomePhaseView(layoutManager: AvatarLayoutManager())
        .background(AssessmentTheme.Content.background)
}

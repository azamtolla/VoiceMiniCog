//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. The avatar speaks a short, tight intro.
//  Subtest rows reveal ~200ms before she says each name, triggered by
//  conversation.replica.started_speaking (not onAppear).
//  Begin button appears as she says "press Begin Assessment".
//

import SwiftUI

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager
    var onGoToMainMenu: (() -> Void)? = nil

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false
    @State private var echoSent = false
    @State private var revealTriggered = false

    // MARK: - Intro Script (single echo)

    private let introScript = "Welcome to your Brain Health Check. We'll go through six quick activities together. First, Orientation. Then, Word Learning. Next, Clock Drawing. After that, Verbal Fluency. Then Story Recall. And finally, Word Recall. When you're ready, press Begin Assessment."

    // MARK: - Reveal Timings (ms after replica.started_speaking fires)
    // Calibrated to land ~200ms before she says each section name.
    // Avatar reads at ~2.5 words/sec. Script word positions:
    //   0.0s  "Welcome to your Brain Health Check."
    //   2.5s  "We'll go through six quick activities together."
    //   5.0s  "First, Orientation."              ← reveal Orientation at 4.8s
    //   6.5s  "Then, Word Learning."             ← reveal at 6.3s
    //   8.0s  "Next, Clock Drawing."             ← reveal at 7.8s
    //   9.5s  "After that, Verbal Fluency."      ← reveal at 9.3s
    //  11.0s  "Then Story Recall."               ← reveal at 10.8s
    //  12.5s  "And finally, Word Recall."        ← reveal at 12.3s
    //  14.0s  "When you're ready, press Begin Assessment."
    private let revealDelays: [Double] = [
        4.8,   // Orientation
        6.3,   // Word Learning
        7.8,   // Clock Drawing
        9.3,   // Verbal Fluency
        10.8,  // Story Recall
        12.3,  // Word Recall
    ]
    private let beginButtonDelay: Double = 14.5  // As she says "press Begin Assessment"

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

                Text("6 cognitive activities, about 3-5 minutes")
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

            // Send the single echo — reveals will fire when replica.started_speaking arrives
            if !echoSent {
                echoSent = true
                avatarSpeak(introScript)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarStartedSpeaking)) { _ in
            // Trigger only once — the first time the replica starts speaking our echo
            guard !revealTriggered else { return }
            revealTriggered = true
            startRevealSequence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Safety fallback: if she finishes before our timers complete, show everything
            if !showBeginButton {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    revealedSubtests = QmciSubtest.allCases.count
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showBeginButton = true
                    buttonBounce = true
                }
            }
        }
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        // Reveal each subtest row at its calibrated delay
        for (index, delay) in revealDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                revealedSubtests = index + 1
            }
        }

        // Reveal Begin button as she says "press Begin Assessment"
        DispatchQueue.main.asyncAfter(deadline: .now() + beginButtonDelay) {
            showBeginButton = true
            buttonBounce = true
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

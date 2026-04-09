//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. Avatar delivers full engaging intro script.
//  "Begin Assessment" button only appears after the avatar finishes speaking.
//

import SwiftUI

// MARK: - WelcomePhaseView

struct WelcomePhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager

    @State private var showBeginButton = false

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Brain Icon
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)

            // MARK: Title
            Text("Brain Health Assessment")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            // MARK: Subtitle
            Text("6 cognitive activities, about 5-7 minutes")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            // MARK: Subtest List Card
            VStack(spacing: 0) {
                ForEach(Array(QmciSubtest.allCases.enumerated()), id: \.element) { index, subtest in
                    SubtestRow(subtest: subtest, accentColor: layoutManager.accentColor)

                    if index < QmciSubtest.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(AssessmentTheme.Content.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                radius: 12,
                y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()

            // MARK: Begin Assessment Button — only visible after avatar finishes intro
            if showBeginButton {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
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
                    .shadow(
                        color: layoutManager.accentColor.opacity(0.35),
                        radius: 8,
                        y: 4
                    )
                }
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            avatarSetContext("You are a warm, enthusiastic neuroscience avatar delivering an engaging introduction to a brain health assessment. Speak the script sent via echo with energy, warmth, and varied pacing. After finishing the script, tell the patient to press the Begin Assessment button on screen. Do NOT start asking assessment questions. Do NOT advance phases.")
            avatarSpeak(welcomeIntroScript)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Show Begin button when avatar finishes the intro
            withAnimation(.easeInOut(duration: 0.4)) {
                showBeginButton = true
            }
        }
    }

    // MARK: - Full Welcome Intro Script

    private var welcomeIntroScript: String {
        """
        Hey — I'm really glad you're here. \
        What you're about to do in the next few minutes is one of the most genuinely interesting things you can do for your own health. \
        Not a blood draw. Not a treadmill. Not a questionnaire with a hundred 'on a scale of one to ten' questions. \
        We're going to look at your brain — how it remembers, how it thinks, how it moves through the world. \
        And honestly? It's kind of incredible. \
        Here's what most people don't realize: your brain is giving off signals all the time — signals about memory, attention, and processing — and most of those signals go completely unnoticed. \
        Until today. Because today we're actually listening. \
        This assessment — six short activities — is designed by neuroscientists to gently reveal how different parts of your brain are performing right now. \
        Not to judge. Not to alarm. Just to know. And knowing is the most powerful thing there is. \
        We start with something that might sound simple but is actually profound. I'm going to ask you where you are, what day it is, what year. \
        Your brain has to actively construct that answer every single time. It's not stored like a file — it's rebuilt, moment to moment. Ten points. Pretty cool for a warm-up, right? \
        Next, I'm going to say a few words to you. Just words. And your only job is to listen. \
        What's happening in your brain in that moment is extraordinary — your hippocampus is firing, encoding those words into short-term memory. Five points — and they come back later. \
        Then I'm going to ask you to draw a clock. A simple clock. But what your brain has to do — the spatial reasoning, the planning, the sequencing — it's activating multiple brain systems simultaneously. Fifteen points. \
        After that, I'm going to give you a category, and you're going to name as many things in that category as you possibly can. Fast. Really fast. Twenty points. Your brain loves to sprint. \
        Then I'll tell you a short story, and later I'll ask you about it. Thirty points — the biggest block in the whole assessment. So listen closely. Every word counts. \
        And finally, those words from the very beginning? It's time to bring them back. Twenty points. \
        Six activities. Five to seven minutes. And at the end, you'll know something real about how your brain is working today. \
        Not a diagnosis. Not a verdict. A snapshot of one of the most complex objects in the known universe: your brain. \
        I'll be right here with you, every step of the way. \
        Whenever you're ready, press the Begin Assessment button on the screen, and let's get started.
        """
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

// MARK: - Preview

#Preview {
    WelcomePhaseView(
        layoutManager: AvatarLayoutManager(),
    )
    .background(AssessmentTheme.Content.background)
}

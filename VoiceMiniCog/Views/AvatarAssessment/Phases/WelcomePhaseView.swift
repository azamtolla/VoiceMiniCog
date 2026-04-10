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
            avatarSetContext("You are a board-certified clinical neuropsychologist introducing a standardized cognitive assessment. Speak with a calm, measured, professional tone. Warm but clinical. Clear enunciation, moderate pace. No slang, no exclamation marks, no performance feedback. After the introduction, instruct the patient to press the Begin Assessment button.")
            avatarSpeak(welcomeIntroScript)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                showBeginButton = true
            }
        }
    }

    // MARK: - Welcome Intro Script (Neuropsychologist Voice)

    private var welcomeIntroScript: String {
        """
        Good morning. Thank you for coming in today. My name is Dr. Anna, and I am a clinical neuropsychologist. \
        I will be guiding you through a brief cognitive assessment. This is a standardized screening tool that helps us understand how different areas of your brain are functioning right now. \
        The assessment consists of six short activities. Each one looks at a different aspect of cognitive function. Let me walk you through what to expect. \
        First, I will ask you a few orientation questions — things like today's date and where we are. These questions help us assess your awareness of time and place. \
        Second, I will read you five words and ask you to repeat them back to me. This measures your ability to register and hold new information in working memory. \
        Third, I will ask you to draw a clock face and set it to a specific time. This is a well-established test of visuospatial ability and executive function — how your brain plans and organizes. \
        Fourth, I will ask you to recall those five words from earlier. This measures your delayed memory — how well your brain retains information over a short period. \
        Fifth, I will ask you to name as many animals as you can in one minute. This assesses your verbal fluency — how quickly and flexibly your brain can search and retrieve information. \
        And finally, I will read you a short story and ask you to repeat it back in as much detail as you can. This is the most sensitive part of the assessment. It measures your episodic memory — your ability to encode and recall meaningful information. \
        The entire assessment takes approximately three to five minutes. There are no trick questions, and there is no pass or fail. I am simply gathering information to help your clinician understand your cognitive health. \
        I will be here with you throughout. If you have any questions during the assessment, please feel free to ask. \
        When you are ready to begin, please press the Begin Assessment button on the screen.
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

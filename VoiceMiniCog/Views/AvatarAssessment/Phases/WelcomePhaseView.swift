//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. Avatar introduces the assessment as a
//  neuropsychologist. Each subtest row reveals as the avatar describes it.
//  Begin Assessment button appears with a bounce after the avatar finishes.
//

import SwiftUI

// MARK: - WelcomePhaseView

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false

    // Timing: seconds after avatar starts speaking when each subtest is mentioned.
    // Matches the neuropsychologist intro script structure.
    private let subtestRevealDelays: [Double] = [
        16,   // Orientation — "First, I will ask you a few orientation questions..."
        26,   // Word Learning — "Second, I will read you five words..."
        36,   // Clock Drawing — "Third, I will ask you to draw a clock face..."
        46,   // Word Recall — "Fourth, I will ask you to recall those five words..."
        54,   // Verbal Fluency — "Fifth, I will ask you to name as many animals..."
        64,   // Story Recall — "And finally, I will read you a short story..."
    ]

    // Begin button appears after avatar finishes (~85 seconds)
    private let beginButtonDelay: Double = 80

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Header (fades in immediately)
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

            // MARK: Subtest List Card — rows reveal one by one
            VStack(spacing: 0) {
                ForEach(Array(QmciSubtest.allCases.enumerated()), id: \.element) { index, subtest in
                    if index < revealedSubtests {
                        SubtestRow(subtest: subtest, accentColor: layoutManager.accentColor)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))

                        if index < QmciSubtest.allCases.count - 1 && index < revealedSubtests - 1 {
                            Divider()
                                .padding(.leading, 44)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .background(revealedSubtests > 0 ? AssessmentTheme.Content.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: revealedSubtests > 0
                    ? AssessmentTheme.Content.shadowColor.opacity(0.08)
                    : Color.clear,
                radius: 12,
                y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .animation(.easeOut(duration: 0.4), value: revealedSubtests)

            Spacer()

            // MARK: Begin Assessment Button — bouncy entrance after avatar finishes
            if showBeginButton {
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
                    .shadow(
                        color: layoutManager.accentColor.opacity(0.35),
                        radius: 8,
                        y: 4
                    )
                    .scaleEffect(buttonBounce ? 1.0 : 0.85)
                }
                .buttonStyle(AssessmentPrimaryButtonStyle())
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            Spacer().frame(height: 16)
        }
        .onAppear {
            // 1. Show header immediately
            withAnimation(.easeOut(duration: 0.4)) {
                headerVisible = true
            }

            // 2. Set neuropsychologist context
            avatarSetContext("You are a board-certified clinical neuropsychologist introducing a standardized cognitive assessment. Speak with a calm, measured, professional tone. Warm but clinical. Clear enunciation, moderate pace. No slang, no exclamation marks, no performance feedback. After the introduction, instruct the patient to press the Begin Assessment button.")

            // 3. Avatar speaks the full intro
            avatarSpeak(welcomeIntroScript)

            // 4. Reveal each subtest row timed to the avatar's speech
            for (index, delay) in subtestRevealDelays.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        revealedSubtests = index + 1
                    }
                }
            }

            // 5. Show Begin button with bounce after avatar finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + beginButtonDelay) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showBeginButton = true
                    buttonBounce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Backup: if avatar finishes before timer, show button immediately
            if !showBeginButton {
                // Reveal any remaining subtests
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    revealedSubtests = QmciSubtest.allCases.count
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        showBeginButton = true
                        buttonBounce = true
                    }
                }
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
        layoutManager: AvatarLayoutManager()
    )
    .background(AssessmentTheme.Content.background)
}

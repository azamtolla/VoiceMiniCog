//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. Avatar introduces the assessment as a
//  neuropsychologist. Each subtest row reveals AFTER the avatar finishes
//  describing it. Begin Assessment button bounces in at the end.
//
//  Sync method: The intro is sent as sequential echo calls. After each
//  echo completes (avatarDoneSpeaking), the corresponding subtest row
//  reveals and the next echo fires. This guarantees visual-audio sync.
//

import SwiftUI

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager
    var onGoToMainMenu: (() -> Void)? = nil

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false
    @State private var currentIntroStep = 0
    @State private var introStarted = false

    // The intro is split into sequential segments. After each segment,
    // the avatar pauses, the corresponding subtest reveals, then the next plays.
    private let introSegments: [(text: String, revealsSubtest: Bool)] = [
        // Segment 0: Opening (no subtest reveal)
        ("Good morning. Thank you for coming in today. My name is Dr. Anna, and I am a clinical neuropsychologist. I will be guiding you through a brief cognitive assessment. This is a standardized screening tool that helps us understand how different areas of your brain are functioning right now. The assessment consists of six short activities. Let me walk you through what to expect.", false),

        // Segment 1: Orientation → reveals row 1
        ("First, I will ask you a few orientation questions — things like today's date and where we are. These questions help us assess your awareness of time and place.", true),

        // Segment 2: Word Learning → reveals row 2
        ("Second, I will read you five words and ask you to repeat them back to me. This measures your ability to register and hold new information in working memory.", true),

        // Segment 3: Clock Drawing → reveals row 3
        ("Third, I will ask you to draw a clock face and set it to a specific time. This is a well-established test of visuospatial ability and executive function — how your brain plans and organizes.", true),

        // Segment 4: Word Recall → reveals row 4
        ("Fourth, I will ask you to recall those five words from earlier. This measures your delayed memory — how well your brain retains information over a short period.", true),

        // Segment 5: Verbal Fluency → reveals row 5
        ("Fifth, I will ask you to name as many animals as you can in one minute. This assesses your verbal fluency — how quickly and flexibly your brain can search and retrieve information.", true),

        // Segment 6: Story Recall → reveals row 6
        ("And finally, I will read you a short story and ask you to repeat it back in as much detail as you can. This is the most sensitive part of the assessment. It measures your episodic memory — your ability to encode and recall meaningful information.", true),

        // Segment 7: Closing (triggers Begin button)
        ("The entire assessment takes approximately three to five minutes. There are no trick questions, and there is no pass or fail. I am simply gathering information to help your clinician understand your cognitive health. I will be here with you throughout. When you are ready to begin, please press the Begin Assessment button on the screen.", false),
    ]

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

            // MARK: Subtest List — rows reveal one by one as avatar describes each
            VStack(spacing: 0) {
                ForEach(Array(QmciSubtest.allCases.enumerated()), id: \.element) { index, subtest in
                    if index < revealedSubtests {
                        SubtestRow(subtest: subtest, accentColor: layoutManager.accentColor)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))

                        if index < min(revealedSubtests - 1, QmciSubtest.allCases.count - 1) {
                            Divider()
                                .padding(.leading, 44)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.vertical, revealedSubtests > 0 ? 8 : 0)
            .background(revealedSubtests > 0 ? AssessmentTheme.Content.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: revealedSubtests > 0
                    ? AssessmentTheme.Content.shadowColor.opacity(0.08)
                    : Color.clear,
                radius: 12, y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: revealedSubtests)

            Spacer()

            // MARK: Begin Assessment Button — bouncy entrance
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
                    .shadow(color: layoutManager.accentColor.opacity(0.35), radius: 8, y: 4)
                    .scaleEffect(buttonBounce ? 1.0 : 0.85)
                }
                .buttonStyle(AssessmentPrimaryButtonStyle())
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

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

            avatarSetContext("You are a board-certified clinical neuropsychologist introducing a standardized cognitive assessment. Speak with a calm, measured, professional tone. Warm but clinical. Clear enunciation, moderate pace. No slang, no exclamation marks, no performance feedback.")

            // Start the first segment
            speakNextSegment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            guard introStarted else { return }
            advanceIntro()
        }
    }

    // MARK: - Sequential Intro Playback

    private func speakNextSegment() {
        guard currentIntroStep < introSegments.count else { return }
        introStarted = true
        let segment = introSegments[currentIntroStep]
        avatarSpeak(segment.text)
    }

    private func advanceIntro() {
        let justFinished = currentIntroStep
        guard justFinished < introSegments.count else { return }

        let segment = introSegments[justFinished]

        // Reveal subtest row if this segment maps to one
        if segment.revealsSubtest {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                revealedSubtests += 1
            }
        }

        // Move to next segment
        currentIntroStep = justFinished + 1

        if currentIntroStep < introSegments.count {
            // Brief pause between segments for natural pacing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                speakNextSegment()
            }
        } else {
            // All segments done — show Begin button with bounce
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
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

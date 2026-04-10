//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. The entire intro is sent as ONE echo call.
//  Subtest rows reveal at pre-calculated times based on word count
//  at ~2.5 words/second (calm neuropsychologist pace). No chaining,
//  no sequential echo calls, no avatarDoneSpeaking dependency.
//

import SwiftUI

struct WelcomePhaseView: View {

    let layoutManager: AvatarLayoutManager
    var onGoToMainMenu: (() -> Void)? = nil

    @State private var showBeginButton = false
    @State private var buttonBounce = false
    @State private var revealedSubtests = 0
    @State private var headerVisible = false

    // MARK: - Intro Script Segments

    // Each segment: (text, cumulative word count up to end of this segment)
    // Used to calculate when the avatar reaches each section.
    // At ~2.5 words/second (calm clinical pace), we can predict reveal times.
    private static let segments: [(text: String, revealsSubtest: Bool)] = [
        // Opening — 68 words ≈ 27s
        ("Hello, and welcome to your Brain Health Assessment. On the left side of the screen, you will see an overview of the activities we will complete together. This is a brief, standardized cognitive screening. It will take approximately three to five minutes, and it will help your clinician understand how different areas of your brain are functioning today. There are six short activities. Let me explain each one.", false),

        // Orientation — 25 words ≈ 10s
        ("First, orientation. I will ask you a few simple questions, such as today's date and what country we are in.", true),

        // Word Learning — 28 words ≈ 11s
        ("Second, word registration. I will read you five words and ask you to repeat them back. This measures how well you take in new information.", true),

        // Clock Drawing — 30 words ≈ 12s
        ("Third, clock drawing. I will ask you to draw a clock and set it to a specific time. This tests how your brain plans and organizes visually.", true),

        // Word Recall — 27 words ≈ 11s
        ("Fourth, delayed recall. After a short break, I will ask you to remember those five words from earlier. This measures how well your memory holds over time.", true),

        // Verbal Fluency — 24 words ≈ 10s
        ("Fifth, verbal fluency. I will ask you to name as many animals as you can in one minute. This measures how quickly your brain retrieves information.", true),

        // Story Recall — 32 words ≈ 13s
        ("And finally, logical memory. I will read you a short story, and then ask you to repeat back as much as you can remember. This is the most sensitive part of the assessment.", true),

        // Closing — 30 words ≈ 12s
        ("There are no trick questions and there is no pass or fail. When you are ready, press the Begin Assessment button on the screen.", false),
    ]

    // Pre-calculated reveal times (seconds from start) based on cumulative word count at 2.5 words/sec
    // Segment word counts: 68, 25, 28, 30, 27, 24, 32, 30
    // Cumulative: 68, 93, 121, 151, 178, 202, 234, 264
    // At 2.5 w/s: 27.2, 37.2, 48.4, 60.4, 71.2, 80.8, 93.6, 105.6
    private let revealTimes: [Double] = [
        28,   // Orientation appears (after opening finishes)
        38,   // Word Learning
        50,   // Clock Drawing
        62,   // Word Recall (delayed recall)
        73,   // Verbal Fluency
        87,   // Story Recall
    ]
    private let beginButtonTime: Double = 100  // Begin button appears

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

            // MARK: Subtest List — rows reveal timed to avatar speech
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

            // MARK: Begin Assessment Button
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
            // Show header
            withAnimation(.easeOut(duration: 0.4)) { headerVisible = true }

            // Set persona
            avatarSetContext("You are a board-certified clinical neuropsychologist. Speak with a calm, measured, professional tone. Clear enunciation, moderate pace. No slang, no exclamation marks. Speak the text exactly as provided.")

            // Send the ENTIRE intro as one echo — avatar speaks it continuously
            let fullScript = Self.segments.map(\.text).joined(separator: " ")
            avatarSpeak(fullScript)

            // Reveal subtests at pre-calculated times
            for (index, time) in revealTimes.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        revealedSubtests = index + 1
                    }
                }
            }

            // Begin button with bounce
            DispatchQueue.main.asyncAfter(deadline: .now() + beginButtonTime) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showBeginButton = true
                    buttonBounce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Backup: if avatar finishes before timers, reveal everything
            if !showBeginButton {
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

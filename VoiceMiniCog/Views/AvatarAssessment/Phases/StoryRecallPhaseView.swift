//
//  StoryRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 8 — Story Recall. Avatar narrates a short logical memory story
//  while the patient listens, then the patient retells the story aloud.
//

import SwiftUI

// MARK: - StoryRecallPhaseView

struct StoryRecallPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var phase: StoryPhase = .listening
    @State private var contentVisible = false

    enum StoryPhase { case listening, recalling }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Icon
            Image(systemName: phase == .listening ? "book.fill" : "mic.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentIconHeaderAccent(layoutManager.accentColor)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Title
            Text(phase == .listening
                 ? LeftPaneSpeechCopy.storyRecallListeningTitle
                 : LeftPaneSpeechCopy.storyRecallRecallingTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Subtitle
            Text(phase == .listening
                 ? LeftPaneSpeechCopy.storyRecallListeningSubtitle
                 : LeftPaneSpeechCopy.storyRecallRecallingSubtitle)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            Spacer()

            // MARK: Action Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                if phase == .listening {
                    contentVisible = false
                    withAnimation(AssessmentTheme.Anim.contentFade) { phase = .recalling }
                    layoutManager.setAvatarListening()
                    // Re-animate content enter for the recalling phase
                    withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                        contentVisible = true
                    }
                } else {
                    layoutManager.advanceToNextPhase()
                }
            } label: {
                Text(phase == .listening
                     ? "Story Finished — Begin Recall"
                     : "Continue to Word Recall")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)
            .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            // Avatar speaks the story intro + reads the story text
            let story = qmciState.currentStory
            avatarSpeak(LeftPaneSpeechCopy.storyRecallIntro)
            // After a brief pause for the intro, read the story
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                if phase == .listening {
                    avatarSpeak(story.voiceText)
                }
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .recalling {
                layoutManager.avatarBehavior = .speaking
                avatarSpeak(LeftPaneSpeechCopy.storyRecallPrompt)
                // Switch to listening after the prompt (~4s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    layoutManager.setAvatarListening()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Listening") {
    StoryRecallPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: QmciState()
    )
    .background(AssessmentTheme.Content.background)
}

#Preview("Recalling") {
    let view = StoryRecallPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: QmciState()
    )
    return view
        .background(AssessmentTheme.Content.background)
}

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
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Title
            Text(phase == .listening
                 ? "Listen carefully to\nthis short story"
                 : "Now tell me everything\nyou remember")
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Subtitle
            Text(phase == .listening
                 ? "The avatar is reading a story.\nPay close attention."
                 : "Take your time. Say everything\nyou can recall.")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .animation(AssessmentTheme.Anim.contentFade, value: phase)

            Spacer()

            // MARK: Action Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                if phase == .listening {
                    withAnimation(AssessmentTheme.Anim.contentFade) { phase = .recalling }
                    layoutManager.setAvatarListening()
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
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .animation(AssessmentTheme.Anim.contentFade, value: phase)

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            // Avatar speaks the story intro + reads the story text
            let story = qmciState.currentStory
            let intro = "I'm going to read you a short story. Listen carefully and try to remember as much of it as you can. When I'm finished, I'll ask you to tell me everything you can recall — even small details. Ready?"
            avatarSpeak(intro)
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
                avatarSpeak("Now tell me everything you can remember about that story — start from the beginning and tell me as much as you can.")
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

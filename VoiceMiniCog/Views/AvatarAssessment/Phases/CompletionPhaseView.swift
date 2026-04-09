//
//  CompletionPhaseView.swift
//  VoiceMiniCog
//
//  Terminal phase for the caregiver QDRS flow.
//  Shows a thank-you message and a button to return home.
//

import SwiftUI

struct CompletionPhaseView: View {

    let onComplete: () -> Void

    @State private var contentVisible = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Checkmark icon
            ZStack {
                Circle()
                    .fill(AssessmentTheme.Phase.results.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AssessmentTheme.Phase.results)
            }
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            Text("Questionnaire Complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            Text("Thank you for completing the\ncaregiver questionnaire.")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            Spacer()

            // Return home button
            MCPrimaryButton("Return Home", icon: "house.fill", color: AssessmentTheme.Phase.results) {
                onComplete()
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSpeak(LeftPaneSpeechCopy.closingThankYou)
        }
    }
}

#Preview {
    CompletionPhaseView(onComplete: {})
        .background(AssessmentTheme.Content.background)
}

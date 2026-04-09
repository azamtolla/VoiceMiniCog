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

    @State private var appeared = false

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
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)

            Text("Questionnaire Complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .opacity(appeared ? 1 : 0)

            Text("Thank you for completing the\ncaregiver questionnaire.")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Spacer()

            // Return home button
            MCPrimaryButton("Return Home", icon: "house.fill", color: AssessmentTheme.Phase.results) {
                onComplete()
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                appeared = true
            }
        }
    }
}

#Preview {
    CompletionPhaseView(onComplete: {})
        .background(AssessmentTheme.Content.background)
}

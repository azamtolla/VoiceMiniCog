//
//  CompletionPhaseView.swift
//  VoiceMiniCog
//
//  Terminal phase for the avatar-guided cognitive assessment.
//  Shows a thank-you message and a button to return home.
//

import SwiftUI

struct CompletionPhaseView: View {

    let onComplete: () -> Void
    let assessmentState: AssessmentState
    @State private var showReport = false

    @State private var contentVisible = false
    @State private var avatarSpeaking = true

    var body: some View {
        VStack(spacing: 24) {
            PhaseHeaderBadge(
                phaseName: "Complete",
                icon: "checkmark.circle.fill",
                accentColor: AssessmentTheme.Phase.results
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20).padding(.leading, 20)

            Spacer()

            // Checkmark icon
            ZStack {
                Circle()
                    .fill(AssessmentTheme.Phase.results.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AssessmentTheme.Phase.results)
            }
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            Text("Assessment Complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            Text("Thank you for completing the\ncognitive assessment.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            Spacer()

            // Return home — disabled until avatar finishes closing speech
            MCPrimaryButton("Return Home", icon: "house.fill", color: AssessmentTheme.Phase.results) {
                onComplete()
            }
            .disabled(avatarSpeaking)
            .opacity(avatarSpeaking ? 0.5 : 1.0)
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            MCSecondaryButton("Review Clinical Report",
                              icon: "doc.text.magnifyingglass",
                              color: AssessmentTheme.Phase.results) {
                showReport = true
            }
            .disabled(avatarSpeaking)
            .opacity(avatarSpeaking ? 0.5 : 1.0)
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.30), value: contentVisible)

            Spacer()
        }
        .onAppear {
            guard !contentVisible else { return }

            avatarInterrupt()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }

            // Use avatarSetContext directly — completion phase does not need
            // the "never correct patient" rule that avatarSetAssessmentContext appends.
            avatarSetContext(QMCIAvatarContext.completion)

            // Small delay ensures the interrupt notification is processed
            // before the speak notification, guaranteeing ordering.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                avatarSpeak(LeftPaneSpeechCopy.closingThankYou)
            }

            // Fallback: enable button after 6s in case the avatar is disconnected
            // and .avatarDoneSpeaking never fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                guard avatarSpeaking else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    avatarSpeaking = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            // Phase guard: only act on this notification if the completion
            // phase is actually visible. A stale notification from a prior
            // phase (e.g., story recall closing utterance) could race and
            // prematurely enable the buttons.
            guard contentVisible else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                avatarSpeaking = false
            }
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                PCPReportView(
                    state: assessmentState,
                    onRestart: {
                        showReport = false
                    },
                    onFinalize: {
                        showReport = false
                        onComplete()
                    }
                )
            }
            .interactiveDismissDisabled(true)
        }
    }
}

#Preview {
    @Previewable @State var completed = false
    CompletionPhaseView(onComplete: { completed = true }, assessmentState: AssessmentState())
        .background(AssessmentTheme.Content.background)
        .overlay(alignment: .top) {
            if completed {
                Text("onComplete fired")
                    .font(.caption)
                    .padding(8)
                    .background(.green.opacity(0.2), in: .capsule)
                    .padding(.top, 60)
            }
        }
}

//
//  WordRegistrationPhaseView.swift
//  VoiceMiniCog
//
//  Phase 5 — Word Registration. The avatar reads 5 words aloud while
//  word chips appear progressively on screen (one every 1.5 s).
//

import SwiftUI

// MARK: - WordRegistrationPhaseView

struct WordRegistrationPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var revealedCount = 0
    @State private var isRevealing = false
    @State private var contentVisible = false

    private var words: [String] { qmciState.registrationWords }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Ear Icon
            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentIconHeaderAccent(layoutManager.accentColor)

            // MARK: Title
            Text(LeftPaneSpeechCopy.wordRegistrationTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: Subtitle
            Text(LeftPaneSpeechCopy.wordRegistrationSubtitle)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // MARK: Word Chips
            if !words.isEmpty {
                HStack(spacing: 10) {
                    ForEach(0..<words.count, id: \.self) { index in
                        WordChip(
                            word: words[index],
                            isRevealed: index < revealedCount,
                            accentColor: layoutManager.accentColor
                        )
                    }
                }
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)
            }

            Spacer()

            // MARK: Continue Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                layoutManager.advanceToNextPhase()
            } label: {
                Text("Continue to Clock Drawing")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: layoutManager.accentColor.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.22), value: contentVisible)

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetContext("You are a clinical neuropsychologist administering the Word Registration subtest. Read the five words slowly and clearly, one per second, exactly as provided via echo commands. Do not add any words of your own. Do not provide feedback on the patient's recall. If the patient speaks between words, respond briefly: 'Let us continue.' Maintain a calm, professional tone throughout.")
            if words.isEmpty {
                qmciState.selectWordList()
            }
            startWordReveal()
            avatarSpeak(LeftPaneSpeechCopy.wordRegistrationNarration(words: qmciState.registrationWords))
        }
    }

    // MARK: Progressive Reveal

    private func startWordReveal() {
        guard !isRevealing else { return }
        isRevealing = true
        for i in 0..<words.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                withAnimation(AssessmentTheme.Anim.chipAppear) { revealedCount = i + 1 }
            }
        }
    }
}

// MARK: - WordChip

private struct WordChip: View {

    let word: String
    let isRevealed: Bool
    let accentColor: Color

    var body: some View {
        Text(isRevealed ? word : "...")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(
                isRevealed
                    ? AssessmentTheme.Content.textPrimary
                    : AssessmentTheme.Content.textSecondary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isRevealed
                    ? accentColor.opacity(0.12)
                    : Color.gray.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isRevealed ? 1.0 : 0.9)
            .animation(AssessmentTheme.Anim.chipAppear, value: isRevealed)
    }
}

// MARK: - Preview

#Preview {
    let layoutManager = AvatarLayoutManager()
    let qmciState = QmciState()
    qmciState.selectWordList()

    return WordRegistrationPhaseView(
        layoutManager: layoutManager,
        qmciState: qmciState
    )
    .background(AssessmentTheme.Content.background)
}

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

    private var words: [String] { qmciState.registrationWords }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Ear Icon
            Image(systemName: "ear.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)

            // MARK: Title
            Text("Listen carefully")
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            // MARK: Subtitle
            Text("The avatar will say 5 words.\nRepeat them back when asked.")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

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
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            if words.isEmpty {
                qmciState.selectWordList()
            }
            startWordReveal()
        }
    }

    // MARK: Progressive Reveal

    private func startWordReveal() {
        guard !isRevealing else { return }
        isRevealing = true

        // Avatar speaks the intro prompt
        let introWords = words.joined(separator: "... ")
        avatarSpeak("I'm going to read you five words. Please listen carefully and try to remember them — I'll ask you about them again later. The words are: \(introWords).")

        for i in 0..<words.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                withAnimation(AssessmentTheme.Anim.chipAppear) { revealedCount = i + 1 }
            }
        }

        // After all words revealed, avatar asks for repetition
        let totalRevealTime = Double(words.count) * 1.5 + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + totalRevealTime) {
            avatarSpeak("Can you repeat those words for me?")
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

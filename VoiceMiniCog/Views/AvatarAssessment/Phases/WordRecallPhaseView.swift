//
//  WordRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 9 — Word Recall. Clinician marks each of the 5 registration words
//  as correctly recalled or not. Final score saved to qmciState.delayedRecallWords.
//

import SwiftUI

// MARK: - WordRecallPhaseView

struct WordRecallPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState
    let onComplete: () -> Void

    @State private var recallResults: [Bool?]
    @State private var contentVisible = false

    // MARK: Init

    init(
        layoutManager: AvatarLayoutManager,
        qmciState: QmciState,
        onComplete: @escaping () -> Void
    ) {
        self.layoutManager = layoutManager
        self.qmciState = qmciState
        self.onComplete = onComplete
        _recallResults = State(initialValue: Array(repeating: nil, count: qmciState.registrationWords.count))
    }

    // MARK: Computed Properties

    private var words: [String] { qmciState.registrationWords }

    private var recalledCount: Int {
        recallResults.compactMap { $0 }.filter { $0 }.count
    }

    private var allMarked: Bool {
        recallResults.allSatisfy { $0 != nil }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Icon
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)
                .assessmentIconHeaderAccent(layoutManager.accentColor)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // MARK: Title
            Text(LeftPaneSpeechCopy.wordRecallTitle)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // MARK: Word Card
            VStack(spacing: 0) {
                ForEach(0..<words.count, id: \.self) { index in
                    wordRow(index: index)

                    if index < words.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(AssessmentTheme.Content.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                radius: 12,
                y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.18), value: contentVisible)

            // MARK: Score Display
            if allMarked {
                Text("\(recalledCount)/\(words.count) recalled")
                    .font(AssessmentTheme.Fonts.scoreDisplay)
                    .foregroundStyle(layoutManager.accentColor)
                    .padding(.top, 20)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // MARK: Complete Button
            if allMarked {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    qmciState.delayedRecallWords = words.enumerated().compactMap { i, w in
                        recallResults[i] == true ? w : nil
                    }
                    onComplete()
                } label: {
                    Text("Complete Assessment")
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
                }
                .buttonStyle(AssessmentPrimaryButtonStyle())
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)
                .transition(.scale.combined(with: .opacity))
            }

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            layoutManager.setAvatarSpeaking()
            avatarSpeak(LeftPaneSpeechCopy.wordRecallPrompt)
            // Switch to listening after avatar finishes speaking (~3s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                layoutManager.setAvatarListening()
            }
        }
    }

    // MARK: - Word Row

    private func wordRow(index: Int) -> some View {
        HStack(spacing: 12) {
            // Word label
            Text(words[index])
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .strikethrough(recallResults[index] == false, color: AssessmentTheme.Content.textSecondary)

            Spacer()

            // Correct button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(AssessmentTheme.Anim.buttonPress) {
                    recallResults[index] = true
                }
            } label: {
                Image(systemName: recallResults[index] == true
                      ? "checkmark.circle.fill"
                      : "checkmark.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(
                        recallResults[index] == true
                            ? Color(hex: "#34C759")
                            : Color.gray.opacity(0.30)
                    )
            }
            .buttonStyle(.plain)

            // Incorrect button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(AssessmentTheme.Anim.buttonPress) {
                    recallResults[index] = false
                }
            } label: {
                Image(systemName: recallResults[index] == false
                      ? "xmark.circle.fill"
                      : "xmark.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(
                        recallResults[index] == false
                            ? Color(hex: "#FF3B30")
                            : Color.gray.opacity(0.30)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview {
    let layoutManager = AvatarLayoutManager()
    let qmciState = QmciState()
    qmciState.selectWordList()

    return WordRecallPhaseView(
        layoutManager: layoutManager,
        qmciState: qmciState,
        onComplete: {}
    )
    .background(AssessmentTheme.Content.background)
}

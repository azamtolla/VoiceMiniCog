//
//  QAPhaseView.swift
//  VoiceMiniCog
//
//  Reusable Q&A template for QDRS (10 questions), PHQ-2 (2 questions),
//  and Orientation (5 questions). Shows question text, answer buttons,
//  and progress. Avatar asks questions vocally; this provides visual
//  reinforcement and clinician scoring.
//

import SwiftUI

// MARK: - QAPhaseView

struct QAPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var assessmentState: AssessmentState
    let phaseID: AssessmentPhaseID

    @State private var currentIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var animateIn = false

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            VStack(spacing: 20) {

                // Question counter
                Text("\(currentIndex + 1) of \(totalQuestions)")
                    .font(AssessmentTheme.Fonts.timerSmall)
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)

                // Question text
                Text(currentQuestionText)
                    .font(AssessmentTheme.Fonts.question)
                    .foregroundStyle(AssessmentTheme.Content.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 10)

                // Answer buttons
                VStack(spacing: 8) {
                    ForEach(Array(currentAnswers.enumerated()), id: \.offset) { index, answer in
                        answerButton(text: answer, index: index)
                    }
                }
                .opacity(animateIn ? 1 : 0)
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()

            // Orientation dots (only for orientation phase)
            if phaseID == .orientation {
                orientationFooter
                    .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
                animateIn = true
            }
            // Avatar speaks the first question when phase appears
            avatarSpeak(currentVoicePrompt)
        }
        .onChange(of: currentIndex) { _, _ in
            animateIn = false
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                animateIn = true
            }
            // Avatar speaks each new question as it appears on screen
            avatarSpeak(currentVoicePrompt)
        }
    }

    // MARK: - Answer Button

    private func answerButton(text: String, index: Int) -> some View {
        Button {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            selectedAnswer = index
            recordAnswer(index)
            layoutManager.acknowledgeAnswer()

            // Auto-advance after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if currentIndex < totalQuestions - 1 {
                    selectedAnswer = nil
                    currentIndex += 1
                } else {
                    layoutManager.advanceToNextPhase()
                }
            }
        } label: {
            Text(text)
                .font(AssessmentTheme.Fonts.buttonLabel)
                .foregroundStyle(
                    selectedAnswer == index
                        ? AssessmentTheme.Button.selectedText
                        : AssessmentTheme.Button.normalText
                )
                .frame(maxWidth: .infinity)
                .frame(height: AssessmentTheme.Sizing.buttonMinHeight)
                .background(
                    selectedAnswer == index
                        ? layoutManager.accentColor
                        : AssessmentTheme.Button.normalFill
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            selectedAnswer == index
                                ? Color.clear
                                : Color.black.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(
                    color: selectedAnswer == index
                        ? layoutManager.accentColor.opacity(0.30)
                        : .clear,
                    radius: selectedAnswer == index ? 8 : 0,
                    y: selectedAnswer == index ? 4 : 0
                )
        }
        .buttonStyle(.plain)
        .disabled(selectedAnswer != nil)
    }

    // MARK: - Orientation Footer

    private var orientationFooter: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(orientationDotColor(at: i))
                    .frame(width: 10, height: 10)
            }
            Spacer()
            Text("\(assessmentState.qmciState.orientationScore)/10")
                .font(AssessmentTheme.Fonts.timerSmall)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
        }
    }

    // MARK: - Data Helpers

    private var totalQuestions: Int {
        switch phaseID {
        case .qdrs:         return QDRS_QUESTIONS.count
        case .phq2:         return PHQ2_QUESTIONS.count
        case .orientation:  return ORIENTATION_ITEMS.count
        default:            return 0
        }
    }

    private var currentQuestionText: String {
        switch phaseID {
        case .qdrs:
            return QDRS_QUESTIONS[safe: currentIndex]?.text ?? ""
        case .phq2:
            return PHQ2_QUESTIONS[safe: currentIndex] ?? ""
        case .orientation:
            return ORIENTATION_ITEMS[safe: currentIndex]?.question ?? ""
        default:
            return ""
        }
    }

    /// Voice prompt for the avatar — matches the on-screen question text
    private var currentVoicePrompt: String {
        switch phaseID {
        case .qdrs:
            return QDRS_QUESTIONS[safe: currentIndex]?.voicePrompt ?? ""
        case .phq2:
            return PHQ2_QUESTIONS[safe: currentIndex] ?? ""
        case .orientation:
            return ORIENTATION_ITEMS[safe: currentIndex]?.voicePrompt ?? ""
        default:
            return ""
        }
    }

    private var currentAnswers: [String] {
        switch phaseID {
        case .qdrs:
            return ["No Change", "Sometimes", "Yes, Changed"]
        case .phq2:
            return ["Not at all", "Several days", "More than half the days", "Nearly every day"]
        case .orientation:
            return ["Correct", "Incorrect"]
        default:
            return []
        }
    }

    // MARK: - Record Answer

    private func recordAnswer(_ index: Int) {
        switch phaseID {
        case .qdrs:
            // QDRSAnswer rawValues are Strings; map index → case
            let answer: QDRSAnswer
            switch index {
            case 0: answer = .normal
            case 1: answer = .sometimes
            default: answer = .changed
            }
            assessmentState.qdrsState.answers[currentIndex] = answer

        case .phq2:
            let answer = PHQ2Answer(rawValue: index) ?? .notAtAll
            assessmentState.phq2State.answers[currentIndex] = answer

        case .orientation:
            if currentIndex < assessmentState.qmciState.orientationAnswers.count {
                assessmentState.qmciState.orientationAnswers[currentIndex] = (index == 0)
            }

        default:
            break
        }
    }

    // MARK: - Orientation Dot Color

    private func orientationDotColor(at index: Int) -> Color {
        guard index < assessmentState.qmciState.orientationAnswers.count else {
            return Color.gray.opacity(0.2)
        }
        guard let answer = assessmentState.qmciState.orientationAnswers[safe: index] else {
            return Color.gray.opacity(0.2)
        }
        if let correct = answer {
            return correct ? Color(hex: "#34C759") : Color(hex: "#FF3B30")
        }
        return Color.gray.opacity(0.2)
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("QDRS Phase") {
    QAPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState(),
        phaseID: .qdrs
    )
    .background(AssessmentTheme.Content.background)
}

#Preview("PHQ-2 Phase") {
    QAPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState(),
        phaseID: .phq2
    )
    .background(AssessmentTheme.Content.background)
}

#Preview("Orientation Phase") {
    QAPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState(),
        phaseID: .orientation
    )
    .background(AssessmentTheme.Content.background)
}

//
//  QAPhaseView.swift
//  VoiceMiniCog
//
//  Reusable Q&A template for QDRS, PHQ-2, and Orientation.
//
//  Orientation: avatar asks the question aloud, patient answers verbally
//  to the avatar. Clinician taps a checkmark or X to score.
//  The patient's answer is handled entirely by the avatar (Tavus WebRTC).
//
//  QDRS/PHQ-2: avatar asks, clinician taps answer buttons.
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
    @State private var avatarDoneSpeaking = false

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

                if phaseID == .orientation {
                    // Orientation: listening indicator + clinician scoring
                    orientationScoringArea
                        .opacity(animateIn ? 1 : 0)
                } else {
                    // QDRS / PHQ-2: answer buttons
                    VStack(spacing: 8) {
                        ForEach(Array(currentAnswers.enumerated()), id: \.offset) { index, answer in
                            answerButton(text: answer, index: index)
                        }
                    }
                    .opacity(animateIn ? 1 : 0)
                }
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()

            // Orientation dots
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
            avatarSetContext("You are administering a clinical assessment. The current phase is \(phaseID.displayName). You speak ONLY the question text provided via echo commands. After speaking the question, wait silently for the patient to answer. Do NOT repeat the question, do NOT give hints, do NOT advance. Keep any responses very brief.")
            speakQuestion(currentVoicePrompt)
        }
        .onChange(of: currentIndex) { _, _ in
            animateIn = false
            avatarDoneSpeaking = false
            selectedAnswer = nil
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                animateIn = true
            }
            speakQuestion(currentVoicePrompt)
        }
    }

    // MARK: - Orientation Scoring Area

    @ViewBuilder
    private var orientationScoringArea: some View {
        if !avatarDoneSpeaking {
            // Avatar is speaking — show nothing
            EmptyView()
        } else {
            // Avatar finished speaking — show listening state + scoring buttons
            VStack(spacing: 16) {
                // Listening indicator
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundStyle(AssessmentTheme.Phase.welcome)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text("Patient is answering...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AssessmentTheme.Content.textSecondary)
                }

                // Clinician scoring: simple check/X buttons
                HStack(spacing: 20) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        scoreOrientation(correct: true)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                            Text("Correct")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: "#34C759"))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAnswer != nil)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        scoreOrientation(correct: false)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                            Text("Incorrect")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(hex: "#FF3B30"))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAnswer != nil)
                }
            }
        }
    }

    // MARK: - Score Orientation Answer

    private func scoreOrientation(correct: Bool) {
        selectedAnswer = correct ? 0 : 1
        if currentIndex < assessmentState.qmciState.orientationAnswers.count {
            assessmentState.qmciState.orientationAnswers[currentIndex] = correct
        }
        layoutManager.acknowledgeAnswer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if currentIndex < totalQuestions - 1 {
                currentIndex += 1
            } else {
                layoutManager.advanceToNextPhase()
            }
        }
    }

    // MARK: - Answer Button (QDRS / PHQ-2 only)

    private func answerButton(text: String, index: Int) -> some View {
        Button {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            selectedAnswer = index
            recordAnswer(index)
            layoutManager.acknowledgeAnswer()

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

    // MARK: - Speak Question

    /// Avatar speaks the question, then switches to listening.
    /// For orientation: also shows the scoring UI after speaking.
    private func speakQuestion(_ text: String) {
        avatarDoneSpeaking = false
        layoutManager.setAvatarSpeaking()
        avatarSpeak(text)
        let wordCount = text.split(separator: " ").count
        let speakDuration = max(2.0, Double(wordCount) * 0.08 + 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + speakDuration) {
            layoutManager.setAvatarListening()
            avatarDoneSpeaking = true
        }
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
            return []
        default:
            return []
        }
    }

    // MARK: - Record Answer (QDRS / PHQ-2 only)

    private func recordAnswer(_ index: Int) {
        switch phaseID {
        case .qdrs:
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

#Preview("Orientation Phase") {
    QAPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState(),
        phaseID: .orientation
    )
    .background(AssessmentTheme.Content.background)
}

//
//  QAPhaseView.swift
//  VoiceMiniCog
//
//  Reusable Q&A template for QDRS and Orientation.
//
//  Orientation: avatar asks each question, patient answers verbally,
//  auto-advances after patient response (via .patientDoneSpeaking).
//  No Correct/Incorrect buttons — fully hands-free.
//
//  QDRS: avatar asks, clinician taps answer buttons.
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
    @State private var contentVisible = false
    @State private var avatarDoneSpeaking = false
    @State private var waitingForPatientResponse = false
    @State private var orientationAutoAdvanceTask: Task<Void, Never>?

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
                    .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                    .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

                if phaseID == .orientation {
                    // Orientation: listening indicator (no buttons)
                    orientationListeningArea
                        .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                        .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
                } else {
                    // QDRS / PHQ-2: answer buttons
                    VStack(spacing: 8) {
                        ForEach(Array(currentAnswers.enumerated()), id: \.offset) { index, answer in
                            answerButton(text: answer, index: index)
                        }
                    }
                    .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                    .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
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
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetContext("You are administering a clinical assessment. The current phase is \(phaseID.displayName). You speak ONLY the question text provided via echo commands. Do NOT ask your own questions or advance the assessment. If the patient asks to skip or move on, gently redirect them to answer the current question.")
            speakQuestion(currentVoicePrompt)
        }
        .onChange(of: currentIndex) { _, _ in
            contentVisible = false
            avatarDoneSpeaking = false
            selectedAnswer = nil
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            speakQuestion(currentVoicePrompt)
        }
        .onReceive(NotificationCenter.default.publisher(for: .patientDoneSpeaking)) { _ in
            if phaseID == .orientation && waitingForPatientResponse {
                advanceOrientationQuestion()
            }
        }
    }

    // MARK: - Orientation Listening Area

    @ViewBuilder
    private var orientationListeningArea: some View {
        if avatarDoneSpeaking {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundStyle(AssessmentTheme.Phase.welcome)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text("Listening...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AssessmentTheme.Content.textSecondary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Answer Button (QDRS only)

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
        .buttonStyle(AssessmentPrimaryButtonStyle())
        .disabled(selectedAnswer != nil)
    }

    // MARK: - Speak Question + Avatar Sync

    private func speakQuestion(_ text: String) {
        avatarDoneSpeaking = false
        waitingForPatientResponse = false
        orientationAutoAdvanceTask?.cancel()
        layoutManager.setAvatarSpeaking()
        avatarSpeak(text)
        let wordCount = text.split(separator: " ").count
        let speakDuration = max(2.0, Double(wordCount) * 0.08 + 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + speakDuration) {
            layoutManager.setAvatarListening()
            avatarDoneSpeaking = true
            if phaseID == .orientation {
                waitForPatientResponse()
            }
        }
    }

    // MARK: - Wait for Patient Response (Orientation)

    private func waitForPatientResponse() {
        waitingForPatientResponse = true
        orientationAutoAdvanceTask?.cancel()
        orientationAutoAdvanceTask = Task { @MainActor in
            // Fallback: 15 seconds if patient doesn't respond
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            advanceOrientationQuestion()
        }
    }

    private func advanceOrientationQuestion() {
        guard waitingForPatientResponse else { return }
        waitingForPatientResponse = false
        orientationAutoAdvanceTask?.cancel()

        if currentIndex < assessmentState.qmciState.orientationAnswers.count {
            assessmentState.qmciState.orientationAnswers[currentIndex] = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if currentIndex < totalQuestions - 1 {
                currentIndex += 1
            } else {
                layoutManager.advanceToNextPhase()
            }
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
        case .qdrs:         return QDRS_QUESTIONS[safe: currentIndex]?.text ?? ""
        case .phq2:         return PHQ2_QUESTIONS[safe: currentIndex] ?? ""
        case .orientation:  return ORIENTATION_ITEMS[safe: currentIndex]?.question ?? ""
        default:            return ""
        }
    }

    private var currentVoicePrompt: String {
        switch phaseID {
        case .qdrs:         return QDRS_QUESTIONS[safe: currentIndex]?.voicePrompt ?? ""
        case .phq2:         return PHQ2_QUESTIONS[safe: currentIndex] ?? ""
        case .orientation:  return ORIENTATION_ITEMS[safe: currentIndex]?.voicePrompt ?? ""
        default:            return ""
        }
    }

    private var currentAnswers: [String] {
        switch phaseID {
        case .qdrs:         return ["No Change", "Sometimes", "Yes, Changed"]
        case .phq2:         return ["Not at all", "Several days", "More than half the days", "Nearly every day"]
        case .orientation:  return [] // Auto-advancing, no buttons
        default:            return []
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

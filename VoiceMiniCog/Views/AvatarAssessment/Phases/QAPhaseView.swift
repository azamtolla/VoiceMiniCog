//
//  QAPhaseView.swift
//  VoiceMiniCog
//
//  Reusable Q&A template for QDRS (10 questions), PHQ-2 (2 questions),
//  and Orientation (5 questions).
//
//  Orientation: avatar asks, patient speaks, transcript shown, auto-scored.
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

    // Orientation speech recognition
    @State private var speechService = SpeechService()
    @State private var orientationState: OrientationListeningState = .waiting
    @State private var scoredResult: Bool? = nil

    private enum OrientationListeningState {
        case waiting      // Avatar is speaking the question
        case listening    // Patient is responding
        case scored       // Answer auto-scored, showing result
    }

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

                // Orientation: show transcript + auto-score (no buttons)
                if phaseID == .orientation {
                    orientationResponseArea
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
            avatarSetContext("You are administering a clinical assessment. The current phase is \(phaseID.displayName). You speak ONLY the question text provided via echo commands. Do NOT ask your own questions or advance the assessment. If the patient asks to skip or move on, gently redirect them to answer the current question.")
            if phaseID == .orientation {
                speakThenListenOrientation(currentVoicePrompt)
            } else {
                speakThenListen(currentVoicePrompt)
            }
        }
        .onChange(of: currentIndex) { _, _ in
            animateIn = false
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                animateIn = true
            }
            if phaseID == .orientation {
                speakThenListenOrientation(currentVoicePrompt)
            } else {
                speakThenListen(currentVoicePrompt)
            }
        }
        .onDisappear {
            speechService.stopListening()
        }
    }

    // MARK: - Orientation Response Area

    @ViewBuilder
    private var orientationResponseArea: some View {
        VStack(spacing: 16) {
            if orientationState == .waiting {
                // Avatar is speaking — show nothing yet
                EmptyView()
            } else if orientationState == .listening {
                // Listening indicator + live transcript
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: "#34C759"))
                        .frame(width: 10, height: 10)
                        .opacity(speechService.isListening ? 1 : 0.3)
                    Text(speechService.transcript.isEmpty ? "Listening..." : speechService.transcript)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(speechService.transcript.isEmpty
                            ? AssessmentTheme.Content.textSecondary
                            : AssessmentTheme.Content.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(12)
            } else if orientationState == .scored {
                // Show patient response + correct/incorrect badge
                VStack(spacing: 10) {
                    // Patient's answer
                    Text("\"\(speechService.transcript)\"")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AssessmentTheme.Content.textPrimary)
                        .multilineTextAlignment(.center)
                        .italic()

                    // Score badge
                    HStack(spacing: 6) {
                        Image(systemName: scoredResult == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 18))
                        Text(scoredResult == true ? "Correct" : "Incorrect")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(scoredResult == true ? Color(hex: "#34C759") : Color(hex: "#FF3B30"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background((scoredResult == true ? Color(hex: "#34C759") : Color(hex: "#FF3B30")).opacity(0.08))
                .cornerRadius(12)
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

    // MARK: - Speak Then Listen (QDRS / PHQ-2)

    private func speakThenListen(_ text: String) {
        layoutManager.setAvatarSpeaking()
        avatarSpeak(text)
        let wordCount = text.split(separator: " ").count
        let speakDuration = max(2.0, Double(wordCount) * 0.08 + 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + speakDuration) {
            layoutManager.setAvatarListening()
        }
    }

    // MARK: - Speak Then Listen (Orientation — with speech recognition)

    private func speakThenListenOrientation(_ text: String) {
        orientationState = .waiting
        scoredResult = nil
        speechService.stopListening()
        speechService.transcript = ""

        layoutManager.setAvatarSpeaking()
        avatarSpeak(text)

        let wordCount = text.split(separator: " ").count
        let speakDuration = max(2.0, Double(wordCount) * 0.08 + 1.5)

        // After avatar finishes speaking → start listening
        DispatchQueue.main.asyncAfter(deadline: .now() + speakDuration) {
            layoutManager.setAvatarListening()
            orientationState = .listening
            startOrientationListening()
        }
    }

    private func startOrientationListening() {
        Task {
            if !speechService.isAuthorized {
                _ = await speechService.requestAuthorization()
            }
            try? await speechService.startListening()

            // Monitor transcript — when patient stops speaking (transcript stabilizes),
            // auto-score after a 2.5s pause
            monitorTranscript()
        }
    }

    private func monitorTranscript() {
        // Check every 0.5s if transcript has stabilized (patient stopped talking)
        var lastTranscript = ""
        var stableCount = 0

        func check() {
            guard orientationState == .listening else { return }

            if !speechService.transcript.isEmpty && speechService.transcript == lastTranscript {
                stableCount += 1
                if stableCount >= 5 { // 2.5s of stable transcript
                    scoreOrientationResponse()
                    return
                }
            } else {
                stableCount = 0
            }
            lastTranscript = speechService.transcript
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { check() }
    }

    private func scoreOrientationResponse() {
        guard orientationState == .listening else { return }

        speechService.stopListening()

        let item = ORIENTATION_ITEMS[currentIndex]
        let isCorrect = scoreOrientationAnswer(type: item.correctAnswerType, transcript: speechService.transcript)

        // Record the score
        if currentIndex < assessmentState.qmciState.orientationAnswers.count {
            assessmentState.qmciState.orientationAnswers[currentIndex] = isCorrect
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            scoredResult = isCorrect
            orientationState = .scored
        }
        layoutManager.acknowledgeAnswer()

        // Auto-advance after showing result
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
            return [] // Orientation uses speech recognition, not buttons
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

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var contentVisible = false
    /// True only after Tavus `replica.stopped_speaking` (or a generous fallback) for the current question.
    @State private var questionPlaybackFinished = false
    @State private var waitingForPatientResponse = false
    @State private var orientationAutoAdvanceTask: Task<Void, Never>?
    /// Bumped on each `speakQuestion` so late `avatarDoneSpeaking` events cannot unlock the wrong question.
    @State private var questionSpeechEpoch = 0
    /// Orientation: Tavus can emit `user.stopped_speaking` right after mic unmutes without a matching
    /// `user.started_speaking`, which was auto-advancing past questions (e.g. skipping "What month is this?").
    @State private var heardPatientSpeechDuringAnswerWait = false

    /// Voice mode ONLY (Task 6 blocker fix): in avatar mode the
    /// .patientStartedSpeaking/.patientDoneSpeaking signals come from Daily's
    /// SERVER-SIDE speech events; in voice mode nothing captures audio during
    /// an orientation answer window, so every question would fall through to
    /// the 10 s no-response timeout and score nil (10 of 100 Qmci points).
    /// This SpeechService runs a listening window for the duration of
    /// waitForPatientResponse() purely so its Task 4B bridge can post those
    /// notifications from on-device ASR activity.
    ///
    /// CLINICAL NOTE: orientation scores speech PRESENCE only (2 pts default
    /// on speech, nil on silence — clinician adjusts in the PCP report). The
    /// transcript is never scored, and this change adds no transcript scoring:
    /// the advance/scoring logic in advanceOrientationQuestion is untouched
    /// and identical for both modes.
    @StateObject private var voiceAnswerListener = SpeechService()
    @State private var didRequestSpeechAuth = false

    // MARK: Body

    var body: some View {
        Group {
            if phaseID == .orientation {
                orientationBody
            } else {
                qdrsStyleBody
            }
        }
        .onAppear {
            avatarInterrupt()
            // Scored subtest: disable speculative_inference + RAG via phase-type signal.
            avatarSetAssessmentPhaseType(.orientation)
            // Arm the autonomous-operation silence watchdog (90s re-prompt, 150s abandon).
            avatarBeginSilenceWatch()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            // Voice mode: speech-recognition permission is needed before the
            // first orientation answer window opens (same pattern as
            // WordRegistrationPhaseView's onAppear auth request).
            if phaseID == .orientation, GuideMode.current == .voice, !didRequestSpeechAuth {
                didRequestSpeechAuth = true
                Task { _ = await voiceAnswerListener.requestAuthorization() }
            }
            if phaseID == .orientation {
                avatarSetAssessmentContext(QMCIAvatarContext.orientation)
            } else {
                avatarSetAssessmentContext(
                    "You are a clinical neuropsychologist administering the \(phaseID.displayName) portion of a standardized cognitive assessment. Speak with a calm, measured, professional tone. You speak ONLY the question text provided via echo commands — do not ad-lib or rephrase. Do not provide hints, feedback, or encouragement. If the patient asks to skip or seems confused, say calmly: 'Please take your time and answer as best you can.'"
                )
            }
            speakQuestion(currentVoicePrompt)
        }
        .onChange(of: currentIndex) { _, _ in
            contentVisible = false
            questionPlaybackFinished = false
            selectedAnswer = nil
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            speakQuestion(currentVoicePrompt)
        }
        .onReceive(NotificationCenter.default.publisher(for: .patientStartedSpeaking)) { _ in
            if phaseID == .orientation, waitingForPatientResponse {
                heardPatientSpeechDuringAnswerWait = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .patientDoneSpeaking)) { _ in
            guard phaseID == .orientation, waitingForPatientResponse else { return }
            // Ignore orphan "stopped" without a "started" (noise / AGC right after replica stops).
            guard heardPatientSpeechDuringAnswerWait else { return }
            advanceOrientationQuestion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            finishQuestionSpeechIfNeeded(epoch: questionSpeechEpoch)
        }
        .onDisappear {
            // Voice-mode ASR window cleanup on mid-wait exit (End Session):
            // without this the audio-engine tap leaks past the phase. Inert
            // in avatar mode — the listener is never started there.
            if voiceAnswerListener.isListening {
                voiceAnswerListener.stopListening()
            }
        }
    }

    // MARK: - Orientation body (full redesign)

    /// Truly vertically centered: equal Spacer() above and below the
    /// entire question block (rules + text + step dots + waveform).
    /// No container card — the question floats on the canvas, framed
    /// only by two hairline rules. Book/card-game feel.
    @ViewBuilder
    private var orientationBody: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                orientationQuestionDisplay

                // Step indicators — 20pt below the bottom rule
                OrientationStepIndicators(
                    totalQuestions: totalQuestions,
                    currentIndex: currentIndex,
                    accent: layoutManager.accentColor
                )

                // Listening waveform
                OrientationListeningWaveform(
                    isActive: questionPlaybackFinished && waitingForPatientResponse,
                    color: layoutManager.accentColor
                )
                .frame(height: 24)
                .padding(.top, 4)
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()
        }
    }

    // MARK: - Orientation question display (no fill, two hairline rules)

    /// Question text floating on the canvas, framed above and below by a
    /// single 1pt rule. No background color, no card, no shadow. Fades in
    /// on appear: opacity 0→1, offset y 12→0, easeOut 0.4s.
    @ViewBuilder
    private var orientationQuestionDisplay: some View {
        VStack(spacing: 24) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 40)

            Text(currentQuestionText)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)
                .animation(
                    reduceMotion ? .none : .easeOut(duration: 0.4),
                    value: contentVisible
                )

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - QDRS / PHQ-2 body (legacy layout, untouched)

    @ViewBuilder
    private var qdrsStyleBody: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("Question \(currentIndex + 1) of \(totalQuestions)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(layoutManager.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(layoutManager.accentColor.opacity(0.12)))
                    .overlay(Capsule().stroke(layoutManager.accentColor.opacity(0.22), lineWidth: 1))
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 10)
                    .motionSafe(AssessmentTheme.Motion.phaseEnter, value: contentVisible)

                questionCard
                    .motionSafe(AssessmentTheme.Motion.phaseEnter, value: contentVisible)

                VStack(spacing: 8) {
                    ForEach(Array(currentAnswers.enumerated()), id: \.offset) { index, answer in
                        answerButton(text: answer, index: index)
                    }
                }
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()
        }
    }

    // MARK: - Question Card (regularMaterial + staggered line reveal)

    /// Splits the question on whitespace into chunks and reveals each with
    /// a short stagger (0.04s per chunk) — same pattern Apple uses for
    /// onboarding text. Falls back to a single-shot fade under reduce-motion.
    @ViewBuilder
    private var questionCard: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let splitLines = currentQuestionText.split(separator: "\n").map { String($0) }
        let lines: [String] = splitLines.isEmpty ? [currentQuestionText] : splitLines

        VStack(alignment: .center, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AssessmentTheme.Content.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 8)
                    .motionSafe(
                        AssessmentTheme.Motion.phaseEnter.delay(Double(i) * 0.04),
                        value: contentVisible
                    )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .assessmentGlass(in: shape, tint: layoutManager.accentColor, prominence: .regular)
        .overlay(shape.stroke(layoutManager.accentColor.opacity(0.12), lineWidth: 1))
        .assessmentShadow(AssessmentTheme.Depth.cardResting)
    }

    // Orientation listening area replaced by OrientationListeningWaveform
    // (see bottom of file).

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
        questionSpeechEpoch += 1
        let epoch = questionSpeechEpoch
        questionPlaybackFinished = false
        waitingForPatientResponse = false
        orientationAutoAdvanceTask?.cancel()
        layoutManager.setAvatarSpeaking()
        avatarSpeak(text)

        // Fallback if the Tavus bridge never posts `avatarDoneSpeaking`
        let wordCount = text.split(separator: " ").count
        let fallbackSeconds = max(14.0, Double(wordCount) * 0.38 + 6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackSeconds) {
            finishQuestionSpeechIfNeeded(epoch: epoch)
        }
    }

    /// Unlocks listening / orientation wait only after the replica finishes this question’s echo.
    private func finishQuestionSpeechIfNeeded(epoch: Int) {
        guard epoch == questionSpeechEpoch else { return }
        guard !questionPlaybackFinished else { return }
        questionPlaybackFinished = true
        layoutManager.setAvatarListening()
        if phaseID == .orientation {
            waitForPatientResponse()
        }
    }

    // MARK: - Wait for Patient Response (Orientation)

    private func waitForPatientResponse() {
        // DailyCallManager.handleReplicaStoppedSpeaking is the single source of
        // truth for unmuting after the avatar finishes a prompt; its watchdog
        // also unmutes if Tavus drops the stopped_speaking event. No explicit
        // unmute needed here.
        waitingForPatientResponse = true
        heardPatientSpeechDuringAnswerWait = false
        orientationAutoAdvanceTask?.cancel()

        // Task 6 blocker fix — voice mode only: open an on-device ASR window
        // so SpeechService's bridge can post .patientStartedSpeaking /
        // .patientDoneSpeaking (in avatar mode Daily's server-side events own
        // those posts; the bridge is mode-gated internally so nothing can
        // double-fire). The window detects speech PRESENCE only; no
        // transcript is scored (see voiceAnswerListener doc comment).
        if GuideMode.current == .voice {
            if SpeechService.fixturesEnabled {
                // Simulator has no microphone — inject a fixture so the
                // presence bridge is exercisable end-to-end in smoke tests.
                voiceAnswerListener.fixtureTranscript = "It is two thousand twenty six"
            }
            Task { @MainActor in
                do {
                    try await voiceAnswerListener.startListening()
                } catch {
                    // Presence signal unavailable — the 10 s timeout below
                    // still runs and scores nil (clinician review), exactly
                    // the pre-existing no-speech-detected behavior.
                    print("[QAPhaseView] Voice-mode ASR window failed to start: \(error.localizedDescription)")
                }
            }
        }

        orientationAutoAdvanceTask = Task { @MainActor in
            // QMCI protocol: max 10 seconds per orientation answer
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            // Timeout path: patient was silent — do NOT default to full credit.
            advanceOrientationQuestion(patientResponded: false)
        }
    }

    private func advanceOrientationQuestion(patientResponded: Bool = true) {
        guard waitingForPatientResponse else { return }
        waitingForPatientResponse = false
        orientationAutoAdvanceTask?.cancel()

        // Close the voice-mode ASR window with the answer wait. Any
        // .patientDoneSpeaking this stop emits is dropped by the
        // waitingForPatientResponse guard above (already false). Inert in
        // avatar mode — the listener is never started there.
        if voiceAnswerListener.isListening {
            voiceAnswerListener.stopListening()
        }

        // Avatar cannot judge correctness. If the patient spoke, default to full
        // credit (2 pts) and let the clinician adjust in the PCP report. If the
        // patient was silent (timeout), leave the score nil so the clinician is
        // forced to review — a silent answer should never silently earn 2 pts.
        if currentIndex < assessmentState.qmciState.orientationScores.count {
            assessmentState.qmciState.orientationScores[currentIndex] = patientResponded ? 2 : nil
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

    /// No longer used — bottom-left dots replaced by OrientationStepIndicators
    /// rendered directly beneath the question card. Retained as a computed
    /// helper so orientationDotColor(at:) can still feed any clinician-facing
    /// display that might want per-question score colors in the future.
    private var orientationFooter: some View { EmptyView() }

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
        guard index < assessmentState.qmciState.orientationScores.count else {
            return Color.gray.opacity(0.2)
        }
        guard let score = assessmentState.qmciState.orientationScores[safe: index] ?? nil else {
            return Color.gray.opacity(0.2)
        }
        switch score {
        case 2:  return Color(hex: "#34C759")   // full credit — green
        case 1:  return Color(hex: "#FF9500")   // partial credit — orange
        default: return Color(hex: "#FF3B30")   // no credit — red
        }
    }
}

// MARK: - OrientationStepIndicators

/// Five centered step dots under the Orientation question card.
///   • Completed: 12pt filled accent circle with tiny checkmark
///   • Current:   14pt accent circle with an outer pulsing ring (beacon)
///   • Upcoming:  10pt light gray circle
/// All state transitions spring(.4, .7); reduce-motion degrades cleanly.
private struct OrientationStepIndicators: View {
    let totalQuestions: Int
    let currentIndex: Int
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<totalQuestions, id: \.self) { i in
                dot(for: i)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7),
            value: currentIndex
        )
    }

    @ViewBuilder
    private func dot(for i: Int) -> some View {
        // Sized to match the Word Registration bubbles (52pt diameter)
        // so the progress language is consistent across the assessment.
        let diam: CGFloat = 52
        if i < currentIndex {
            // Completed — 40% accent fill + 1.5pt stroke + white checkmark.
            ZStack {
                Circle().fill(accent.opacity(0.40)).frame(width: diam, height: diam)
                Circle().strokeBorder(accent, lineWidth: 1.5).frame(width: diam, height: diam)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        } else if i == currentIndex {
            // Current — subtle 12% tint + pulsing beacon ring.
            ZStack {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4    // 0...1
                        let scale = 1.0 + 0.22 * phase                                  // 1.0 → 1.22
                        let alpha = 1.0 - phase                                         // 1.0 → 0
                        Circle()
                            .strokeBorder(accent.opacity(alpha), lineWidth: 2)
                            .frame(width: diam, height: diam)
                            .scaleEffect(scale)
                    }
                }
                Circle().fill(accent.opacity(0.18)).frame(width: diam, height: diam)
                Circle().strokeBorder(accent, lineWidth: 1.5).frame(width: diam, height: diam)
            }
            .frame(width: diam * 1.3, height: diam * 1.3)  // room for the pulse
        } else {
            // Upcoming — 12% accent fill + 1.5pt accent stroke, same
            // empty-bubble look as Word Registration.
            ZStack {
                Circle().fill(accent.opacity(0.12)).frame(width: diam, height: diam)
                Circle().strokeBorder(accent, lineWidth: 1.5).frame(width: diam, height: diam)
            }
        }
    }
}

// MARK: - OrientationListeningWaveform

/// Three small bars in the phase accent color with staggered vertical
/// amplitude. Fades in when `isActive` becomes true, fades out when false.
/// Reduce-motion renders static bars.
private struct OrientationListeningWaveform: View {
    let isActive: Bool
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: 4, height: CGFloat(10 + i * 6))
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            let phaseShift = Double(i) * 0.4
                            let amp = (sin(t * 3.5 - phaseShift) + 1) / 2    // 0...1
                            Capsule()
                                .fill(color)
                                .frame(width: 4, height: CGFloat(8 + amp * 18))
                        }
                    }
                }
            }
        }
        .opacity(isActive ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .accessibilityLabel("Listening")
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

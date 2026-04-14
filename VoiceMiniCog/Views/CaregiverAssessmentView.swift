//
//  CaregiverAssessmentView.swift
//  VoiceMiniCog
//
//  Dedicated caregiver/informant QDRS questionnaire with three states:
//  .welcome → .questions(0...9) → .complete
//
//  Shares only the avatar video component (right panel) with the cognitive
//  assessment. Left panel is a clean, simple questionnaire — no cognitive
//  subtest UI, no progress bar, no word chips, no timers.
//
//  **TavusCVIView instance note:** This view creates its OWN TavusCVIView
//  (line ~334) connected to the same conversation URL. This is intentional:
//  the caregiver flow runs on a separate screen from AvatarAssessmentCanvas,
//  so there is no shared WKWebView lifecycle to worry about. However, both
//  views must NOT be in the SwiftUI hierarchy simultaneously — the parent
//  (ContentView) is responsible for ensuring only one screen that embeds
//  TavusCVIView is mounted at a time. AvatarAssessmentCanvas enforces this
//  via its `warmTavusWebViewOnHome` flag (set to false while caregiver is
//  active) which prevents it from passing the Daily URL into AvatarZoneView.
//

import SwiftUI

// MARK: - Caregiver Flow State

private enum CaregiverFlowState: Equatable {
    case welcome
    case questions(index: Int)
    case complete
}

// MARK: - CaregiverAssessmentView

struct CaregiverAssessmentView: View {

    @Bindable var assessmentState: AssessmentState
    var tavusService: TavusService
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var flowState: CaregiverFlowState = .welcome
    @State private var selectedAnswer: QDRSAnswer? = nil
    @State private var animateContent = false
    @State private var isPressed: [QDRSAnswer: Bool] = [:]
    @State private var answerTransitionWork: DispatchWorkItem?
    @State private var speakNextQuestionWork: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let questions = QDRS_QUESTIONS
    private let avatarWidthRatio: CGFloat = 0.50

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth = geo.size.width * avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // Background gradient (light left → dark right)
                LinearGradient(
                    stops: [
                        .init(color: AssessmentTheme.Content.background, location: 0.0),
                        .init(color: AssessmentTheme.Content.background, location: 1.0 - avatarWidthRatio),
                        .init(color: AssessmentTheme.Avatar.gradientEdge, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    // MARK: Left Panel
                    leftPanel
                        .frame(width: contentWidth)

                    // MARK: Right Panel — Avatar (audio-only, no camera feed)
                    avatarPanel(width: avatarWidth, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onDisappear {
            answerTransitionWork?.cancel()
            answerTransitionWork = nil
            speakNextQuestionWork?.cancel()
            speakNextQuestionWork = nil
        }
    }

    // MARK: - Left Panel Router

    @ViewBuilder
    private var leftPanel: some View {
        switch flowState {
        case .welcome:
            welcomePanel
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .questions(let index):
            questionPanel(index: index)
                .id(index)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .complete:
            completionPanel
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity
                ))
        }
    }

    // MARK: - Welcome Panel

    private var welcomePanel: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo / icon
            MCIconCircle(
                icon: "person.2.fill",
                color: AssessmentTheme.Phase.qdrs,
                size: 80
            )
            .padding(.bottom, 20)

            Text("Family Member &\nCaregiver Questionnaire")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text("This brief questionnaire asks about changes you may\nhave noticed in your family member or patient's everyday\nmemory and activities.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            // Duration + guidance
            HStack(spacing: 16) {
                Label("10 questions", systemImage: "list.bullet")
                Label("About 3–5 minutes", systemImage: "clock")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(AssessmentTheme.Content.textSecondary)
            .padding(.bottom, 8)

            Text("There are no right or wrong answers.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AssessmentTheme.Phase.qdrs)
                .padding(.bottom, 32)

            // Begin button
            MCPrimaryButton("Begin Questionnaire", icon: "play.fill", color: AssessmentTheme.Phase.qdrs) {
                avatarInterrupt()
                withAnimation(.easeInOut(duration: 0.35)) {
                    flowState = .questions(index: 0)
                }
                // Avatar speaks the first question
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    avatarSpeak(questions[0].voicePrompt)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Cancel
            Button { onCancel() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 15))
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(MCDesign.Colors.textTertiary)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
        .onAppear {
            avatarSpeak("Thank you for being here today. I have ten brief questions about any changes you may have noticed in the patient's everyday memory and activities. There are no right or wrong answers. Tap Begin when you're ready.")
        }
    }

    // MARK: - Question Panel

    private func questionPanel(index: Int) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            // Question counter
            Text("Question \(index + 1) of \(questions.count)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .padding(.bottom, 8)

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<questions.count, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i, current: index))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
            }
            .padding(.bottom, 24)

            Spacer()

            // Question text — vertically centered
            Text(questions[index].text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            // Answer buttons
            VStack(spacing: 14) {
                ForEach(QDRSAnswer.allCases, id: \.self) { answer in
                    answerButton(answer, questionIndex: index)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Cancel
            Button { onCancel() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 15))
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(MCDesign.Colors.textTertiary)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Answer Button

    private func answerButton(_ answer: QDRSAnswer, questionIndex: Int) -> some View {
        let pressed = isPressed[answer] ?? false
        let selected = selectedAnswer == answer

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectAnswer(answer, questionIndex: questionIndex)
        } label: {
            Text(answer.displayLabel)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(selected ? .white : AssessmentTheme.Content.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(selected ? AssessmentTheme.Phase.qdrs : AssessmentTheme.Content.surface)
                .cornerRadius(MCDesign.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                        .stroke(
                            selected ? AssessmentTheme.Phase.qdrs : Color.gray.opacity(0.2),
                            lineWidth: 1.5
                        )
                )
                .mcShadow(pressed ? MCDesign.Shadow.pressed : MCDesign.Shadow.card)
                .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(selectedAnswer != nil)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) { isPressed[answer] = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) { isPressed[answer] = false } }
        )
    }

    // MARK: - Completion Panel

    private var completionPanel: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AssessmentTheme.Phase.results.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AssessmentTheme.Phase.results)
            }

            Text("Thank You")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)

            Text("Your responses have been recorded.\nThe clinician will review your answers.")
                .font(.system(size: 17))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            MCPrimaryButton("Done", icon: "checkmark", color: AssessmentTheme.Phase.results) {
                avatarInterrupt()
                onComplete()
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)
        }
        .onAppear {
            avatarSpeak("Thank you for answering those questions. That information is very helpful. The clinician will review your responses.")
        }
    }

    // MARK: - Avatar Panel

    private func avatarPanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Dark gradient background
            RadialGradient(
                colors: [AssessmentTheme.Avatar.gradientCenter, AssessmentTheme.Avatar.gradientEdge],
                center: .center,
                startRadius: 0,
                endRadius: max(width, height) * 0.7
            )

            // Avatar video or loading state
            if let url = tavusService.activeConversation?.conversation_url {
                TavusCVIView(conversationURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(16)
            } else if tavusService.isCreatingConversation {
                // Loading state — subtle pulsing placeholder
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Connecting avatar...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if let error = tavusService.lastError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Logic

    private func selectAnswer(_ answer: QDRSAnswer, questionIndex: Int) {
        // Cancel any in-flight transition from a previous rapid tap
        answerTransitionWork?.cancel()
        speakNextQuestionWork?.cancel()

        selectedAnswer = answer
        assessmentState.qdrsState.answers[questionIndex] = answer

        let transitionWork = DispatchWorkItem { [self] in
            // Guard: if the work item was cancelled (e.g. view disappeared), bail out
            guard answerTransitionWork?.isCancelled == false else { return }

            if questionIndex < questions.count - 1 {
                let nextIndex = questionIndex + 1
                // Reset answer + pressed state synchronously before the transition animation
                selectedAnswer = nil
                isPressed = [:]
                withAnimation(.easeInOut(duration: 0.3)) {
                    flowState = .questions(index: nextIndex)
                }
                assessmentState.qdrsState.currentIndex = nextIndex
                // Avatar speaks next question in sync with left panel transition
                let speakWork = DispatchWorkItem {
                    guard speakNextQuestionWork?.isCancelled == false else { return }
                    avatarSpeak(questions[nextIndex].voicePrompt)
                }
                speakNextQuestionWork = speakWork
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: speakWork)
            } else {
                assessmentState.qdrsState.isComplete = true
                // Reset answer + pressed state synchronously before the transition animation
                selectedAnswer = nil
                isPressed = [:]
                withAnimation(.easeInOut(duration: 0.3)) {
                    flowState = .complete
                }
            }
        }
        answerTransitionWork = transitionWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: transitionWork)
    }

    private func dotColor(for index: Int, current: Int) -> Color {
        if index < current {
            return AssessmentTheme.Phase.qdrs
        } else if index == current {
            return AssessmentTheme.Phase.qdrs.opacity(0.5)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

#Preview {
    CaregiverAssessmentView(
        assessmentState: AssessmentState(),
        tavusService: TavusService.shared,
        onComplete: {},
        onCancel: {}
    )
}

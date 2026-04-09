//
//  CaregiverAssessmentView.swift
//  VoiceMiniCog
//
//  Dedicated caregiver/informant QDRS questionnaire.
//  Completely separate from AvatarAssessmentCanvas — shares only the
//  avatar video component (right panel). Left panel shows a clean,
//  simple questionnaire: "Question X of 10", full question text, and
//  three large answer buttons. No cognitive subtest UI, no progress
//  bar, no word chips, no timers.
//

import SwiftUI

struct CaregiverAssessmentView: View {

    @Bindable var assessmentState: AssessmentState
    var tavusService: TavusService
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var currentIndex = 0
    @State private var selectedAnswer: QDRSAnswer? = nil
    @State private var animateQuestion = false
    @State private var showCompletion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let questions = QDRS_QUESTIONS
    private let avatarWidthRatio: CGFloat = 0.45

    var body: some View {
        GeometryReader { geo in
            let avatarWidth = geo.size.width * avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // Background gradient (light left → dark right)
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                        .init(color: Color(hex: "#F8F9FA"), location: 1.0 - avatarWidthRatio),
                        .init(color: Color(hex: "#111111"), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    // MARK: Left — Question Panel
                    if showCompletion {
                        completionPanel
                            .frame(width: contentWidth)
                    } else {
                        questionPanel
                            .frame(width: contentWidth)
                    }

                    // MARK: Right — Avatar Zone
                    AvatarZoneView(
                        layoutManager: AvatarLayoutManager(),
                        conversationURL: tavusService.activeConversation?.conversation_url,
                        isConnecting: tavusService.isCreatingConversation,
                        errorMessage: tavusService.lastError,
                        width: avatarWidth,
                        height: geo.size.height
                    )
                    .frame(width: avatarWidth, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    // MARK: - Question Panel

    private var questionPanel: some View {
        VStack(spacing: 0) {
            // Top padding for safe area
            Spacer().frame(height: 60)

            // Question counter
            Text("Question \(currentIndex + 1) of \(questions.count)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .padding(.bottom, 8)

            // Simple progress dots
            HStack(spacing: 6) {
                ForEach(0..<questions.count, id: \.self) { i in
                    Circle()
                        .fill(i < currentIndex ? AssessmentTheme.Phase.qdrs :
                              i == currentIndex ? AssessmentTheme.Phase.qdrs.opacity(0.5) :
                              Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 32)

            Spacer()

            // Question text
            Text(questions[currentIndex].text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .opacity(animateQuestion ? 1 : 0)
                .offset(y: animateQuestion ? 0 : 12)

            Spacer().frame(height: 40)

            // Answer buttons
            VStack(spacing: 14) {
                ForEach(QDRSAnswer.allCases, id: \.self) { answer in
                    answerButton(answer)
                }
            }
            .padding(.horizontal, 32)
            .opacity(animateQuestion ? 1 : 0)

            Spacer()

            // Cancel button
            Button {
                onCancel()
            } label: {
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
            animateIn()
            // Avatar speaks the first QDRS question when the panel appears
            avatarSpeak(questions[currentIndex].voicePrompt)
        }
    }

    // MARK: - Answer Button

    private func answerButton(_ answer: QDRSAnswer) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectAnswer(answer)
        } label: {
            Text(answer.displayLabel)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(selectedAnswer == answer ? .white : AssessmentTheme.Content.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    selectedAnswer == answer
                        ? AssessmentTheme.Phase.qdrs
                        : AssessmentTheme.Content.surface
                )
                .cornerRadius(MCDesign.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                        .stroke(
                            selectedAnswer == answer
                                ? AssessmentTheme.Phase.qdrs
                                : Color.gray.opacity(0.2),
                            lineWidth: 1.5
                        )
                )
                .mcShadow(MCDesign.Shadow.card)
        }
        .buttonStyle(.plain)
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

            Text("Questionnaire Complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)

            Text("Thank you for completing the\ncaregiver questionnaire.")
                .font(.system(size: 17))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            MCPrimaryButton("Return Home", icon: "house.fill", color: AssessmentTheme.Phase.results) {
                onComplete()
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 24)
        }
    }

    // MARK: - Logic

    private func selectAnswer(_ answer: QDRSAnswer) {
        selectedAnswer = answer
        assessmentState.qdrsState.answers[currentIndex] = answer

        // Brief delay then advance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if currentIndex < questions.count - 1 {
                animateQuestion = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    currentIndex += 1
                    assessmentState.qdrsState.currentIndex = currentIndex
                    selectedAnswer = nil
                    animateIn()
                    // Avatar speaks the next question in sync with left panel
                    avatarSpeak(questions[currentIndex].voicePrompt)
                }
            } else {
                // Done — mark QDRS complete
                assessmentState.qdrsState.isComplete = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    showCompletion = true
                }
            }
        }
    }

    private func animateIn() {
        if reduceMotion {
            animateQuestion = true
        } else {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                animateQuestion = true
            }
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

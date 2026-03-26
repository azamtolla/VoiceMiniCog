//
//  QDRSView.swift
//  VoiceMiniCog
//
//  QDRS: intro → 10 questions → summary. Redesigned for 65+ patients.
//  60pt touch targets, 20pt+ text, one question per screen.
//

import SwiftUI

struct QDRSView: View {
    @Bindable var qdrsState: QDRSState
    let onComplete: () -> Void
    let onDecline: () -> Void

    @State private var screen: QDRSScreen = .intro
    @State private var selectedAnswer: QDRSAnswer?

    enum QDRSScreen { case intro, questions, summary }

    var body: some View {
        VStack(spacing: 0) {
            if screen == .questions { questionsHeader }

            switch screen {
            case .intro: introScreen
            case .questions: questionScreen
            case .summary: summaryScreen
            }
        }
        .background(MCDesign.Colors.background)
        .animation(MCDesign.Anim.standard, value: screen)
        .animation(MCDesign.Anim.standard, value: qdrsState.currentIndex)
    }

    // MARK: - Intro

    private var introScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MCDesign.Spacing.lg) {
                MCIconCircle(
                    icon: "list.clipboard.fill",
                    color: MCDesign.Colors.qdrsAccent,
                    size: MCDesign.Sizing.iconXL
                )

                Text("Quick Memory Questionnaire")
                    .font(MCDesign.Fonts.screenTitle)
                    .foregroundColor(MCDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("10 short questions about everyday memory and thinking.\nThere are no right or wrong answers.")
                    .font(MCDesign.Fonts.body)
                    .foregroundColor(MCDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MCDesign.Spacing.xl)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                    Text("About 2-3 minutes")
                        .font(MCDesign.Fonts.caption)
                }
                .foregroundColor(MCDesign.Colors.textTertiary)
            }

            Spacer()

            VStack(spacing: MCDesign.Spacing.md) {
                MCPrimaryButton("Begin Questions", icon: "arrow.right",
                                color: MCDesign.Colors.qdrsAccent) {
                    withAnimation { screen = .questions }
                }

                MCSecondaryButton("Skip", icon: "chevron.right") {
                    qdrsState.declined = true
                    onDecline()
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .padding(.bottom, MCDesign.Spacing.xxl)
        }
    }

    // MARK: - Questions Header

    private var questionsHeader: some View {
        VStack(spacing: MCDesign.Spacing.sm) {
            HStack {
                Text("Question \(qdrsState.currentIndex + 1) of \(QDRS_QUESTIONS.count)")
                    .font(MCDesign.Fonts.caption)
                    .foregroundColor(MCDesign.Colors.textSecondary)

                Spacer()

                if let q = qdrsState.currentQuestion {
                    Text(q.domain)
                        .font(MCDesign.Fonts.smallCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(MCDesign.Colors.qdrsAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(MCDesign.Colors.qdrsAccent.opacity(0.1))
                        .cornerRadius(MCDesign.Radius.small)
                }
            }

            MCProgressBar(
                progress: qdrsState.progress,
                color: MCDesign.Colors.qdrsAccent
            )
        }
        .padding(.horizontal, MCDesign.Spacing.lg)
        .padding(.vertical, MCDesign.Spacing.md)
        .background(MCDesign.Colors.surface)
        .mcShadow(MCDesign.Shadow.header)
    }

    // MARK: - Question Screen

    private var questionScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            if let question = qdrsState.currentQuestion {
                VStack(spacing: MCDesign.Spacing.xl) {
                    // Domain icon
                    MCIconCircle(
                        icon: domainIcon(question.domain),
                        color: MCDesign.Colors.qdrsAccent,
                        size: MCDesign.Sizing.iconMedium
                    )

                    // Question text — large and clear
                    Text(question.text)
                        .font(MCDesign.Fonts.sectionTitle)
                        .foregroundColor(MCDesign.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MCDesign.Spacing.lg)

                    // Answer buttons — 60pt each
                    VStack(spacing: MCDesign.Spacing.md) {
                        answerButton(answer: .normal)
                        answerButton(answer: .sometimes)
                        answerButton(answer: .changed)
                    }
                    .padding(.horizontal, MCDesign.Spacing.lg)
                }
            }

            Spacer()

            // Navigation
            HStack(spacing: MCDesign.Spacing.md) {
                MCSecondaryButton("Back", icon: "chevron.left",
                                  width: 120) {
                    withAnimation(MCDesign.Anim.standard) {
                        qdrsState.goBack()
                        selectedAnswer = qdrsState.answers[qdrsState.currentIndex]
                    }
                }
                .disabled(qdrsState.currentIndex == 0)
                .opacity(qdrsState.currentIndex == 0 ? 0.35 : 1)

                Spacer()

                MCPrimaryButton(
                    qdrsState.currentIndex == QDRS_QUESTIONS.count - 1 ? "Finish" : "Next",
                    icon: "arrow.right",
                    color: selectedAnswer == nil ? MCDesign.Colors.border : MCDesign.Colors.primary700
                ) {
                    commitSelectedAnswer()
                }
                .disabled(selectedAnswer == nil)
                .frame(width: 160)
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .padding(.bottom, MCDesign.Spacing.lg)
        }
        .onAppear { selectedAnswer = qdrsState.answers[qdrsState.currentIndex] }
        .onChange(of: qdrsState.currentIndex) { _, _ in
            selectedAnswer = qdrsState.answers[qdrsState.currentIndex]
        }
        .onChange(of: qdrsState.isComplete) { _, complete in
            if complete { withAnimation { screen = .summary } }
        }
    }

    // MARK: - Answer Button (60pt height)

    private func answerButton(answer: QDRSAnswer) -> some View {
        let isSelected = selectedAnswer == answer

        return Button(action: {
            withAnimation(MCDesign.Anim.quick) {
                selectedAnswer = answer
            }
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }) {
            HStack(spacing: MCDesign.Spacing.md) {
                // Color indicator circle
                ZStack {
                    Circle()
                        .fill(answer.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: answerIcon(answer))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(answer.color)
                }

                Text(answer.displayLabel)
                    .font(MCDesign.Fonts.bodySemibold)
                    .foregroundColor(MCDesign.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(answer.color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(height: MCDesign.Sizing.primaryButtonHeight) // 60pt
            .background(isSelected ? answer.color.opacity(0.06) : MCDesign.Colors.surface)
            .cornerRadius(MCDesign.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                    .stroke(isSelected ? answer.color : MCDesign.Colors.border,
                            lineWidth: isSelected ? 2 : 1)
            )
            .mcShadow(MCDesign.Shadow.card)
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryScreen: some View {
        ScrollView {
            VStack(spacing: MCDesign.Spacing.lg) {
                Spacer().frame(height: MCDesign.Spacing.md)

                Text("QDRS Summary")
                    .font(MCDesign.Fonts.screenTitle)
                    .foregroundColor(MCDesign.Colors.textPrimary)

                // Score
                MCCard {
                    VStack(spacing: MCDesign.Spacing.md) {
                        Text(String(format: "%.1f", qdrsState.totalScore))
                            .font(MCDesign.Fonts.scoreDisplay)
                            .foregroundColor(qdrsState.riskColor)

                        Text("out of 10")
                            .font(MCDesign.Fonts.caption)
                            .foregroundColor(MCDesign.Colors.textTertiary)

                        Text(qdrsState.riskLabel)
                            .font(MCDesign.Fonts.bodySemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, MCDesign.Spacing.lg)
                            .padding(.vertical, MCDesign.Spacing.sm)
                            .background(qdrsState.riskColor)
                            .cornerRadius(MCDesign.Radius.small)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Flagged domains
                if !qdrsState.flaggedDomains.isEmpty {
                    MCCard(title: "Flagged Domains", icon: "exclamationmark.triangle.fill",
                           accentColor: MCDesign.Colors.warning) {
                        FlowLayout(spacing: 8) {
                            ForEach(qdrsState.flaggedDomains, id: \.self) { domain in
                                Text(domain)
                                    .font(MCDesign.Fonts.smallCaption)
                                    .fontWeight(.medium)
                                    .foregroundColor(MCDesign.Colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(MCDesign.Colors.warning.opacity(0.1))
                                    .cornerRadius(MCDesign.Radius.small)
                            }
                        }
                    }
                }

                // Note
                HStack(spacing: MCDesign.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(MCDesign.Colors.primary500)
                    Text("This is patient-reported. The cognitive assessment comes next.")
                        .font(MCDesign.Fonts.smallCaption)
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }
                .padding(MCDesign.Spacing.md)
                .background(MCDesign.Colors.primary50)
                .cornerRadius(MCDesign.Radius.medium)

                // Actions
                VStack(spacing: MCDesign.Spacing.md) {
                    MCPrimaryButton("Continue", icon: "arrow.right") {
                        onComplete()
                    }

                    MCSecondaryButton("Edit Answers") {
                        qdrsState.reset()
                        withAnimation { screen = .questions }
                    }
                }

                Spacer().frame(height: MCDesign.Spacing.xl)
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
        }
    }

    // MARK: - Helpers

    private func commitSelectedAnswer() {
        guard let selectedAnswer else { return }
        withAnimation(MCDesign.Anim.standard) {
            qdrsState.answer(selectedAnswer)
        }
    }

    private func domainIcon(_ domain: String) -> String {
        switch domain {
        case "Memory": return "brain"
        case "Orientation": return "location.fill"
        case "Judgment": return "scale.3d"
        case "Community": return "cart.fill"
        case "Home Activities": return "house.fill"
        case "Personal Care": return "figure.stand"
        case "Behavior": return "face.smiling"
        case "Language": return "text.bubble.fill"
        case "Interest": return "heart.fill"
        case "Repetition": return "arrow.2.squarepath"
        default: return "questionmark.circle"
        }
    }

    private func answerIcon(_ answer: QDRSAnswer) -> String {
        switch answer {
        case .normal: return "checkmark"
        case .sometimes: return "minus"
        case .changed: return "exclamationmark"
        }
    }
}

#Preview {
    QDRSView(qdrsState: QDRSState(), onComplete: {}, onDecline: {})
}

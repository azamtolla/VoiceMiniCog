//
//  PHQ2View.swift
//  VoiceMiniCog
//
//  PHQ-2 depression gate — 2 questions, 4 options each.
//  Positive ≥ 3 triggers PHQ-9 recommendation.
//

import SwiftUI

struct PHQ2View: View {
    @Binding var phq2State: PHQ2State
    let onComplete: () -> Void

    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack {
                Text("Depression Screen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textSecondary)
                Spacer()
                Text("Question \(currentIndex + 1) of 2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MCDesign.Colors.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.white)

            Spacer()

            VStack(spacing: 28) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "#7C3AED").opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "#7C3AED"))
                }

                // Question
                Text(PHQ2_QUESTIONS[currentIndex])
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Answer buttons
                VStack(spacing: 10) {
                    ForEach(PHQ2Answer.allCases, id: \.rawValue) { answer in
                        Button(action: {
                            selectAnswer(answer)
                        }) {
                            HStack(spacing: 14) {
                                Text("\(answer.rawValue)")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorForScore(answer.rawValue))
                                    .frame(width: 28)

                                Text(answer.displayLabel)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(MCDesign.Colors.textPrimary)

                                Spacer()

                                if phq2State.answers[currentIndex] == answer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(colorForScore(answer.rawValue))
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 60)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        phq2State.answers[currentIndex] == answer
                                            ? colorForScore(answer.rawValue)
                                            : MCDesign.Colors.border,
                                        lineWidth: phq2State.answers[currentIndex] == answer ? 2 : 1
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Nav
            HStack(spacing: 12) {
                if currentIndex > 0 {
                    Button(action: { currentIndex -= 1 }) {
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MCDesign.Colors.textSecondary)
                            .frame(width: 96, height: 52)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(MCDesign.Colors.border, lineWidth: 1)
                            )
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(MCDesign.Colors.surfaceInset)
    }

    private func selectAnswer(_ answer: PHQ2Answer) {
        phq2State.answers[currentIndex] = answer
        if currentIndex < 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentIndex += 1
            }
        } else if phq2State.isComplete {
            onComplete()
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 0: return MCDesign.Colors.success
        case 1: return MCDesign.Colors.warning
        case 2: return Color(hex: "#F97316")
        default: return MCDesign.Colors.error
        }
    }
}

#Preview {
    PHQ2View(phq2State: .constant(PHQ2State()), onComplete: {})
}

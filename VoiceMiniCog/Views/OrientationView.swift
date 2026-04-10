//
//  OrientationView.swift
//  VoiceMiniCog
//
//  Qmci Orientation subtest — 5 questions about date/location.
//  Each correct = 2 points, max 10.
//

import SwiftUI

struct OrientationView: View {
    @ObservedObject var qmciState: QmciState
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var patientAnswer = ""
    @State private var showResult = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Orientation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                Spacer()
                Text("\(currentIndex + 1) of \(ORIENTATION_ITEMS.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MCDesign.Colors.textTertiary)

                // Running score
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(MCDesign.Colors.success)
                    Text("\(qmciState.orientationScore)/10")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.white)
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)

            // Progress
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(MCDesign.Colors.border)
                    Rectangle()
                        .fill(MCDesign.Colors.primary700)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(ORIENTATION_ITEMS.count))
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .frame(height: 4)

            Spacer()

            if currentIndex < ORIENTATION_ITEMS.count {
                let item = ORIENTATION_ITEMS[currentIndex]

                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(MCDesign.Colors.primary700.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "calendar")
                            .font(.system(size: 28))
                            .foregroundColor(MCDesign.Colors.primary700)
                    }

                    // Question
                    Text(item.question)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(MCDesign.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Voice input (with text fallback)
                    CompactSpeechListener { transcript in
                        patientAnswer = transcript
                    }
                    .padding(.horizontal, 32)

                    // Text fallback
                    TextField("Or type the answer...", text: $patientAnswer)
                        .font(MCDesign.Fonts.body)
                        .padding(MCDesign.Spacing.md)
                        .background(MCDesign.Colors.surface)
                        .cornerRadius(MCDesign.Radius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                                .stroke(MCDesign.Colors.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                        .submitLabel(.done)
                        .onSubmit { checkAnswer() }

                    // Result indicator (legacy view — avatar flow uses auto-advance)
                    if showResult, let score = qmciState.orientationScores[currentIndex] {
                        HStack(spacing: 8) {
                            Image(systemName: score >= 2 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 20))
                        }
                        .foregroundColor(score >= 2 ? MCDesign.Colors.success : MCDesign.Colors.error)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            Spacer()

            // Back
            if currentIndex > 0 && !showResult {
                Button(action: goBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                        Text("Previous")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(MCDesign.Colors.textSecondary)
                }
                .padding(.bottom, 24)
            }
        }
        .background(MCDesign.Colors.surfaceInset)
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
        .animation(.easeInOut(duration: 0.2), value: showResult)
    }

    private func checkAnswer() {
        guard currentIndex < ORIENTATION_ITEMS.count else { return }
        let item = ORIENTATION_ITEMS[currentIndex]
        let correct = scoreOrientationAnswer(type: item.correctAnswerType, transcript: patientAnswer)
        qmciState.orientationScores[currentIndex] = correct ? 2 : 0
        // Persist raw patient response + attempted flag for view-layer display
        if currentIndex < qmciState.orientationResponses.count {
            qmciState.orientationResponses[currentIndex] = patientAnswer
        }
        let trimmed = patientAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, currentIndex < qmciState.orientationAttempted.count {
            qmciState.orientationAttempted[currentIndex] = true
        }
        showResult = true
        advanceAfterDelay()
    }

    private func scoreManual(correct: Bool) {
        qmciState.orientationScores[currentIndex] = correct ? 2 : 0
        // Persist raw patient response + attempted flag for view-layer display
        if currentIndex < qmciState.orientationResponses.count {
            qmciState.orientationResponses[currentIndex] = patientAnswer
        }
        let trimmed = patientAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, currentIndex < qmciState.orientationAttempted.count {
            qmciState.orientationAttempted[currentIndex] = true
        }
        showResult = true
        advanceAfterDelay()
    }

    private func advanceAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showResult = false
            patientAnswer = ""
            if currentIndex < ORIENTATION_ITEMS.count - 1 {
                currentIndex += 1
            } else {
                qmciState.completedSubtests.insert(.orientation)
                onComplete()
            }
        }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        patientAnswer = ""
        qmciState.orientationScores[currentIndex] = nil
    }
}

#Preview {
    OrientationView(qmciState: QmciState(), onComplete: {})
}

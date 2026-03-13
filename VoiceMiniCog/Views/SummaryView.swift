//
//  SummaryView.swift
//  VoiceMiniCog
//
//  Displays assessment results
//

import SwiftUI

struct SummaryView: View {
    var state: AssessmentState
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Assessment Complete")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top, 24)

                // Score banner
                VStack(spacing: 8) {
                    Text("\(state.totalScore) / 5")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(state.isPositiveScreen ? .red : .green)

                    Text(state.isPositiveScreen ? "Screen Positive" : "Screen Negative")
                        .font(.headline)
                        .foregroundColor(state.isPositiveScreen ? .red : .green)

                    Text(state.isPositiveScreen
                         ? "Further evaluation recommended"
                         : "No significant impairment detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(state.isPositiveScreen
                              ? Color.red.opacity(0.1)
                              : Color.green.opacity(0.1))
                )
                .padding(.horizontal)

                // Score breakdown
                VStack(alignment: .leading, spacing: 16) {
                    Text("Score Breakdown")
                        .font(.headline)

                    ScoreRow(
                        label: "Word Recall",
                        score: state.recallScore,
                        maxScore: 3,
                        detail: state.recalledWords.isEmpty
                            ? nil
                            : "Recalled: \(state.recalledWords.joined(separator: ", "))"
                    )

                    ScoreRow(
                        label: "Clock Drawing",
                        score: state.clockScore ?? 0,
                        maxScore: 2,
                        detail: state.clockAnalysis?.interpretation
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal)

                // Clock image (if available)
                if let clockImage = state.clockImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clock Drawing")
                            .font(.headline)

                        Image(uiImage: clockImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200)
                            .cornerRadius(8)
                            .shadow(radius: 2)
                    }
                    .padding(.horizontal)
                }

                // Done button
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Score Row

struct ScoreRow: View {
    let label: String
    let score: Int
    let maxScore: Int
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)

                Spacer()

                Text("\(score) / \(maxScore)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(score == maxScore ? .green : (score == 0 ? .red : .orange))
            }

            if let detail = detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let state = AssessmentState()
    state.recallScore = 2
    state.clockScore = 1
    state.recalledWords = ["banana", "chair"]

    return SummaryView(state: state, onDone: {})
}

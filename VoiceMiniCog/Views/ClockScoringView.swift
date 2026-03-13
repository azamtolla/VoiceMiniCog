//
//  ClockScoringView.swift
//  VoiceMiniCog
//
//  Clinician clock scoring view matching React
//

import SwiftUI

struct ClockScoringView: View {
    var state: AssessmentState
    var onScore: (Int, ClockScoreSource) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("Clinician Evaluation")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MercyColors.gray500)
                    .textCase(.uppercase)
                    .tracking(1)

                // Clock image
                if let image = state.clockImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MercyColors.gray200, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                // AI suggestion (if available)
                if let analysis = state.clockAnalysis {
                    aiSuggestionCard(analysis: analysis)
                }

                // Scoring options
                Text("Select your clinical assessment:")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(MercyColors.gray700)

                VStack(spacing: 12) {
                    ForEach(MiniCogClockOption.all, id: \.score) { option in
                        scoreOption(option)
                    }
                }

                // Accept AI button
                if let analysis = state.clockAnalysis {
                    Button(action: { onScore(analysis.aiClass, .ai) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Accept AI Score: \(analysis.severity) (\(analysis.aiClass))")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(MercyColors.mercyBlue)
                        .cornerRadius(12)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .background(Color.white)
    }

    private func scoreOption(_ option: MiniCogClockOption) -> some View {
        let color: Color = option.score == 0 ? MercyColors.error :
                           option.score == 1 ? MercyColors.warning : MercyColors.success
        let bgColor: Color = option.score == 0 ? MercyColors.error.opacity(0.1) :
                             option.score == 1 ? MercyColors.warning.opacity(0.1) : MercyColors.success.opacity(0.1)

        let isAIPick = state.clockAnalysis?.aiClass == option.score

        return Button(action: { onScore(option.score, .clinician) }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(option.score) - \(option.label)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MercyColors.gray800)

                    Text(option.description)
                        .font(.system(size: 13))
                        .foregroundColor(MercyColors.gray600)

                    Text(option.shulmanRange)
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray500)
                }

                Spacer()

                if isAIPick {
                    Text("AI Pick")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color)
                        .cornerRadius(8)
                }
            }
            .padding(16)
            .background(bgColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: 2)
            )
        }
    }

    private func aiSuggestionCard(analysis: ClockAnalysisResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(MercyColors.mercyBlue)
                Text("AI Analysis (CDT Model)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MercyColors.mercyBlue)
            }

            // Main recommendation
            let color: Color = analysis.aiClass == 0 ? MercyColors.error :
                               analysis.aiClass == 1 ? MercyColors.warning : MercyColors.success

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.severity)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MercyColors.gray800)
                    Text("Shulman Score: \(analysis.shulmanRange)")
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray600)
                }

                Spacer()

                Text("\(Int(analysis.confidence * 100))% confident")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MercyColors.gray700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
            }
            .padding(12)
            .background(color.opacity(0.15))
            .cornerRadius(8)

            Text(analysis.interpretation)
                .font(.system(size: 14))
                .foregroundColor(MercyColors.gray700)

            // Probability bars
            VStack(alignment: .leading, spacing: 8) {
                Text("Probability Breakdown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MercyColors.gray500)

                probabilityBar(label: "Normal (Shulman 4-5)", value: analysis.probabilities.normal45, color: MercyColors.success)
                probabilityBar(label: "Moderate (Shulman 2-3)", value: analysis.probabilities.moderate23, color: MercyColors.warning)
                probabilityBar(label: "Severe (Shulman 0-1)", value: analysis.probabilities.severe01, color: MercyColors.error)
            }

            // Clinical action
            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended Action:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MercyColors.gray500)
                Text(analysis.clinicalAction)
                    .font(.system(size: 14))
                    .foregroundColor(MercyColors.gray700)
            }
            .padding(12)
            .background(MercyColors.gray50)
            .cornerRadius(8)
        }
        .padding(16)
        .background(MercyColors.mercyBlue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MercyColors.mercyBlue.opacity(0.2), lineWidth: 1)
        )
    }

    private func probabilityBar(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(MercyColors.gray600)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MercyColors.gray700)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MercyColors.gray100)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * value, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    ClockScoringView(state: AssessmentState()) { score, source in
        print("Score: \(score), Source: \(source)")
    }
}

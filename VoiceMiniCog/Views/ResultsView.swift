//
//  ResultsView.swift
//  VoiceMiniCog
//
//  Comprehensive results view matching React complete stage
//

import SwiftUI

struct ResultsView: View {
    var state: AssessmentState
    var onRestart: () -> Void
    var onFinalize: () -> Void

    @State private var expandedSections: Set<String> = ["clockScore", "interpretation"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Composite Risk Banner (if AD8 completed)
                if let risk = state.compositeRisk {
                    compositeRiskBanner(risk)
                }

                // AI Score Summary
                aiScoreSummary

                // AD8 Results (if completed)
                if state.ad8State.score != nil {
                    ad8ResultsCard
                } else if state.ad8State.declined {
                    ad8DeclinedCard
                }

                // Clinician Clock Score Selection
                clockScoreSelection

                // Screen Interpretation
                screenInterpretationSelection

                // Final Score Summary
                finalScoreSummary

                // Action Buttons
                actionButtons
            }
            .padding(20)
        }
        .background(MercyColors.gray50)
    }

    // MARK: - Composite Risk Banner

    private func compositeRiskBanner(_ risk: CompositeRiskOutput) -> some View {
        let color: Color = risk.tier == .low ? MercyColors.success :
                          risk.tier == .intermediate ? MercyColors.warning : MercyColors.error

        return VStack(alignment: .leading, spacing: 12) {
            Text("COMPOSITE COGNITIVE RISK (MINI-COG + AD8)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MercyColors.gray500)
                .tracking(0.5)

            Text(risk.label)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)

            Text(risk.summaryLine)
                .font(.system(size: 14))
                .foregroundColor(MercyColors.gray600)

            Text(risk.narrative)
                .font(.system(size: 14))
                .italic()
                .foregroundColor(MercyColors.gray700)
                .padding(12)
                .background(MercyColors.gray100)
                .cornerRadius(8)

            if !risk.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested Actions:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MercyColors.gray600)

                    ForEach(risk.suggestedActions, id: \.self) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(action)
                        }
                        .font(.system(size: 13))
                        .foregroundColor(MercyColors.gray600)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            Rectangle()
                .fill(color)
                .frame(width: 6)
                .cornerRadius(12, corners: [.topLeft, .bottomLeft]),
            alignment: .leading
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - AI Score Summary

    private var aiScoreSummary: some View {
        let aiClockScore = state.clockAnalysis?.aiClass ?? state.clockScore ?? 0
        let aiTotal = state.recallScore + aiClockScore

        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(MercyColors.mercyBlue)
                Text("AI-Estimated Scoring (for review)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MercyColors.gray800)
            }

            HStack(spacing: 24) {
                // Clock Score
                VStack(spacing: 4) {
                    Text("Clock (AI)")
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray500)
                    Text("\(aiClockScore)/2")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MercyColors.gray800)
                    scoreChip(score: aiClockScore, type: "clock")
                }

                // Recall Score
                VStack(spacing: 4) {
                    Text("Word Recall")
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray500)
                    Text("\(state.recallScore)/3")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MercyColors.gray800)
                    if !state.recalledWords.isEmpty {
                        Text(state.recalledWords.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(MercyColors.gray500)
                    }
                }

                // Total
                VStack(spacing: 4) {
                    Text("AI Total")
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray500)
                    Text("\(aiTotal)/5")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(aiTotal < 3 ? MercyColors.error : MercyColors.success)
                }
            }

            // Clock image
            if let image = state.clockImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MercyColors.gray200, lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - AD8 Results Card

    private var ad8ResultsCard: some View {
        let score = state.ad8State.score ?? 0
        let isPositive = score >= 2

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .foregroundColor(Color(hex: "#ea580c"))
                Text("AD8 Dementia Screening")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MercyColors.gray800)

                Text(state.ad8State.respondentType == .informant ? "Informant" : "Self-Report")
                    .font(.system(size: 11))
                    .foregroundColor(MercyColors.gray600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MercyColors.gray100)
                    .cornerRadius(4)
            }

            HStack(alignment: .top, spacing: 24) {
                // Score
                VStack(spacing: 4) {
                    Text("\(score)/8")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(isPositive ? MercyColors.error : MercyColors.success)

                    Text(isPositive ? "Screen Positive" : "Screen Negative")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isPositive ? MercyColors.error : MercyColors.success)
                        .cornerRadius(8)
                }

                // Flagged domains
                if !state.ad8State.flaggedDomains.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flagged Domains")
                            .font(.system(size: 12))
                            .foregroundColor(MercyColors.gray500)

                        FlowLayout(spacing: 4) {
                            ForEach(state.ad8State.flaggedDomains, id: \.self) { domain in
                                Text(domain)
                                    .font(.system(size: 11))
                                    .foregroundColor(MercyColors.gray600)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MercyColors.gray100)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }

            // Self-report warning
            if state.ad8State.respondentType == .selfReport && score >= 2 && score <= 3 {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(MercyColors.mercyBlue)
                    Text("Borderline self-report AD8 score. Consider informant corroboration for higher accuracy.")
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray600)
                }
                .padding(10)
                .background(MercyColors.mercyBlue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPositive ? MercyColors.warning : MercyColors.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - AD8 Declined Card

    private var ad8DeclinedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 24))
                .foregroundColor(MercyColors.gray400)

            Text("AD8 Dementia Screening")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MercyColors.gray800)

            Text("AD8 was declined by the patient")
                .font(.system(size: 14))
                .foregroundColor(MercyColors.gray500)
                .italic()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MercyColors.gray300, lineWidth: 1)
        )
    }

    // MARK: - Clock Score Selection

    private var clockScoreSelection: some View {
        let aiScore = state.clockAnalysis?.aiClass ?? state.clockScore ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Clinician Clock Drawing Score")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MercyColors.gray800)

            ForEach(0..<3) { score in
                let option = MiniCogClockOption.all[2 - score] // Reverse order: 2, 1, 0
                let isSelected = state.clinicianClockScore == option.score
                let isAIPick = aiScore == option.score
                let color: Color = option.score == 0 ? MercyColors.error :
                                   option.score == 1 ? MercyColors.warning : MercyColors.success

                Button(action: { state.clinicianClockScore = option.score }) {
                    HStack {
                        Circle()
                            .strokeBorder(isSelected ? color : MercyColors.gray300, lineWidth: 2)
                            .background(Circle().fill(isSelected ? color : Color.clear))
                            .frame(width: 20, height: 20)
                            .overlay(
                                isSelected ? Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white) : nil
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("\(option.score) - \(option.label)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MercyColors.gray800)

                                if isAIPick {
                                    Text("AI")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(color)
                                        .cornerRadius(4)
                                }
                            }

                            Text(option.shulmanRange)
                                .font(.system(size: 12))
                                .foregroundColor(MercyColors.gray500)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(isSelected ? color.opacity(0.1) : Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color : MercyColors.gray200, lineWidth: isSelected ? 2 : 1)
                    )
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Screen Interpretation Selection

    private var screenInterpretationSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen Interpretation (clinician selects)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MercyColors.gray800)

            VStack(spacing: 8) {
                interpretationOption(
                    interpretation: .negative,
                    label: "Negative screen",
                    description: "Mini-Cog ≥ 3, no additional concern",
                    color: MercyColors.success
                )

                interpretationOption(
                    interpretation: .positive,
                    label: "Positive screen",
                    description: "Further evaluation indicated",
                    color: MercyColors.error
                )

                interpretationOption(
                    interpretation: .notInterpretable,
                    label: "Result not interpretable",
                    description: "Hearing, language, motor, or other limitations",
                    color: MercyColors.gray500
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func interpretationOption(interpretation: ScreenInterpretation, label: String, description: String, color: Color) -> some View {
        let isSelected = state.screenInterpretation == interpretation

        return Button(action: { state.screenInterpretation = interpretation }) {
            HStack {
                Circle()
                    .strokeBorder(isSelected ? color : MercyColors.gray300, lineWidth: 2)
                    .background(Circle().fill(isSelected ? color : Color.clear))
                    .frame(width: 20, height: 20)
                    .overlay(
                        isSelected ? Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white) : nil
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MercyColors.gray800)

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(MercyColors.gray500)
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? color.opacity(0.1) : Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : MercyColors.gray200, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    // MARK: - Final Score Summary

    private var finalScoreSummary: some View {
        let total = state.clinicianTotalScore

        return VStack(spacing: 8) {
            Text("FINAL MINI-COG TOTAL (CLINICIAN-CONFIRMED)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MercyColors.gray500)
                .tracking(0.5)

            Text("\(total) / 5")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(total < 3 ? MercyColors.error : MercyColors.success)

            HStack(spacing: 16) {
                Text("Clock: \(state.clinicianClockScore ?? 0)/2")
                    .font(.system(size: 14))
                    .foregroundColor(MercyColors.gray600)

                Text("Recall: \(state.recallScore)/3")
                    .font(.system(size: 14))
                    .foregroundColor(MercyColors.gray600)
            }

            // AD8 info
            if let ad8Score = state.ad8State.score {
                Divider()
                    .padding(.vertical, 8)

                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("AD8 Score")
                            .font(.system(size: 12))
                            .foregroundColor(MercyColors.gray500)
                        Text("\(ad8Score)/8")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ad8Score >= 2 ? MercyColors.error : MercyColors.success)
                    }

                    if let risk = state.compositeRisk {
                        VStack(spacing: 2) {
                            Text("Composite Risk")
                                .font(.system(size: 12))
                                .foregroundColor(MercyColors.gray500)
                            Text(risk.label)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(
                                    risk.tier == .low ? MercyColors.success :
                                    risk.tier == .intermediate ? MercyColors.warning : MercyColors.error
                                )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(MercyColors.gray50)
        .cornerRadius(12)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onFinalize) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirm & Save Assessment")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    (state.clinicianClockScore != nil && state.screenInterpretation != nil)
                    ? MercyColors.mercyBlue : MercyColors.gray300
                )
                .cornerRadius(12)
            }
            .disabled(state.clinicianClockScore == nil || state.screenInterpretation == nil)

            Button(action: onRestart) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Start Over")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MercyColors.gray600)
            }
        }
    }

    // MARK: - Helpers

    private func scoreChip(score: Int, type: String) -> some View {
        let label: String
        let color: Color

        if type == "clock" {
            switch score {
            case 0:
                label = "Severe"
                color = MercyColors.error
            case 1:
                label = "Moderate"
                color = MercyColors.warning
            default:
                label = "Normal"
                color = MercyColors.success
            }
        } else {
            label = score >= 2 ? "Normal" : "Impaired"
            color = score >= 2 ? MercyColors.success : MercyColors.error
        }

        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += maxHeight + spacing
                maxHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            maxHeight = max(maxHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }

        return (CGSize(width: totalWidth, height: currentY + maxHeight), positions)
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ResultsView(
        state: AssessmentState(),
        onRestart: {},
        onFinalize: {}
    )
}

//
//  ProgressTrackView.swift
//  VoiceMiniCog
//
//  Weighted segmented progress bar for the avatar assessment canvas.
//  Segment widths are proportional to clinical phase weights.
//

import SwiftUI

struct ProgressTrackView: View {
    let layoutManager: AvatarLayoutManager

    private let weights = AssessmentTheme.progressWeights
    private var totalWeight: Int { weights.reduce(0, +) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            // Segmented progress bar
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                        let segmentWidth = segmentWidth(for: weight, totalWidth: geometry.size.width)
                        segmentView(for: index, width: segmentWidth)
                    }
                }
            }
            .frame(height: AssessmentTheme.Sizing.progressTrackHeight)

            // Phase name label
            Text(layoutManager.currentPhase.displayName.uppercased())
                .font(AssessmentTheme.Fonts.phaseLabel)
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .tracking(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Segment View

    @ViewBuilder
    private func segmentView(for index: Int, width: CGFloat) -> some View {
        let phaseIndex = index + 1 // phases are 1-indexed
        let currentIndex = layoutManager.currentPhase.rawValue

        RoundedRectangle(cornerRadius: 2)
            .fill(segmentColor(phaseIndex: phaseIndex, currentIndex: currentIndex))
            .frame(width: width, height: AssessmentTheme.Sizing.progressTrackHeight)
            .animation(.easeInOut(duration: 0.3), value: currentIndex)
    }

    // MARK: - Helpers

    private func segmentColor(phaseIndex: Int, currentIndex: Int) -> Color {
        if phaseIndex < currentIndex {
            // Completed phase — full accent color
            return AssessmentTheme.accent(for: phaseIndex)
        } else if phaseIndex == currentIndex {
            // Active phase — current phase accent color
            return AssessmentTheme.accent(for: phaseIndex)
        } else {
            // Upcoming phase — muted gray
            return Color.gray.opacity(0.2)
        }
    }

    private func segmentWidth(for weight: Int, totalWidth: CGFloat) -> CGFloat {
        guard totalWeight > 0 else { return 0 }
        let segmentCount = CGFloat(weights.count)
        let totalSpacing = 2.0 * (segmentCount - 1)
        let availableWidth = totalWidth - totalSpacing
        return availableWidth * CGFloat(weight) / CGFloat(totalWeight)
    }
}

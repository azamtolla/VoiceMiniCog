//
//  ProgressTrackView.swift
//  VoiceMiniCog
//
//  Segmented progress bar driven by the layout manager's phase sequence.
//  Only shows segments for phases in the current flow type.
//

import SwiftUI

struct ProgressTrackView: View {
    let layoutManager: AvatarLayoutManager

    private var phases: [AssessmentPhaseID] { layoutManager.phaseSequence }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            // Segmented progress bar
            GeometryReader { geometry in
                let segmentCount = CGFloat(phases.count)
                let totalSpacing = 2.0 * (segmentCount - 1)
                let segmentWidth = (geometry.size.width - totalSpacing) / segmentCount

                HStack(spacing: 2) {
                    ForEach(Array(phases.enumerated()), id: \.element) { index, phase in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segmentColor(for: phase))
                            .frame(width: segmentWidth, height: AssessmentTheme.Sizing.progressTrackHeight)
                            .animation(.easeInOut(duration: 0.3), value: layoutManager.currentPhase)
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

    // MARK: - Segment Color

    private func segmentColor(for phase: AssessmentPhaseID) -> Color {
        let currentIndex = layoutManager.currentPhaseIndex
        guard let phaseIndex = phases.firstIndex(of: phase) else {
            return Color.gray.opacity(0.2)
        }

        if phaseIndex < currentIndex {
            return AssessmentTheme.accent(for: phase.rawValue)
        } else if phaseIndex == currentIndex {
            return AssessmentTheme.accent(for: phase.rawValue)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

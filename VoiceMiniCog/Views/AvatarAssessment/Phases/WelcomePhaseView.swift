//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. Displays assessment overview, subtest list,
//  Begin Assessment button, and a Standard Mode (No Avatar) fallback link.
//

import SwiftUI

// MARK: - WelcomePhaseView

struct WelcomePhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // MARK: Brain Icon
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 14)

            // MARK: Title
            Text("Brain Health Assessment")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            // MARK: Subtitle
            Text("6 cognitive activities, about 5-7 minutes")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            // MARK: Subtest List Card
            VStack(spacing: 0) {
                ForEach(Array(QmciSubtest.allCases.enumerated()), id: \.element) { index, subtest in
                    SubtestRow(subtest: subtest, accentColor: layoutManager.accentColor)

                    if index < QmciSubtest.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(AssessmentTheme.Content.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                radius: 12,
                y: 2
            )
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            Spacer()

            // MARK: Begin Assessment Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                layoutManager.transitionTo(.qdrs)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Begin Assessment")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(layoutManager.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(
                    color: layoutManager.accentColor.opacity(0.35),
                    radius: 8,
                    y: 4
                )
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            // MARK: Bottom Padding
            Spacer().frame(height: 16)
        }
    }
}

// MARK: - SubtestRow

private struct SubtestRow: View {

    let subtest: QmciSubtest
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: subtest.iconName)
                .font(.system(size: 16))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            Text(subtest.displayName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)

            Spacer()

            Text("\(subtest.maxScore) pts")
                .font(.system(size: 13))
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview {
    WelcomePhaseView(
        layoutManager: AvatarLayoutManager(),
    )
    .background(AssessmentTheme.Content.background)
}

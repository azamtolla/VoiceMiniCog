//
//  MiniCogIntroView.swift
//  VoiceMiniCog
//
//  Qmci intro — previews subtests. Used when no mode choice is needed.
//

import SwiftUI

struct MiniCogIntroView: View {
    let onStart: () -> Void

    var body: some View {
        QmciModePickerView(onStandard: onStart, onAvatar: onStart)
    }
}

/// Mode picker: lets clinician choose Standard (on-device) or Avatar (PersonaPlex) mode.
struct QmciModePickerView: View {
    let onStandard: () -> Void
    let onAvatar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MCDesign.Spacing.lg) {
                MCIconCircle(
                    icon: "brain.head.profile",
                    color: MCDesign.Colors.primary700,
                    size: MCDesign.Sizing.iconXL
                )

                Text("Brain Health Assessment")
                    .font(MCDesign.Fonts.screenTitle)
                    .foregroundColor(MCDesign.Colors.textPrimary)

                Text("6 cognitive activities, about 5-7 minutes")
                    .font(MCDesign.Fonts.body)
                    .foregroundColor(MCDesign.Colors.textSecondary)

                // Subtests preview
                MCCard {
                    VStack(alignment: .leading, spacing: MCDesign.Spacing.sm) {
                        ForEach(QmciSubtest.allCases, id: \.rawValue) { subtest in
                            HStack(spacing: MCDesign.Spacing.md) {
                                MCIconCircle(
                                    icon: subtest.iconName,
                                    color: MCDesign.Colors.primary500,
                                    size: MCDesign.Sizing.iconSmall
                                )
                                Text(subtest.displayName)
                                    .font(MCDesign.Fonts.bodyMedium)
                                    .foregroundColor(MCDesign.Colors.textPrimary)
                                Spacer()
                                Text("\(subtest.maxScore) pts")
                                    .font(MCDesign.Fonts.smallCaption)
                                    .foregroundColor(MCDesign.Colors.textTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, MCDesign.Spacing.md)
            }
            .padding(.horizontal, MCDesign.Spacing.lg)

            Spacer()

            // Two mode buttons
            VStack(spacing: MCDesign.Spacing.md) {
                MCPrimaryButton("Start Assessment", icon: "play.fill") {
                    onStandard()
                }

                MCSecondaryButton("Use Avatar Guide", icon: "person.crop.circle.fill") {
                    onAvatar()
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .padding(.bottom, MCDesign.Spacing.xxl)
        }
        .background(MCDesign.Colors.background)
    }
}

#Preview {
    QmciModePickerView(onStandard: {}, onAvatar: {})
}

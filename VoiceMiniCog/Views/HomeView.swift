//
//  HomeView.swift
//  VoiceMiniCog
//
//  Screen 1: Entry point — "Brain Health Screen"
//

import SwiftUI

struct HomeView: View {
    let onStart: (QDRSRespondentType) -> Void

    @State private var respondentType: QDRSRespondentType = .patient

    var body: some View {
        ZStack {
            MCDesign.Colors.background.ignoresSafeArea()

            VStack {
                Spacer()

                MCCard {
                    VStack(spacing: MCDesign.Spacing.lg) {
                        // Header
                        VStack(spacing: MCDesign.Spacing.sm) {
                            MCIconCircle(
                                icon: "brain.head.profile",
                                color: MCDesign.Colors.primary700,
                                size: MCDesign.Sizing.iconLarge
                            )

                            Text("Brain Health Screen")
                                .font(MCDesign.Fonts.screenTitle)
                                .foregroundColor(MCDesign.Colors.primary700)

                            Text("QDRS + Cognitive Assessment (~8 min)")
                                .font(MCDesign.Fonts.caption)
                                .foregroundColor(MCDesign.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)

                        // Respondent selector
                        VStack(alignment: .leading, spacing: MCDesign.Spacing.sm) {
                            Text("Who is completing the questionnaire?")
                                .font(MCDesign.Fonts.bodySemibold)
                                .foregroundColor(MCDesign.Colors.textPrimary)

                            VStack(spacing: MCDesign.Spacing.sm) {
                                respondentOption(
                                    type: .patient,
                                    label: "Patient",
                                    icon: "person.fill",
                                    detail: "Patient answers about themselves"
                                )
                                respondentOption(
                                    type: .informant,
                                    label: "Informant / Caregiver",
                                    icon: "person.2.fill",
                                    detail: "Family member or caregiver answers"
                                )
                            }
                        }

                        // Start button
                        MCPrimaryButton("Start Screening", icon: "play.fill") {
                            onStart(respondentType)
                        }
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, MCDesign.Spacing.md)

                Spacer()
            }
        }
    }

    private func respondentOption(type: QDRSRespondentType, label: String, icon: String, detail: String) -> some View {
        let isSelected = respondentType == type

        return Button(action: {
            withAnimation(MCDesign.Anim.quick) { respondentType = type }
        }) {
            HStack(spacing: MCDesign.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? MCDesign.Colors.primary700 : MCDesign.Colors.textTertiary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(MCDesign.Fonts.bodyMedium)
                        .foregroundColor(isSelected ? MCDesign.Colors.primary700 : MCDesign.Colors.textPrimary)
                    Text(detail)
                        .font(MCDesign.Fonts.smallCaption)
                        .foregroundColor(MCDesign.Colors.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(MCDesign.Colors.primary500)
                }
            }
            .padding(MCDesign.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: MCDesign.Sizing.touchTargetMin)
            .background(isSelected ? MCDesign.Colors.primary50 : MCDesign.Colors.surface)
            .cornerRadius(MCDesign.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                    .stroke(isSelected ? MCDesign.Colors.primary500 : MCDesign.Colors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(onStart: { _ in })
}

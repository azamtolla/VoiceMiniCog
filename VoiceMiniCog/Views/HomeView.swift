//
//  HomeView.swift
//  VoiceMiniCog
//
//  Three-card assessment launcher: Quick, Caregiver, Extended.
//  HA-inspired card styling with staggered entrance animations.
//

import SwiftUI

struct HomeView: View {
    let onSelectFlow: (AssessmentFlowType) -> Void
    var onResume: (() -> Void)? = nil

    @State private var hasInProgress: Bool = false
    @State private var headerAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MCDesign.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Header
                VStack(spacing: MCDesign.Spacing.sm) {
                    MCIconCircle(
                        icon: "brain.head.profile",
                        color: MCDesign.Colors.primary700,
                        size: MCDesign.Sizing.iconLarge
                    )

                    Text("Brain Health Screen")
                        .font(MCDesign.Fonts.screenTitle)
                        .foregroundColor(MCDesign.Colors.primary700)

                    Text("Select an assessment type to begin")
                        .font(MCDesign.Fonts.caption)
                        .foregroundColor(MCDesign.Colors.textTertiary)
                }
                .opacity(headerAppeared ? 1 : 0)
                .offset(y: headerAppeared ? 0 : -10)
                .padding(.bottom, MCDesign.Spacing.xl)

                // MARK: Three Cards
                HStack(spacing: 20) {
                    AssessmentCard(
                        title: "Quick\nAssessment",
                        icon: "bolt.fill",
                        accentColor: AssessmentTheme.Phase.welcome,
                        staggerIndex: 0
                    ) {
                        onSelectFlow(.quick)
                    }

                    AssessmentCard(
                        title: "Family / Caregiver\nQuestionnaire",
                        icon: "person.2.fill",
                        accentColor: AssessmentTheme.Phase.qdrs,
                        staggerIndex: 1
                    ) {
                        onSelectFlow(.caregiver)
                    }

                    AssessmentCard(
                        title: "Extended\nAssessment",
                        icon: "list.clipboard.fill",
                        accentColor: AssessmentTheme.Phase.clock,
                        staggerIndex: 2
                    ) {
                        onSelectFlow(.extended)
                    }
                }
                .frame(maxWidth: 880)
                .padding(.horizontal, MCDesign.Spacing.lg)

                // MARK: Resume Banner
                if hasInProgress {
                    Button(action: { onResume?() }) {
                        HStack(spacing: MCDesign.Spacing.sm) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume Assessment")
                                    .font(MCDesign.Fonts.bodySemibold)
                                Text("An interrupted assessment was found")
                                    .font(MCDesign.Fonts.smallCaption)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(MCDesign.Spacing.md)
                        .frame(maxWidth: 880, minHeight: MCDesign.Sizing.touchTargetMin)
                        .background(MCDesign.Colors.primary700)
                        .cornerRadius(MCDesign.Radius.medium)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, MCDesign.Spacing.lg)
                    .padding(.horizontal, MCDesign.Spacing.lg)
                }

                Spacer()
            }
        }
        .onAppear {
            hasInProgress = AssessmentPersistence.hasInProgressAssessment()
            if reduceMotion {
                headerAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                    headerAppeared = true
                }
            }
        }
    }
}

#Preview {
    HomeView(onSelectFlow: { _ in }, onResume: {})
}

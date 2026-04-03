//
//  AvatarAssessmentCanvas.swift
//  VoiceMiniCog
//
//  Root view for the avatar-guided assessment.
//  ONE unified canvas: content zone (left) + avatar zone (right).
//  Layout ratios are driven by AvatarLayoutManager per phase.
//

import SwiftUI

// MARK: - AvatarAssessmentCanvas

struct AvatarAssessmentCanvas: View {

    @Bindable var assessmentState: AssessmentState
    let conversationURL: String?
    let onComplete: () -> Void
    let onFallback: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    @State private var showPauseSheet = false

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let avatarWidth  = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // MARK: Layer 1 — Unified background gradient
                // Light #F8F9FA on left → dark #080808 on right,
                // gradient stop animated with avatarWidthRatio.
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                        .init(
                            color: Color(hex: "#F8F9FA"),
                            location: 1.0 - layoutManager.avatarWidthRatio
                        ),
                        .init(color: Color(hex: "#080808"), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.avatarWidthRatio)

                // MARK: Layer 2 — Content + Avatar HStack
                HStack(spacing: 0) {

                    // MARK: Content Zone (left)
                    contentZone
                        .frame(width: contentWidth)

                    // MARK: Avatar Zone (right)
                    avatarZone(width: avatarWidth, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
        .pauseSheet(
            isPresented: $showPauseSheet,
            accentColor: layoutManager.accentColor,
            onCancel: onCancel
        )
    }

    // MARK: - Content Zone

    @ViewBuilder
    private var contentZone: some View {
        VStack(spacing: 0) {
            // Progress track — 60pt top padding for safe area
            progressTrackPlaceholder
                .padding(.top, 60)

            // Phase-specific content
            Group {
                phaseContent
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .id(layoutManager.currentPhase)
                    .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Pause button
            pauseButton
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Phase Content Switch

    @ViewBuilder
    private var phaseContent: some View {
        switch layoutManager.currentPhase {
        case .welcome:
            WelcomePhaseView(layoutManager: layoutManager, onStandard: onFallback)
        case .qdrs:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .qdrs)
        case .phq2:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .phq2)
        case .orientation:
            QAPhaseView(layoutManager: layoutManager, assessmentState: assessmentState, phaseID: .orientation)
        case .wordRegistration:
            WordRegistrationPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .clockDrawing:
            ClockDrawingPhaseView(layoutManager: layoutManager, assessmentState: assessmentState)
        case .verbalFluency:
            VerbalFluencyPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .storyRecall:
            StoryRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState)
        case .wordRecall:
            WordRecallPhaseView(layoutManager: layoutManager, qmciState: assessmentState.qmciState, onComplete: onComplete)
        }
    }

    // MARK: - Progress Track

    private var progressTrackPlaceholder: some View {
        ProgressTrackView(layoutManager: layoutManager)
    }

    // MARK: - Pause Button

    private var pauseButton: some View {
        PauseButtonView {
            showPauseSheet = true
        }
    }

    // MARK: - Avatar Zone

    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: conversationURL,
            width: width,
            height: height
        )
        .frame(width: width, height: height)
    }
}

// MARK: - Pause Sheet View Modifier

private struct PauseSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let accentColor: Color
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                VStack(spacing: 24) {
                    Text("Assessment Paused")
                        .font(.system(size: 22, weight: .bold))
                    Text("The patient can take a break.")
                        .font(.system(size: 16))
                        .foregroundColor(AssessmentTheme.Content.textSecondary)
                    Button("Resume Assessment") { isPresented = false }
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(accentColor)
                        .cornerRadius(14)
                    Button("End Session") {
                        isPresented = false
                        onCancel()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "#DC2626"))
                }
                .padding(32)
                .presentationDetents([.medium])
            }
    }
}

private extension View {
    func pauseSheet(
        isPresented: Binding<Bool>,
        accentColor: Color,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(PauseSheetModifier(
            isPresented: isPresented,
            accentColor: accentColor,
            onCancel: onCancel
        ))
    }
}

// MARK: - Preview

#Preview {
    AvatarAssessmentCanvas(
        assessmentState: AssessmentState(),
        conversationURL: nil,
        onComplete: {},
        onFallback: {},
        onCancel: {}
    )
}

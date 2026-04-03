//
//  AvatarZoneView.swift
//  VoiceMiniCog
//
//  Right side of the avatar assessment canvas — dark radial gradient,
//  Tavus CVI video, accent ring, and avatar state label.
//

import SwiftUI

// MARK: - CLINICAL-UI
// Displays the AI avatar video stream and behavioral state indicator.
// No PHI is rendered here — only the avatar video feed and state label.

struct AvatarZoneView: View {
    let layoutManager: AvatarLayoutManager
    let conversationURL: String?
    let width: CGFloat
    let height: CGFloat

    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 1.0

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Dark radial gradient background
            RadialGradient(
                colors: [AssessmentTheme.Avatar.gradientCenter, AssessmentTheme.Avatar.gradientEdge],
                center: .center,
                startRadius: 0,
                endRadius: max(width, height) * 0.7
            )

            // 2. Tavus CVI video feed (when conversation is active)
            if let url = conversationURL {
                TavusCVIView(conversationURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(16)
                    .opacity(layoutManager.avatarOpacity)
                    .animation(.easeInOut(duration: 0.3), value: layoutManager.avatarOpacity)
            }

            // 3. Accent ring (hidden during .waiting)
            if layoutManager.showAvatarRing {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(layoutManager.accentColor, lineWidth: AssessmentTheme.Sizing.avatarRingWidth)
                    .padding(16)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .animation(.easeInOut(duration: 0.3), value: ringScale)
                    .animation(.easeInOut(duration: 0.3), value: ringOpacity)
            }

            // 4. State label at bottom
            VStack {
                Spacer()
                avatarStateLabel
                    .padding(.bottom, 20)
            }
        }
        .onChange(of: layoutManager.avatarBehavior) { _, newBehavior in
            updateRingAnimation(for: newBehavior)
        }
        .onAppear {
            updateRingAnimation(for: layoutManager.avatarBehavior)
        }
    }

    // MARK: - State Label

    @ViewBuilder
    private var avatarStateLabel: some View {
        let labelText = stateLabelText(for: layoutManager.avatarBehavior)
        if !labelText.isEmpty {
            Text(labelText)
                .font(AssessmentTheme.Fonts.avatarLabel)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    // MARK: - Helpers

    private func stateLabelText(for behavior: AvatarBehavior) -> String {
        switch behavior {
        case .speaking:        return "Speaking..."
        case .listening:       return "Listening..."
        case .narrating:       return "Reading story..."
        case .idle:            return "Ready"
        case .acknowledging:   return "Got it..."
        case .waiting:         return ""
        case .completing:      return "Finishing up..."
        }
    }

    private func updateRingAnimation(for behavior: AvatarBehavior) {
        switch behavior {
        case .speaking, .narrating:
            withAnimation(
                .easeInOut(duration: AssessmentTheme.Anim.ringPulseDuration)
                .repeatForever(autoreverses: true)
            ) {
                ringScale = 1.03
                ringOpacity = 1.0
            }

        case .listening:
            withAnimation(
                .easeInOut(duration: AssessmentTheme.Anim.ringPulseDuration)
                .repeatForever(autoreverses: true)
            ) {
                ringScale = 1.05
                ringOpacity = 1.0
            }

        case .idle:
            withAnimation(
                .easeInOut(duration: AssessmentTheme.Anim.ringPulseDuration)
                .repeatForever(autoreverses: true)
            ) {
                ringOpacity = 0.4
                ringScale = 1.0
            }

        case .acknowledging:
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                ringScale = 1.08
                ringOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    ringScale = 1.0
                }
            }

        case .waiting:
            withAnimation(.easeInOut(duration: 0.2)) {
                ringOpacity = 0.0
                ringScale = 1.0
            }

        case .completing:
            withAnimation(.easeInOut(duration: 0.3)) {
                ringOpacity = 0.6
                ringScale = 1.0
            }
        }
    }
}

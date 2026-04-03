//
//  PauseButtonView.swift
//  VoiceMiniCog
//
//  Persistent pill-shaped pause button for the avatar assessment canvas.
//

import SwiftUI

struct PauseButtonView: View {
    let action: () -> Void

    @State private var isPressed = false

    // MARK: - Body

    var body: some View {
        Button {
            triggerHaptic()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .medium))
                Text("Pause")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white.opacity(isPressed ? 1.0 : 0.7))
            .frame(width: AssessmentTheme.Sizing.pauseButtonWidth,
                   height: AssessmentTheme.Sizing.pauseButtonHeight)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(PauseButtonStyle(isPressed: $isPressed))
    }

    // MARK: - Haptic

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - PauseButtonStyle

private struct PauseButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressed
                }
            }
    }
}

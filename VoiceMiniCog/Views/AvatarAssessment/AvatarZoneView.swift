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
    var isConnecting: Bool = false
    var errorMessage: String? = nil
    let width: CGFloat
    let height: CGFloat
    var onRetry: (() -> Void)? = nil
    var onContinueWithoutAvatar: (() -> Void)? = nil

    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 1.0
    @State private var connectingElapsed: TimeInterval = 0
    private let connectionTimeout: TimeInterval = 15

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

            // 2. Tavus CVI video feed / connecting state / error recovery
            if let url = conversationURL {
                TavusCVIView(conversationURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(16)
                    .opacity(layoutManager.avatarOpacity)
                    .animation(.easeInOut(duration: 0.3), value: layoutManager.avatarOpacity)
            } else if isConnecting && connectingElapsed < connectionTimeout {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Connecting avatar...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .onAppear { connectingElapsed = 0 }
                .task(id: isConnecting) {
                    while !Task.isCancelled && isConnecting {
                        try? await Task.sleep(for: .seconds(1))
                        connectingElapsed += 1
                    }
                }
            } else if let error = errorMessage {
                avatarRecoveryView(message: error)
            } else if isConnecting && connectingElapsed >= connectionTimeout {
                avatarRecoveryView(message: "Avatar is taking longer than expected.")
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

    // MARK: - Recovery UI

    private func avatarRecoveryView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let onRetry {
                Button {
                    connectingElapsed = 0
                    onRetry()
                } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if let onContinue = onContinueWithoutAvatar {
                Button {
                    onContinue()
                } label: {
                    Text("Continue without avatar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
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

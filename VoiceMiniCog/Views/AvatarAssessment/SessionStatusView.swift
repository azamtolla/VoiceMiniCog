//
//  SessionStatusView.swift
//  VoiceMiniCog
//
//  Light-background status panel that replaces the dark avatar zone
//  during clock drawing. Shows Speaking/Listening status with animated
//  waveform, clock instruction, Done Drawing button, and End Session.
//

import SwiftUI

struct SessionStatusView: View {
    let layoutManager: AvatarLayoutManager
    let onDoneDrawing: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        ZStack {
            // Light background matching content zone
            Color(hex: "#F2F4F7")
                .ignoresSafeArea()

            VStack(spacing: 20) {

                Spacer().frame(maxHeight: 60)

                // MARK: Status Indicator (Speaking / Listening)
                HStack(spacing: 10) {
                    WaveformBars(
                        isActive: true,
                        color: layoutManager.avatarBehavior == .speaking
                            ? Color(hex: "#34C759")
                            : AssessmentTheme.Phase.welcome
                    )

                    Text(statusText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AssessmentTheme.Content.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.7))
                .cornerRadius(16)

                Spacer().frame(height: 8)

                // MARK: Clock Instruction
                Text("Draw a clock. Include all 12 numbers.\nSet the hands to 11:10.")
                    .font(.system(size: 17, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AssessmentTheme.Content.textPrimary)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 4)

                // MARK: Done Drawing Button (Green)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDoneDrawing()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Done Drawing")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 260)
                    .frame(height: 52)
                    .background(Color(hex: "#34C759"))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // MARK: End Session Button (Red)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEndSession()
                } label: {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .frame(height: 52)
                        .background(Color(hex: "#DC2626"))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private var statusText: String {
        switch layoutManager.avatarBehavior {
        case .speaking, .narrating: return "Speaking..."
        case .listening:            return "Listening..."
        case .waiting:              return "Waiting..."
        case .idle:                 return "Ready"
        case .acknowledging:        return "Got it..."
        case .completing:           return "Finishing..."
        }
    }
}

// MARK: - Animated Waveform Bars

struct WaveformBars: View {
    let isActive: Bool
    var color: Color = .blue

    @State private var animating = false

    private let barCount = 7
    private let baseHeights: [CGFloat] = [8, 16, 24, 16, 8, 16, 24]
    private let activeHeights: [CGFloat] = [10, 20, 28, 20, 10, 20, 28]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: animating ? activeHeights[i] : 4)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.07)
                            : .default,
                        value: animating
                    )
            }
        }
        .onAppear { animating = isActive }
        .onChange(of: isActive) { _, active in
            animating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animating = active
            }
        }
    }
}

#Preview {
    SessionStatusView(
        layoutManager: AvatarLayoutManager(),
        onDoneDrawing: {},
        onEndSession: {}
    )
}

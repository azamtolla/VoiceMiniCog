//
//  ClockDrawingControlsView.swift
//  VoiceMiniCog
//
//  Controls overlay for the clock drawing phase — status chip,
//  instruction text, and action buttons. Rendered below the circular
//  live avatar video in AvatarZoneView's clock drawing mode.
//  Does NOT contain a TavusCVIView.
//
//  MARK: CLINICAL-UI — Clock drawing is a validated Qmci subtest (15 pts).
//

import SwiftUI

// MARK: - ClockDrawingControlsView

struct ClockDrawingControlsView: View {

    let layoutManager: AvatarLayoutManager
    let onDoneDrawing: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status chip
            statusChip
                .padding(.bottom, 24)

            // Instruction text
            Text(AssessmentTheme.PromptCopy.clockDrawingInstruction)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDoneDrawing()
                } label: {
                    Label("Done Drawing", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AssessmentTheme.ClockControls.doneButtonColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onEndSession()
                } label: {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AssessmentTheme.ClockControls.endSessionColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Status Chip

    private var statusChip: some View {
        HStack(spacing: 6) {
            MiniWaveform(isActive: layoutManager.avatarBehavior == .speaking)

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AssessmentTheme.ClockControls.statusChipText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(AssessmentTheme.ClockControls.statusChipBackground))
    }

    private var statusText: String {
        switch layoutManager.avatarBehavior {
        case .speaking, .narrating: return "Speaking..."
        case .listening:            return "Listening..."
        default:                    return "Waiting..."
        }
    }
}

// MARK: - Mini Waveform

private struct MiniWaveform: View {
    let isActive: Bool
    private let barCount = 5
    @State private var heights: [CGFloat] = [4, 4, 4, 4, 4]
    private let targetHeights: [CGFloat] = [6, 10, 8, 12, 7]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(AssessmentTheme.ClockControls.statusChipText.opacity(0.6))
                    .frame(width: 2, height: heights[index])
            }
        }
        .frame(height: 14)
        .onAppear { animate() }
        .onChange(of: isActive) { _, active in
            if active { animate() } else { resetBars() }
        }
    }

    private func animate() {
        for i in 0..<barCount {
            withAnimation(
                .easeInOut(duration: 0.5 + Double(i % 3) * 0.12)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.07)
            ) { heights[i] = targetHeights[i] }
        }
    }

    private func resetBars() {
        withAnimation(.easeOut(duration: 0.3)) {
            heights = Array(repeating: 4, count: barCount)
        }
    }
}

// MARK: - Preview

#Preview("Clock Drawing Controls") {
    VStack {
        Circle()
            .fill(Color.gray.opacity(0.15))
            .overlay(Image(systemName: "person.fill").font(.system(size: 60)).foregroundStyle(.gray.opacity(0.4)))
            .frame(width: 180, height: 180)
            .padding(.top, 60)

        ClockDrawingControlsView(
            layoutManager: AvatarLayoutManager(),
            onDoneDrawing: {},
            onEndSession: {}
        )
    }
    .frame(width: 350, height: 900)
    .background(Color.white)
}

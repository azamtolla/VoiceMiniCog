//
//  AvatarVideoOverlays.swift
//  VoiceMiniCog
//
//  SwiftUI overlays for the Daily VideoTrack:
//    - Clock countdown ring (clock drawing phase)
//    - Live transcript strip at the bottom
//    - Score badge that fades in after each subtest completes
//    - Live waveform / listening indicator when the patient speaks
//
//  Usage (host):
//      ZStack {
//        DailyVideoView(track: manager.remoteVideoTrack)
//        AvatarVideoOverlays(
//          patientIsSpeaking: manager.patientIsSpeaking,
//          replicaIsSpeaking: manager.replicaIsSpeaking,
//          clockCountdown: clockState,
//          transcriptTail: transcriptBuffer.tail(max: 2),
//          latestSubtestResult: latestSubtestResult
//        )
//      }
//

import SwiftUI

public struct AvatarVideoOverlays: View {

    public let patientIsSpeaking: Bool
    public let replicaIsSpeaking: Bool

    /// Optional clock-drawing countdown. Pass nil when not in clock phase.
    public let clockCountdown: ClockCountdown?

    /// Last 1–3 transcript lines to show as a live strip. Pass empty to hide.
    public let transcriptTail: [String]

    /// Optional badge describing the most recently completed subtest.
    public let latestSubtestResult: SubtestResult?

    public init(
        patientIsSpeaking: Bool,
        replicaIsSpeaking: Bool,
        clockCountdown: ClockCountdown? = nil,
        transcriptTail: [String] = [],
        latestSubtestResult: SubtestResult? = nil
    ) {
        self.patientIsSpeaking = patientIsSpeaking
        self.replicaIsSpeaking = replicaIsSpeaking
        self.clockCountdown = clockCountdown
        self.transcriptTail = transcriptTail
        self.latestSubtestResult = latestSubtestResult
    }

    public var body: some View {
        ZStack {
            // Clock ring (top-right)
            if let c = clockCountdown {
                VStack {
                    HStack {
                        Spacer()
                        ClockCountdownRing(countdown: c)
                            .frame(width: 96, height: 96)
                            .padding(.top, 28)
                            .padding(.trailing, 28)
                    }
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale))
            }

            // Score badge (top-left)
            if let result = latestSubtestResult {
                VStack {
                    HStack {
                        ScoreBadge(result: result)
                            .padding(.top, 28)
                            .padding(.leading, 28)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Live waveform (bottom-center)
            VStack {
                Spacer()
                LiveWaveformIndicator(
                    active: patientIsSpeaking,
                    color: patientIsSpeaking ? .green : .gray
                )
                .frame(height: 40)
                .padding(.horizontal, 140)
                .padding(.bottom, 24)
                .opacity(patientIsSpeaking ? 1 : 0.2)
                .animation(.easeInOut(duration: 0.25), value: patientIsSpeaking)
            }

            // Transcript strip (bottom, above waveform)
            if !transcriptTail.isEmpty {
                VStack {
                    Spacer()
                    TranscriptStrip(lines: transcriptTail)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 80)
                }
            }
        }
        .allowsHitTesting(false)    // overlays are decorative — don't block video tap-through
        .accessibilityHidden(true)  // avatar video layer handles its own a11y label
    }
}

// MARK: - ClockCountdownRing

public struct ClockCountdown: Equatable {
    public let totalSeconds: Double
    public let remaining: Double

    public init(totalSeconds: Double, remaining: Double) {
        self.totalSeconds = totalSeconds
        self.remaining = max(0, remaining)
    }

    public var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return remaining / totalSeconds
    }
}

public struct ClockCountdownRing: View {
    public let countdown: ClockCountdown

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(countdown.fraction))
                .stroke(
                    countdown.fraction > 0.33 ? Color.cyan : Color.orange,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: countdown.fraction)
            Text("\(Int(countdown.remaining))")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .accessibilityLabel("\(Int(countdown.remaining)) seconds remaining")
    }
}

// MARK: - ScoreBadge

public struct SubtestResult: Equatable {
    public let phaseName: String
    public let scoreLabel: String
    public let color: Color

    public init(phaseName: String, scoreLabel: String, color: Color) {
        self.phaseName = phaseName
        self.scoreLabel = scoreLabel
        self.color = color
    }
}

public struct ScoreBadge: View {
    public let result: SubtestResult

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(result.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.phaseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(result.scoreLabel)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.55))
        )
    }
}

// MARK: - LiveWaveformIndicator

public struct LiveWaveformIndicator: View {
    public let active: Bool
    public let color: Color

    @State private var animated: Bool = false

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 6, height: barHeight(for: i))
                    .animation(
                        active
                            ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.06)
                            : .default,
                        value: animated
                    )
            }
        }
        .onAppear { animated = active }
        .onChange(of: active) { _, new in animated = new }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = active ? 26 : 10
        let jitter: CGFloat = active ? CGFloat([10, 20, 14, 28, 16, 22, 12][index % 7]) : 0
        return base + (animated ? jitter : 0) * 0.6
    }
}

// MARK: - TranscriptStrip

public struct TranscriptStrip: View {
    public let lines: [String]

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.55))
                    )
            }
        }
    }
}

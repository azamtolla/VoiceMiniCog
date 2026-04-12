//
//  AvatarZoneView.swift
//  VoiceMiniCog
//
//  Right side of the avatar assessment canvas — premium clinical avatar zone.
//  Three-layer architecture:
//    1. Background layer — dark gradient (standard phases) or white (clock drawing)
//    2. Video layer — ONE persistent TavusCVIView, phase-aware frame/clip morph
//    3. Chrome layer — phase-specific overlays (standard or clock drawing)
//
//  CRITICAL: TavusCVIView appears in exactly ONE `if let url` branch.
//  That branch is NOT nested inside any phase-conditional. Only the video's
//  .frame(), .clipShape(), and .position() depend on isClockDrawing.
//

import SwiftUI

// MARK: - CLINICAL-UI
// Displays the AI avatar video stream with clinical trust indicators.
// No PHI is rendered here — only the avatar video feed and status overlays.

struct AvatarZoneView: View {
    let layoutManager: AvatarLayoutManager
    let conversationURL: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var onAvatarEvent: ((TavusAvatarEvent) -> Void)?
    let width: CGFloat
    let height: CGFloat

    // MARK: Clock Drawing Callbacks (Task 6 will wire these)

    var onDoneDrawing: (() -> Void)?
    var onEndSession: (() -> Void)?

    // MARK: Animation State

    @State private var breatheScale: CGFloat = 1.0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.4
    @State private var statusDotOpacity: Double = 0.5
    @State private var waveformActive = false
    @State private var accentGlowOpacity: Double = 0.06

    // MARK: - Body

    var body: some View {
        let isClockDrawing = layoutManager.currentPhase == .clockDrawing

        GeometryReader { geo in
            ZStack {
                backgroundLayer(isClockDrawing: isClockDrawing)
                videoLayer(isClockDrawing: isClockDrawing, panelWidth: geo.size.width, panelHeight: geo.size.height)
                if isClockDrawing {
                    clockDrawingChromeLayer(panelHeight: geo.size.height)
                } else {
                    standardChromeLayer(inset: AssessmentTheme.Avatar.videoInset)
                }
            }
        }
        .onChange(of: layoutManager.avatarBehavior) { _, newBehavior in
            updateAnimations(for: newBehavior)
        }
        .onAppear {
            startBreathing()
            updateAnimations(for: layoutManager.avatarBehavior)
        }
    }

    // MARK: - Background Layer

    @ViewBuilder
    private func backgroundLayer(isClockDrawing: Bool) -> some View {
        if isClockDrawing {
            AssessmentTheme.ClockControls.panelBackground
        } else {
            ZStack {
                animatedBackground
                phaseAccentGlow
            }
        }
    }

    // MARK: - Video Layer (CRITICAL — single TavusCVIView at fixed tree position)

    @ViewBuilder
    private func videoLayer(isClockDrawing: Bool, panelWidth: CGFloat, panelHeight: CGFloat) -> some View {
        if isLoading && conversationURL == nil {
            loadingState
        } else if let error = errorMessage, conversationURL == nil {
            errorState(error)
        } else if let url = conversationURL {
            let diameter = AssessmentTheme.ClockControls.avatarDiameter
            let inset = AssessmentTheme.Avatar.videoInset
            let standardW = panelWidth - 2 * inset - 2
            let standardH = panelHeight - 2 * inset - 2
            let videoW = isClockDrawing ? diameter : standardW
            let videoH = isClockDrawing ? diameter : standardH
            let centerY = isClockDrawing ? (diameter / 2) + 60 : panelHeight / 2

            TavusCVIView(conversationURL: url, onAvatarEvent: onAvatarEvent)
                .frame(width: videoW, height: videoH)
                .clipShape(PhaseClipShape(circleProgress: isClockDrawing ? 1.0 : 0.0))
                .overlay(videoRingOverlay(isClockDrawing: isClockDrawing))
                .opacity(layoutManager.avatarOpacity)
                .scaleEffect(isClockDrawing ? 1.0 : breatheScale)
                .position(x: panelWidth / 2, y: centerY)
                .animation(.spring(duration: 0.55, bounce: 0.15), value: isClockDrawing)
        }
    }

    // MARK: - Video Ring Overlay

    @ViewBuilder
    private func videoRingOverlay(isClockDrawing: Bool) -> some View {
        if isClockDrawing {
            PhaseClipShape(circleProgress: 1.0)
                .strokeBorder(AssessmentTheme.ClockControls.avatarRingColor, lineWidth: AssessmentTheme.ClockControls.avatarRingWidth)
        } else {
            RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
                .strokeBorder(layoutManager.accentColor.opacity(ringOpacity), lineWidth: AssessmentTheme.Avatar.accentRingWidth)
                .scaleEffect(ringScale)
        }
    }

    // MARK: - Clock Drawing Chrome Layer

    private func clockDrawingChromeLayer(panelHeight: CGFloat) -> some View {
        let avatarBottom = 60 + AssessmentTheme.ClockControls.avatarDiameter + 20
        return VStack(spacing: 0) {
            Spacer().frame(height: avatarBottom)
            if let done = onDoneDrawing, let end = onEndSession {
                ClockDrawingControlsView(
                    layoutManager: layoutManager,
                    onDoneDrawing: done,
                    onEndSession: end
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Standard Chrome Layer

    private func standardChromeLayer(inset: CGFloat) -> some View {
        ZStack {
            // Glass material backdrop
            RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
                .fill(Color.white.opacity(AssessmentTheme.Avatar.glassOpacity))
                .padding(inset)
                .allowsHitTesting(false)

            // Clinical light effect (top-left highlight)
            RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
                .fill(LinearGradient(colors: [Color.white.opacity(0.03), Color.clear], startPoint: .topLeading, endPoint: .center))
                .padding(inset)
                .allowsHitTesting(false)

            // Status dot, badge, waveform overlays
            overlays(inset: inset)
        }
    }

    // MARK: - Animated Background

    private var animatedBackground: some View {
        RadialGradient(
            colors: [AssessmentTheme.Avatar.gradientCenter, AssessmentTheme.Avatar.gradientEdge],
            center: .init(x: 0.5, y: 0.4),
            startRadius: 0,
            endRadius: max(width, height) * 0.8
        )
    }

    // MARK: - Phase Accent Glow

    private var phaseAccentGlow: some View {
        RadialGradient(
            colors: [
                layoutManager.accentColor.opacity(accentGlowOpacity),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: max(width, height) * 0.5
        )
        .animation(.easeInOut(duration: 0.8), value: layoutManager.accentColor)
        .animation(.easeInOut(duration: 0.6), value: accentGlowOpacity)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.5)
            Text("Connecting to Avatar...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Error State

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Avatar Unavailable")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Overlays

    private func overlays(inset: CGFloat) -> some View {
        ZStack {
            // Status dot (top-right)
            VStack {
                HStack {
                    Spacer()
                    statusDot
                        .padding(.top, inset + 14)
                        .padding(.trailing, inset + 14)
                }
                Spacer()
            }

            // Bottom overlays
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    // Mercy Clinical badge (bottom-left)
                    clinicalBadge
                        .padding(.leading, inset + 12)

                    Spacer()

                    // Audio waveform (bottom-center -> right area)
                }
                .padding(.bottom, inset + 14)

                // Audio waveform centered at bottom
                if waveformActive {
                    audioWaveform
                        .padding(.bottom, inset + 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(
                width: AssessmentTheme.Avatar.statusDotSize,
                height: AssessmentTheme.Avatar.statusDotSize
            )
            .shadow(color: statusDotColor.opacity(0.5), radius: 6)
            .opacity(statusDotOpacity)
    }

    private var statusDotColor: Color {
        switch layoutManager.avatarBehavior {
        case .speaking, .narrating:
            return layoutManager.accentColor
        case .listening:
            return Color(hex: "#22C55E")
        default:
            return Color(hex: "#6B7280")
        }
    }

    // MARK: - Clinical Badge

    private var clinicalBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "staroflife.fill")
                .font(.system(size: 10))
                .foregroundColor(layoutManager.accentColor.opacity(0.8))

            Text("Mercy Clinical Team")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(AssessmentTheme.Avatar.badgeOpacity))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Audio Waveform

    private var audioWaveform: some View {
        HStack(spacing: AssessmentTheme.Avatar.waveBarWidth) {
            ForEach(0..<AssessmentTheme.Avatar.waveBarCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    accentColor: layoutManager.accentColor,
                    isActive: waveformActive
                )
            }
        }
        .frame(height: 20)
    }

    // MARK: - Animation Control

    private func startBreathing() {
        withAnimation(
            .easeInOut(duration: AssessmentTheme.Avatar.breatheDuration)
            .repeatForever(autoreverses: true)
        ) {
            breatheScale = AssessmentTheme.Avatar.breatheScale
        }
    }

    private func updateAnimations(for behavior: AvatarBehavior) {
        switch behavior {
        case .speaking, .narrating:
            withAnimation(.easeInOut(duration: 0.4)) {
                ringOpacity = 0.6
                accentGlowOpacity = 0.1
                statusDotOpacity = 1.0
                waveformActive = true
            }
            withAnimation(
                .easeInOut(duration: AssessmentTheme.Anim.ringPulseDuration)
                .repeatForever(autoreverses: true)
            ) {
                ringScale = 1.02
            }

        case .listening:
            withAnimation(.easeInOut(duration: 0.4)) {
                ringOpacity = 0.5
                ringScale = 1.0
                accentGlowOpacity = 0.08
                statusDotOpacity = 1.0
                waveformActive = false
            }
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                ringScale = 1.03
            }

        case .idle:
            withAnimation(.easeInOut(duration: 0.6)) {
                ringOpacity = 0.25
                ringScale = 1.0
                accentGlowOpacity = 0.06
                statusDotOpacity = 0.5
                waveformActive = false
            }

        case .acknowledging:
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                ringScale = 1.04
                ringOpacity = 0.7
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    ringScale = 1.0
                    ringOpacity = 0.3
                }
            }

        case .waiting:
            withAnimation(.easeInOut(duration: 0.5)) {
                ringOpacity = 0.0
                accentGlowOpacity = 0.02
                statusDotOpacity = 0.3
                waveformActive = false
            }

        case .completing:
            withAnimation(.easeInOut(duration: 0.4)) {
                ringOpacity = 0.4
                ringScale = 1.0
                accentGlowOpacity = 0.06
                statusDotOpacity = 0.6
                waveformActive = false
            }
        }
    }
}

// MARK: - Waveform Bar

private struct WaveformBar: View {
    let index: Int
    let accentColor: Color
    let isActive: Bool

    @State private var barHeight: CGFloat = 4

    private var targetHeight: CGFloat {
        // Staggered heights for visual interest
        let heights: [CGFloat] = [6, 12, 8, 16, 10, 14, 7]
        return heights[index % heights.count]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(accentColor.opacity(0.5 + Double(index % 3) * 0.1))
            .frame(width: AssessmentTheme.Avatar.waveBarWidth, height: barHeight)
            .onAppear {
                guard isActive else { return }
                animate()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    animate()
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        barHeight = 4
                    }
                }
            }
    }

    private func animate() {
        let delay = Double(index) * 0.08
        withAnimation(
            .easeInOut(duration: 0.6 + Double(index % 3) * 0.15)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            barHeight = targetHeight
        }
    }
}

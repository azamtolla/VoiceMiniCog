//
//  AvatarZoneView.swift
//  VoiceMiniCog
//
//  Right side of the avatar assessment canvas — dark radial gradient with
//  rectangular video for standard phases, or light surface with circular
//  avatar crop and controls panel during clock drawing.
//
//  Clock drawing uses a light panel (#F2F4F6), circular video clip, and
//  panel-only instructions / actions; other phases use the dark radial chrome.
//

import SwiftUI

// MARK: - CLINICAL-UI
// Displays the AI avatar video stream and behavioral state indicator.
// No PHI is rendered here — only the avatar video feed and state label.

struct AvatarZoneView: View {
    let layoutManager: AvatarLayoutManager
    let conversationURL: String?
    let dailyCallManager: DailyCallManager
    var isConnecting: Bool = false
    var errorMessage: String? = nil
    let width: CGFloat
    let height: CGFloat
    var onRetry: (() -> Void)? = nil
    var onContinueWithoutAvatar: (() -> Void)? = nil
    var onDoneDrawing: (() -> Void)? = nil
    var onEndSession: (() -> Void)? = nil

    // Ring / glow animation flag. The prior implementation relied on stacked
    // `withAnimation(.repeatForever)` calls which could not be cancelled —
    // each new state change layered a new animation on top of the old one,
    // creating a visible "fight" between the outgoing and incoming ring.
    // The current implementation drives the breathing directly from a
    // TimelineView (see `breathingValues`), so the ring reads the latest
    // behavior every frame and there is no accumulated animation to cancel.
    @State private var isAnimatingRing: Bool = false
    @State private var ackPulseTrigger: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var connectingElapsed: TimeInterval = 0
    private let connectionTimeout: TimeInterval = 15

    /// Clock panel: hide the connecting / Waiting chip once Daily has joined (or session already live).
    @State private var clockPanelFeedReady = false

    /// Mid-session connection lost — set when `.tavusConnectionLost` fires.
    @State private var isConnectionLost = false

    private var isClockDrawing: Bool {
        layoutManager.currentPhase == .clockDrawing
    }

    // MARK: - Body

    var body: some View {
        // Clock-drawing circular avatar: size the circle to fill most of
        // the pane width so the entire face shows, while leaving room
        // below for the instructions + Done Drawing / End Session
        // buttons (~340pt of controls). Cap absolutely so very wide
        // panes don't blow it up past what looks tasteful.
        let clockControlsReservedHeight: CGFloat = 360
        let availableForCircle = max(100, height - clockControlsReservedHeight - 40)
        let circleDiam = min(width * 0.85, min(availableForCircle, 280.0))

        ZStack {
            // 1. No dedicated frame — the avatar floats on the shared
            //    canvas background (AssessmentTheme.canvasBase). Clock
            //    drawing used to have its own light panel here; dropped
            //    so both panes stay the same warm neutral everywhere.

            // 1b. Ambient bloom — a soft radial halo that expands outward
            //     from BEHIND the avatar, not a ring around it. Scales
            //     1.0 → 1.08 on speaking, collapses to a small steady glow
            //     on listening, vanishes on idle. Driven by TimelineView so
            //     the behavior reads every frame without `.repeatForever`
            //     accumulation.
            if !isClockDrawing {
                ambientBloom
                    .allowsHitTesting(false)
            }

            // 2. Video / placeholders — DailyVideoView renders the native Daily video track.
            //    Clock drawing: small circle at top, no colored ring.
            //    Standard: full-bleed rectangle with rounded corners.
            //    Native VideoView stays full-size; SwiftUI .mask() crops the visible region.
            Group {
                if conversationURL != nil {
                    if isClockDrawing {
                        // Clock drawing: a dedicated square frame the size
                        // of the target circle, clipped to Circle() so the
                        // video's .fill scaling centers the face inside
                        // the square — not inside the full pane height,
                        // which was clipping the face off. Anchored near
                        // the top of the pane with room for controls below.
                        VStack(spacing: 0) {
                            DailyVideoView(track: dailyCallManager.remoteVideoTrack)
                                .frame(width: circleDiam, height: circleDiam)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1.5)
                                )
                                .padding(.top, 24)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .opacity(layoutManager.avatarOpacity)
                    } else {
                        // Standard phases: full-pane video with a soft
                        // rounded-rect mask. Ambient bloom behind conveys
                        // the speaking / listening state.
                        DailyVideoView(track: dailyCallManager.remoteVideoTrack)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(layoutManager.avatarOpacity)
                            .mask(alignment: .center) {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .padding(16)
                            }
                    }
                } else if isConnecting && connectingElapsed < connectionTimeout {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(isClockDrawing ? .gray : .white)
                            .scaleEffect(1.5)
                        Text("Connecting avatar...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isClockDrawing ? Color(hex: "#374151") : .white.opacity(0.7))
                    }
                    .onAppear { connectingElapsed = 0 }
                    .task(id: isConnecting) {
                        while !Task.isCancelled && isConnecting {
                            try? await Task.sleep(for: .seconds(1))
                            connectingElapsed += 1
                        }
                    }
                } else if let error = errorMessage {
                    avatarRecoveryView(message: error, lightChrome: isClockDrawing)
                } else if isConnecting && connectingElapsed >= connectionTimeout {
                    avatarRecoveryView(message: "Avatar is taking longer than expected.", lightChrome: isClockDrawing)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: layoutManager.avatarOpacity)

            // 3. No accent ring — the ambient bloom (layer 1b) carries the
            //    state signalling. A hard-edged rectangle around the video
            //    would fight the "one continuous canvas" feel.

            // 4. Controls panel — clock drawing mode
            if isClockDrawing {
                clockDrawingControls(circleDiam: circleDiam)
                    .transition(.opacity)
            }

            // 5. State label — standard mode
            if !isClockDrawing {
                VStack {
                    Spacer()
                    // Thinking dots appear when the avatar is in .acknowledging
                    // ("Got it...") state — a gentle signal that the system
                    // received the patient's answer and is transitioning.
                    ThinkingDots(
                        color: layoutManager.accentColor,
                        isActive: layoutManager.avatarBehavior == .acknowledging
                    )
                    .frame(height: 16)
                    .padding(.bottom, 6)

                    avatarStateLabel
                        .padding(.bottom, 20)
                }
            }

            // 6. Mid-session connection lost overlay
            if isConnectionLost {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(isClockDrawing ? Color(hex: "#6B7280") : Color.white.opacity(0.6))
                    Text("Avatar connection lost")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isClockDrawing ? Color(hex: "#374151") : Color.white.opacity(0.7))
                    Text("The assessment can continue without the avatar.")
                        .font(.system(size: 13))
                        .foregroundStyle(isClockDrawing ? Color(hex: "#6B7280") : Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background((isClockDrawing ? Color.white : Color.black).opacity(0.85))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: isConnectionLost)
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.15), value: layoutManager.currentPhase)
        .onChange(of: layoutManager.avatarBehavior) { _, newBehavior in
            // Fire a one-shot pulse for .acknowledging so the ring "kicks"
            // once — all other states are driven by the TimelineView and
            // settle automatically on the latest behavior.
            if newBehavior == .acknowledging {
                ackPulseTrigger &+= 1
            }
        }
        .onAppear {
            refreshClockPanelFeedReady()
        }
        .onChange(of: layoutManager.currentPhase) { _, _ in
            refreshClockPanelFeedReady()
        }
        .onChange(of: isConnecting) { _, _ in
            refreshClockPanelFeedReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tavusDailyRoomJoined)) { _ in
            // Fix #6: set unconditionally — Daily joins at session start, usually
            // before clock drawing. The old guard on .clockDrawing missed the
            // notification in the common flow. refreshClockPanelFeedReady handles
            // resetting when leaving clock drawing.
            clockPanelFeedReady = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tavusConnectionLost)) { _ in
            isConnectionLost = true
            // Fix #8: mute mic so patient doesn't speak into dead channel
            avatarSetMicMuted(true)
        }
        // Fix #7: reset connection-lost overlay when a new conversation URL arrives
        .onChange(of: conversationURL) { oldURL, newURL in
            if oldURL == nil, newURL != nil {
                isConnectionLost = false
            }
            refreshClockPanelFeedReady()
        }
    }

    /// True once Daily has reported joined, or the session already has a live URL when entering clock.
    private func refreshClockPanelFeedReady() {
        guard isClockDrawing else {
            clockPanelFeedReady = false
            return
        }
        if conversationURL != nil, !isConnecting {
            clockPanelFeedReady = true
        }
    }

    // MARK: - Clock Drawing Controls

    @ViewBuilder
    private func clockDrawingControls(circleDiam: CGFloat) -> some View {
        VStack(spacing: 16) {
            // Space for the circular avatar above
            // Reserve room for: 24pt top padding + circleDiam + small buffer.
            // Tracks the new circle sizing above so the controls panel
            // sits directly below the circular avatar.
            Spacer().frame(height: 24 + circleDiam + (clockPanelFeedReady ? 16 : 8))

            // Connecting / Waiting — hidden once the feed is considered live (Daily joined or URL ready).
            if !clockPanelFeedReady {
                HStack(spacing: 10) {
                    WaveformBars(
                        // Fix #13: only animate when avatar is actually speaking
                        isActive: layoutManager.avatarBehavior == .speaking || layoutManager.avatarBehavior == .narrating,
                        color: layoutManager.avatarBehavior == .speaking
                            ? Color(hex: "#34C759")
                            : AssessmentTheme.Phase.welcome
                    )
                    Text(isConnecting ? "Connecting..." : clockStatusText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "#1F2937"))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(hex: "#E5E7EB"))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            }

            Spacer()

            // Clock instruction (panel only)
            Text(LeftPaneSpeechCopy.clockDrawingAvatarPanelInstruction)
                .font(.system(size: 17, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(hex: "#111827"))
                .padding(.horizontal, 24)

            Spacer().frame(height: 4)

            // Done Drawing
            if let onDoneDrawing {
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
            }

            // End Session
            if let onEndSession {
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
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Clock Status Text

    private var clockStatusText: String {
        switch layoutManager.avatarBehavior {
        case .speaking, .narrating: return "Speaking..."
        case .listening:            return "Listening..."
        case .waiting:              return "Waiting..."
        case .idle:                 return "Ready"
        case .acknowledging:        return "Got it..."
        case .completing:           return "Finishing..."
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

    private func avatarRecoveryView(message: String, lightChrome: Bool) -> some View {
        let primaryText = lightChrome ? Color(hex: "#374151") : Color.white.opacity(0.7)
        let secondaryText = lightChrome ? Color(hex: "#6B7280") : Color.white.opacity(0.5)
        let buttonBg = lightChrome ? Color(hex: "#E5E7EB") : Color.white.opacity(0.15)
        let buttonFg = lightChrome ? Color(hex: "#111827") : Color.white

        return VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let onRetry {
                Button {
                    connectingElapsed = 0
                    onRetry()
                } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(buttonFg)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(buttonBg)
                        .clipShape(Capsule())
                }
            }

            if let onContinue = onContinueWithoutAvatar {
                Button {
                    onContinue()
                } label: {
                    Text("Continue without avatar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(secondaryText)
                }
            }
        }
    }

    // MARK: - Ambient bloom (TimelineView-driven)

    /// Soft radial halo that expands outward from BEHIND the avatar.
    /// Speaking / narrating: scale 1.0 → 1.08, opacity 0.12 → 0.0 (inner to outer),
    /// breathing at the avatarPulse period.
    /// Listening: collapsed steady glow, same color, smaller radius.
    /// Idle / waiting: no glow at all.
    /// Acknowledging: brief brighter flash, settles back.
    ///
    /// Implemented with TimelineView so the current behavior is read every
    /// frame — no stacked `.repeatForever` animations to cancel when the
    /// state changes (prior ring-fight bug).
    @ViewBuilder
    private var ambientBloom: some View {
        let accent = layoutManager.accentColor
        if reduceMotion {
            staticBloom(accent: accent, for: layoutManager.avatarBehavior)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let period = AssessmentTheme.Motion.avatarPulseDuration
                let breath = (sin(t * 2.0 * .pi / period) + 1.0) / 2.0   // 0...1
                let v = bloomValues(for: layoutManager.avatarBehavior, breath: breath)
                RadialGradient(
                    colors: [accent.opacity(v.centerAlpha), accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(width, height) * v.radiusRatio
                )
                .scaleEffect(v.scale)
                .blur(radius: 18)
                .opacity(v.overallOpacity)
            }
        }
    }

    private struct BloomFrame {
        let centerAlpha: Double
        let radiusRatio: Double
        let scale: CGFloat
        let overallOpacity: Double
    }

    private func bloomValues(for b: AvatarBehavior, breath: Double) -> BloomFrame {
        switch b {
        case .speaking, .narrating:
            // Expands outward — scale 1.0 → 1.08, opacity 0.12 → (almost) 0
            return BloomFrame(
                centerAlpha: 0.12 - 0.08 * breath,
                radiusRatio: 0.55,
                scale: 1.0 + 0.08 * CGFloat(breath),
                overallOpacity: 1.0
            )
        case .listening:
            // Steady, warm, attentive — no pulse.
            return BloomFrame(
                centerAlpha: 0.16,
                radiusRatio: 0.40,
                scale: 1.0,
                overallOpacity: 1.0
            )
        case .acknowledging:
            return BloomFrame(
                centerAlpha: 0.22,
                radiusRatio: 0.50,
                scale: 1.05,
                overallOpacity: 1.0
            )
        case .idle, .waiting:
            return BloomFrame(centerAlpha: 0, radiusRatio: 0.3, scale: 1.0, overallOpacity: 0)
        case .completing:
            return BloomFrame(
                centerAlpha: 0.14,
                radiusRatio: 0.45,
                scale: 1.02,
                overallOpacity: 1.0
            )
        }
    }

    @ViewBuilder
    private func staticBloom(accent: Color, for b: AvatarBehavior) -> some View {
        let v = bloomValues(for: b, breath: 0.5)
        RadialGradient(
            colors: [accent.opacity(v.centerAlpha), accent.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: min(width, height) * v.radiusRatio
        )
        .scaleEffect(v.scale)
        .blur(radius: 18)
        .opacity(v.overallOpacity)
        .animation(.easeInOut(duration: 0.3), value: b)
    }
}

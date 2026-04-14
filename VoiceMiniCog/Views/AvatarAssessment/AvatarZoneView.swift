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
    /// Home warm path: keep WKWebView but do not join Daily until assessment starts (see `TavusCVIView`).
    var deferDailyRoomJoin: Bool = false
    var isConnecting: Bool = false
    var errorMessage: String? = nil
    let width: CGFloat
    let height: CGFloat
    var onRetry: (() -> Void)? = nil
    var onContinueWithoutAvatar: (() -> Void)? = nil
    var onDoneDrawing: (() -> Void)? = nil
    var onEndSession: (() -> Void)? = nil

    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 1.0
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
        let circleDiam = min(width * 0.65, 160.0)

        ZStack {
            // 1. Background — dark gradient (standard) or light surface (clock only)
            if isClockDrawing {
                Color(hex: "#F2F4F6")
            } else {
                RadialGradient(
                    colors: [AssessmentTheme.Avatar.gradientCenter, AssessmentTheme.Avatar.gradientEdge],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.7
                )
            }

            // 2. Video / placeholders — ONE TavusCVIView when URL exists; layout + clip change with phase.
            //    Clock drawing: small circle at top, no colored ring.
            //    Standard: full-bleed rectangle with rounded corners.
            //    WKWebView stays full-size so Daily.co never freezes; a SwiftUI
            //    .mask() crops the visible region to circle or rounded rect.
            Group {
                if let url = conversationURL {
                    TavusCVIView(
                        conversationURL: url,
                        deferDailyRoomJoinUntilAssessmentActive: deferDailyRoomJoin
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(layoutManager.avatarOpacity)
                    .mask(alignment: isClockDrawing ? .top : .center) {
                        if isClockDrawing {
                            Circle()
                                .frame(width: circleDiam, height: circleDiam)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .padding(16)
                        }
                    }
                    .overlay(alignment: .top) {
                        if isClockDrawing {
                            Circle()
                                .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1.5)
                                .frame(width: circleDiam, height: circleDiam)
                                .padding(.top, 40)
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

            // 3. Accent ring — standard mode (hidden during clock, registration, fluency, and .waiting)
            if !isClockDrawing
                && layoutManager.currentPhase != .wordRegistration
                && layoutManager.currentPhase != .verbalFluency
                && layoutManager.showAvatarRing {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(layoutManager.accentColor, lineWidth: AssessmentTheme.Sizing.avatarRingWidth)
                    .padding(16)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .animation(.easeInOut(duration: 0.3), value: ringScale)
                    .animation(.easeInOut(duration: 0.3), value: ringOpacity)
            }

            // 4. Controls panel — clock drawing mode
            if isClockDrawing {
                clockDrawingControls(circleDiam: circleDiam)
                    .transition(.opacity)
            }

            // 5. State label — standard mode
            if !isClockDrawing {
                VStack {
                    Spacer()
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
            updateRingAnimation(for: newBehavior)
        }
        .onAppear {
            updateRingAnimation(for: layoutManager.avatarBehavior)
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
            Spacer().frame(height: 40 + circleDiam + (clockPanelFeedReady ? 16 : 8))

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

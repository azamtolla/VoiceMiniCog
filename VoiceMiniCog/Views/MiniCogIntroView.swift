//
//  MiniCogIntroView.swift
//  VoiceMiniCog
//
//  Split-screen layout for iPad.
//  Left: changes between intro overview and active assessment controls.
//  Right: Tavus avatar (persists across states, never reloads).
//

import SwiftUI

struct MiniCogIntroView: View {
    let onStart: () -> Void

    var body: some View {
        QmciModePickerView(onStandard: onStart, onAvatar: onStart)
    }
}

// MARK: - Assessment Mode

private enum AssessmentMode {
    case intro       // Overview + "Begin Assessment"
    case active      // Assessment in progress — avatar is guiding patient
}

/// Split-screen view for iPad.
/// Left panel swaps between intro and active assessment.
/// Right panel is the Tavus avatar — stays put the entire time.
struct QmciModePickerView: View {
    let onStandard: () -> Void
    let onAvatar: () -> Void

    @State private var mode: AssessmentMode = .intro
    @State private var tavusService = TavusService.shared
    @State private var conversationURL: String?
    @State private var isLoadingAvatar = true
    @State private var avatarError: String?
    @State private var showEndConfirmation = false
    @State private var sessionStartTime: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var isMuted = false

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Panel (swaps content)
            Group {
                switch mode {
                case .intro:
                    introPanel
                case .active:
                    activePanel
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: mode)

            // MARK: - Right Panel: Tavus Avatar (persistent)
            avatarPanel
                .frame(maxWidth: .infinity)
        }
        .background(MCDesign.Colors.background)
        .onAppear {
            startAvatar()
        }
        .onDisappear {
            timer?.invalidate()
            Task { await tavusService.endConversation() }
        }
        .alert("End Session?", isPresented: $showEndConfirmation) {
            Button("Continue", role: .cancel) { }
            Button("End & Review Scores", role: .destructive) {
                timer?.invalidate()
                Task { await tavusService.endConversation() }
                onAvatar()
            }
        } message: {
            Text("The avatar session will end. You'll enter scores on the next screen.")
        }
    }

    // MARK: - Intro Panel (before assessment starts)

    private var introPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MCDesign.Spacing.lg) {
                MCIconCircle(
                    icon: "brain.head.profile",
                    color: MCDesign.Colors.primary700,
                    size: MCDesign.Sizing.iconXL
                )

                Text("Brain Health Assessment")
                    .font(MCDesign.Fonts.screenTitle)
                    .foregroundColor(MCDesign.Colors.textPrimary)

                Text("6 cognitive activities, about 5-7 minutes")
                    .font(MCDesign.Fonts.body)
                    .foregroundColor(MCDesign.Colors.textSecondary)

                MCCard {
                    VStack(alignment: .leading, spacing: MCDesign.Spacing.sm) {
                        ForEach(QmciSubtest.allCases, id: \.rawValue) { subtest in
                            HStack(spacing: MCDesign.Spacing.md) {
                                MCIconCircle(
                                    icon: subtest.iconName,
                                    color: MCDesign.Colors.primary500,
                                    size: MCDesign.Sizing.iconSmall
                                )
                                Text(subtest.displayName)
                                    .font(MCDesign.Fonts.bodyMedium)
                                    .foregroundColor(MCDesign.Colors.textPrimary)
                                Spacer()
                                Text("\(subtest.maxScore) pts")
                                    .font(MCDesign.Fonts.smallCaption)
                                    .foregroundColor(MCDesign.Colors.textTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, MCDesign.Spacing.md)
            }
            .padding(.horizontal, MCDesign.Spacing.lg)

            Spacer()

            VStack(spacing: MCDesign.Spacing.md) {
                MCPrimaryButton("Begin Assessment", icon: "play.fill") {
                    withAnimation { mode = .active }
                    startTimer()
                }

                MCSecondaryButton("Standard Mode (No Avatar)", icon: "list.bullet") {
                    Task { await tavusService.endConversation() }
                    onStandard()
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .padding(.bottom, MCDesign.Spacing.xxl)
        }
    }

    // MARK: - Active Panel (assessment in progress)

    private var activePanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: MCDesign.Spacing.lg) {
                // Session timer
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("Session Active")
                        .font(MCDesign.Fonts.bodySemibold)
                        .foregroundColor(MCDesign.Colors.textPrimary)
                    Spacer()
                    Text(timerString)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundColor(MCDesign.Colors.textSecondary)
                }
                .padding(.horizontal, MCDesign.Spacing.md)

                MCCard {
                    VStack(alignment: .leading, spacing: MCDesign.Spacing.md) {
                        Text("The avatar is guiding the patient through the assessment.")
                            .font(MCDesign.Fonts.body)
                            .foregroundColor(MCDesign.Colors.textPrimary)

                        Text("Observe the patient's responses and enter scores when the session ends.")
                            .font(MCDesign.Fonts.caption)
                            .foregroundColor(MCDesign.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, MCDesign.Spacing.md)

                // Subtest checklist
                MCCard {
                    VStack(alignment: .leading, spacing: MCDesign.Spacing.sm) {
                        Text("Assessment Phases")
                            .font(MCDesign.Fonts.bodySemibold)
                            .foregroundColor(MCDesign.Colors.textPrimary)
                            .padding(.bottom, MCDesign.Spacing.xs)

                        ForEach(QmciSubtest.allCases, id: \.rawValue) { subtest in
                            HStack(spacing: MCDesign.Spacing.md) {
                                Image(systemName: "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(MCDesign.Colors.textTertiary)
                                Text(subtest.displayName)
                                    .font(MCDesign.Fonts.body)
                                    .foregroundColor(MCDesign.Colors.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, MCDesign.Spacing.md)
            }
            .padding(.horizontal, MCDesign.Spacing.lg)

            Spacer()

            // Controls
            VStack(spacing: MCDesign.Spacing.md) {
                HStack(spacing: MCDesign.Spacing.md) {
                    // Mute button
                    Button {
                        isMuted.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                            Text(isMuted ? "Unmute" : "Mute")
                        }
                        .font(MCDesign.Fonts.bodySemibold)
                        .foregroundColor(isMuted ? .white : MCDesign.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: MCDesign.Sizing.secondaryButtonHeight)
                        .background(isMuted ? Color.red : MCDesign.Colors.surface)
                        .cornerRadius(MCDesign.Radius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                                .stroke(MCDesign.Colors.border, lineWidth: isMuted ? 0 : 1)
                        )
                    }

                    // Switch to standard
                    Button {
                        timer?.invalidate()
                        Task { await tavusService.endConversation() }
                        onStandard()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet")
                            Text("Classic")
                        }
                        .font(MCDesign.Fonts.bodySemibold)
                        .foregroundColor(MCDesign.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: MCDesign.Sizing.secondaryButtonHeight)
                        .background(MCDesign.Colors.surface)
                        .cornerRadius(MCDesign.Radius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                                .stroke(MCDesign.Colors.border, lineWidth: 1)
                        )
                    }
                }

                MCPrimaryButton("End Session & Enter Scores", icon: "checkmark.circle.fill", color: MCDesign.Colors.error) {
                    showEndConfirmation = true
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
            .padding(.bottom, MCDesign.Spacing.xxl)
        }
    }

    // MARK: - Avatar Panel (right side, never changes)

    private var avatarPanel: some View {
        ZStack {
            Color.black

            if isLoadingAvatar {
                VStack(spacing: MCDesign.Spacing.md) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text("Loading avatar...")
                        .font(MCDesign.Fonts.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if let error = avatarError {
                VStack(spacing: MCDesign.Spacing.md) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Avatar unavailable")
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(.white.opacity(0.6))
                    Text(error)
                        .font(MCDesign.Fonts.smallCaption)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MCDesign.Spacing.lg)
                    Button("Retry") {
                        startAvatar()
                    }
                    .font(MCDesign.Fonts.caption)
                    .foregroundColor(MCDesign.Colors.primary300)
                }
            } else if let url = conversationURL {
                TavusCVIView(conversationURL: url)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MCDesign.Radius.large))
        .padding(.trailing, MCDesign.Spacing.lg)
        .padding(.vertical, MCDesign.Spacing.lg)
    }

    // MARK: - Timer

    private var timerString: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func startTimer() {
        sessionStartTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let start = sessionStartTime {
                elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }
    }

    // MARK: - Avatar Lifecycle

    private func startAvatar() {
        guard tavusService.validateConfiguration() else {
            avatarError = "Tavus API key not configured. Add it in Settings."
            isLoadingAvatar = false
            return
        }

        isLoadingAvatar = true
        avatarError = nil

        Task {
            do {
                let session = try await tavusService.createConversation(
                    conversationName: "MercyCognitive — \(Date().formatted(date: .abbreviated, time: .shortened))"
                )
                await MainActor.run {
                    conversationURL = session.conversation_url
                    isLoadingAvatar = false
                }
            } catch {
                await MainActor.run {
                    avatarError = error.localizedDescription
                    isLoadingAvatar = false
                }
            }
        }
    }
}

#Preview {
    QmciModePickerView(onStandard: {}, onAvatar: {})
        .previewInterfaceOrientation(.landscapeLeft)
}

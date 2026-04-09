//
//  TavusAssessmentView.swift
//  VoiceMiniCog
//
//  Avatar-guided cognitive assessment using Tavus CVI.
//  The Tavus persona (Clinical Neuropsychologist) handles the full
//  assessment flow — QDRS, PHQ-2, Qmci subtests — via voice conversation.
//  The clinician reviews results after the avatar session completes.
//

import SwiftUI

// MARK: - CLINICAL-UI
// This view wraps the Tavus avatar conversation for cognitive screening.
// The avatar guides the patient through the assessment protocol.
// Clinician must review and enter scores manually for CDS exemption (V1).

struct TavusAssessmentView: View {
    @Binding var isActive: Bool
    let assessmentState: AssessmentState
    let onComplete: () -> Void
    let onFallback: () -> Void

    @State private var tavusService = TavusService.shared
    @State private var conversationURL: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEndConfirmation = false
    @State private var isMuted = false
    @State private var sessionStartTime: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let url = conversationURL {
                // Avatar video feed
                TavusCVIView(conversationURL: url)
                    .ignoresSafeArea()

                // Overlay controls
                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
            }
        }
        .onAppear {
            startConversation()
        }
        .onDisappear {
            endConversation()
            timer?.invalidate()
        }
        .alert("End Session?", isPresented: $showEndConfirmation) {
            Button("Continue Assessment", role: .cancel) { }
            Button("End & Review Scores", role: .destructive) {
                endConversation()
                onComplete()
            }
        } message: {
            Text("The avatar session will end. You'll enter scores on the next screen based on what you observed.")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: MCDesign.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("Connecting to Avatar...")
                .font(MCDesign.Fonts.body)
                .foregroundColor(.white)

            Text("Setting up your brain health screening session")
                .font(MCDesign.Fonts.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(MCDesign.Spacing.xl)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: MCDesign.Spacing.lg) {
            MCIconCircle(
                icon: "exclamationmark.triangle.fill",
                color: MCDesign.Colors.warning,
                size: MCDesign.Sizing.iconLarge
            )

            Text("Avatar Unavailable")
                .font(MCDesign.Fonts.sectionTitle)
                .foregroundColor(.white)

            Text(message)
                .font(MCDesign.Fonts.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MCDesign.Spacing.xl)

            VStack(spacing: MCDesign.Spacing.md) {
                MCPrimaryButton("Retry Connection", icon: "arrow.clockwise") {
                    startConversation()
                }

                MCSecondaryButton("Use Standard Assessment", icon: "list.bullet") {
                    onFallback()
                }
            }
            .padding(.horizontal, MCDesign.Spacing.lg)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Session timer
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(timerString)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(MCDesign.Radius.pill)

            Spacer()

            // Close button
            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, MCDesign.Spacing.md)
        .padding(.top, MCDesign.Spacing.sm)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: MCDesign.Spacing.lg) {
            // Mute toggle
            Button {
                isMuted.toggle()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(isMuted ? Color.red.opacity(0.8) : Color.white.opacity(0.2))
                        .clipShape(Circle())
                    Text(isMuted ? "Unmute" : "Mute")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Fallback to standard
            Button {
                endConversation()
                onFallback()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                    Text("Classic")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // End session
            Button {
                showEndConfirmation = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                    Text("End")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.bottom, MCDesign.Spacing.xl)
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

    // MARK: - Conversation Lifecycle

    private func startConversation() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let session = try await tavusService.createConversation(
                    conversationName: "MercyCognitive Assessment — \(Date().formatted(date: .abbreviated, time: .shortened))"
                )

                await MainActor.run {
                    conversationURL = session.conversation_url
                    isLoading = false
                    startTimer()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func endConversation() {
        timer?.invalidate()
        timer = nil
        Task {
            await tavusService.endConversation()
        }
    }
}

#Preview {
    TavusAssessmentView(
        isActive: .constant(true),
        assessmentState: AssessmentState(),
        onComplete: {},
        onFallback: {}
    )
}

//
//  SpeechListenerView.swift
//  VoiceMiniCog
//
//  Reusable speech-to-text listening view.
//  Shows listening indicator, live transcript, and done button.
//  Used by Orientation, Registration, Verbal Fluency, and Delayed Recall subtests.
//

import SwiftUI
import Speech

struct SpeechListenerView: View {
    let prompt: String
    var autoStopAfter: TimeInterval? = nil   // nil = manual stop
    var onTranscript: ((String) -> Void)? = nil  // called on every partial result
    let onDone: (String) -> Void             // called with final transcript

    @StateObject private var speech = SpeechService()
    @State private var hasStarted = false
    @State private var autoStopTimer: Timer?

    var body: some View {
        VStack(spacing: MCDesign.Spacing.lg) {
            // Prompt
            Text(prompt)
                .font(MCDesign.Fonts.sectionTitle)
                .foregroundColor(MCDesign.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MCDesign.Spacing.lg)

            // Listening indicator
            if speech.isListening {
                MCListeningIndicator()

                // Live transcript
                if !speech.transcript.isEmpty {
                    Text(speech.transcript)
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(MCDesign.Colors.textSecondary)
                        .padding(MCDesign.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MCDesign.Colors.surface)
                        .cornerRadius(MCDesign.Radius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                                .stroke(MCDesign.Colors.border, lineWidth: 1)
                        )
                        .padding(.horizontal, MCDesign.Spacing.lg)
                }

                // Auto-stop countdown
                if let remaining = autoStopRemaining {
                    Text("\(remaining)s remaining")
                        .font(MCDesign.Fonts.smallCaption)
                        .foregroundColor(MCDesign.Colors.textTertiary)
                }
            } else if !hasStarted {
                // Not yet started
                MCPrimaryButton("Start Listening", icon: "mic.fill") {
                    startListening()
                }
                .padding(.horizontal, MCDesign.Spacing.xl)
            } else {
                // Stopped — show transcript summary
                if !speech.transcript.isEmpty {
                    VStack(spacing: MCDesign.Spacing.sm) {
                        Text("You said:")
                            .font(MCDesign.Fonts.caption)
                            .foregroundColor(MCDesign.Colors.textTertiary)
                        Text(speech.transcript)
                            .font(MCDesign.Fonts.bodyMedium)
                            .foregroundColor(MCDesign.Colors.textPrimary)
                            .padding(MCDesign.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(MCDesign.Colors.surfaceInset)
                            .cornerRadius(MCDesign.Radius.medium)
                    }
                    .padding(.horizontal, MCDesign.Spacing.lg)
                }
            }

            // Error
            if let error = speech.errorMessage {
                Text(error)
                    .font(MCDesign.Fonts.smallCaption)
                    .foregroundColor(MCDesign.Colors.error)
            }

            // Done / Stop button
            if speech.isListening {
                MCSecondaryButton("Done", icon: "stop.fill") {
                    finishListening()
                }
                .padding(.horizontal, MCDesign.Spacing.xl)
            }
        }
        .onAppear {
            Task {
                _ = await speech.requestAuthorization()
                // Auto-start if authorized
                if speech.isAuthorized {
                    startListening()
                }
            }
        }
        .onDisappear {
            stopAll()
        }
        .onChange(of: speech.transcript) { _, newValue in
            onTranscript?(newValue)
        }
    }

    @State private var autoStopRemaining: Int? = nil

    private func startListening() {
        hasStarted = true
        Task {
            try? await speech.startListening()

            // Set up auto-stop timer if configured
            if let duration = autoStopAfter {
                await MainActor.run {
                    autoStopRemaining = Int(duration)
                    autoStopTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        if let remaining = autoStopRemaining, remaining > 1 {
                            autoStopRemaining = remaining - 1
                        } else {
                            finishListening()
                        }
                    }
                }
            }
        }
    }

    private func finishListening() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        autoStopRemaining = nil
        speech.stopListening()
        onDone(speech.transcript)
    }

    private func stopAll() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        speech.stopListening()
    }
}

// MARK: - Compact variant for inline use

/// Smaller listening widget for embedding inside other views (e.g., orientation questions)
struct CompactSpeechListener: View {
    let onTranscript: (String) -> Void

    @StateObject private var speech = SpeechService()
    @State private var isActive = false

    var body: some View {
        VStack(spacing: MCDesign.Spacing.sm) {
            if isActive {
                HStack(spacing: MCDesign.Spacing.sm) {
                    Circle()
                        .fill(MCDesign.Colors.success)
                        .frame(width: 10, height: 10)

                    Text(speech.transcript.isEmpty ? "Listening..." : speech.transcript)
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(speech.transcript.isEmpty ? MCDesign.Colors.textTertiary : MCDesign.Colors.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: stop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(MCDesign.Colors.error)
                    }
                }
                .padding(MCDesign.Spacing.md)
                .background(MCDesign.Colors.success.opacity(0.08))
                .cornerRadius(MCDesign.Radius.medium)
            } else {
                Button(action: start) {
                    HStack(spacing: MCDesign.Spacing.sm) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                        Text("Tap to listen")
                            .font(MCDesign.Fonts.bodyMedium)
                    }
                    .foregroundColor(MCDesign.Colors.primary500)
                    .padding(MCDesign.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(MCDesign.Colors.primary50)
                    .cornerRadius(MCDesign.Radius.medium)
                }
            }
        }
        .onAppear {
            Task { _ = await speech.requestAuthorization() }
        }
        .onDisappear { speech.stopListening() }
        .onChange(of: speech.transcript) { _, val in onTranscript(val) }
    }

    private func start() {
        isActive = true
        Task { try? await speech.startListening() }
    }

    private func stop() {
        speech.stopListening()
        isActive = false
        onTranscript(speech.transcript)
    }
}

#Preview {
    SpeechListenerView(prompt: "What year is it?") { transcript in
        print("Got: \(transcript)")
    }
}

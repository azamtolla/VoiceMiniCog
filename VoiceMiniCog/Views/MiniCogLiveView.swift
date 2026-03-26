//
//  MiniCogLiveView.swift
//  VoiceMiniCog
//

import SwiftUI

struct MiniCogLiveView: View {
    @Binding var isActive: Bool
    let onRequestFallback: () -> Void

    @State private var assessmentState = AssessmentState()
    @State private var avatarStream = AvatarStreamService()
    @State private var promptTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            AvatarView(blendshapes: avatarStream.blendshapes)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .overlay(alignment: .topLeading) {
                    assistantStateChip
                        .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    if avatarStream.isVoiceOnlyFallback {
                        Text("Voice-only")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(12)
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                if let banner = avatarStream.errorBannerMessage {
                    fallbackBanner(message: banner)
                }

                Text("Current Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MercyColors.gray600)

                Text(assessmentState.currentPrompt.isEmpty ? "Preparing session..." : assessmentState.currentPrompt)
                    .font(.system(size: 17))
                    .foregroundColor(MercyColors.gray800)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(MercyColors.gray200, lineWidth: 1)
                    )
                    .cornerRadius(10)

                Text("Transcript Preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MercyColors.gray600)

                Text(avatarStream.transcriptPreview.isEmpty ? "Waiting for speech..." : avatarStream.transcriptPreview)
                    .font(.system(size: 15))
                    .foregroundColor(MercyColors.gray700)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                    .padding(12)
                    .background(MercyColors.gray50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(MercyColors.gray200, lineWidth: 1)
                    )
                    .cornerRadius(10)

                HStack(spacing: 12) {
                    metricPill(title: "RTT", value: rttString)
                    metricPill(title: "Reconnects", value: "\(avatarStream.metrics.reconnectCount)")
                    metricPill(title: "Dropped", value: "\(avatarStream.metrics.droppedFrameCount)")
                }
            }
            .padding(16)

            Spacer(minLength: 0)
        }
        .background(MercyColors.gray50.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    isActive = false
                }
                .foregroundColor(.red)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Classic View") {
                    onRequestFallback()
                }
            }
        }
        .onAppear {
            if assessmentState.currentPrompt.isEmpty {
                assessmentState.currentPhase = .qmciOrientation
                assessmentState.currentPrompt = assessmentState.getPromptForPhase(.qmciOrientation)
            }
            avatarStream.connect()
            avatarStream.startMicStreaming()
            startPromptSequence()
        }
        .onDisappear {
            promptTask?.cancel()
            avatarStream.stopMicStreaming()
            avatarStream.disconnect()
        }
    }

    private var assistantStateChip: some View {
        let color: Color = switch avatarStream.assistantState {
        case .speaking: MercyColors.mercyBlue
        case .listening: MercyColors.success
        case .thinking: Color(hex: "#7C3AED")
        case .idle: MercyColors.gray500
        }

        let label: String = switch avatarStream.assistantState {
        case .speaking: "Speaking"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .idle: "Idle"
        }

        return Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .cornerRadius(14)
    }

    private var rttString: String {
        guard let rtt = avatarStream.metrics.lastRoundTripMs else { return "--" }
        return "\(Int(rtt))ms"
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MercyColors.gray500)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MercyColors.gray800)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MercyColors.gray200, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func fallbackBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(MercyColors.gray700)
                Button("Switch to classic assessment") {
                    onRequestFallback()
                }
                .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    private func startPromptSequence() {
        promptTask?.cancel()
        promptTask = Task {
            // Reuses existing prompt builders while preserving scoring logic elsewhere.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                assessmentState.currentPhase = .qmciRegistration
                assessmentState.currentPrompt = assessmentState.getWordIntroPrompt()
            }

            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                assessmentState.currentPrompt = assessmentState.getRepeatPrompt()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MiniCogLiveView(isActive: .constant(true), onRequestFallback: {})
    }
}

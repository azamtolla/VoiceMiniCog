//
//  VerbalFluencyView.swift
//  VoiceMiniCog
//
//  Qmci Verbal Fluency subtest — name animals for 60 seconds.
//  Score = unique valid animal names, max 20.
//

import SwiftUI
import Speech

struct VerbalFluencyView: View {
    @Bindable var qmciState: QmciState
    let onComplete: () -> Void

    @State private var timeRemaining = 60
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var liveTranscript = ""
    @State private var foundAnimals: [String] = []
    @State private var speech = SpeechService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Verbal Fluency")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                Spacer()
                // Word count badge
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 12))
                    Text("\(foundAnimals.count)")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(MCDesign.Colors.primary700)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MCDesign.Colors.primary700.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.white)
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 16)

                    if !isRunning {
                        // Pre-start instruction
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(MCDesign.Colors.primary700.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                    .font(.system(size: 34))
                                    .foregroundColor(MCDesign.Colors.primary700)
                            }

                            Text("Name as many animals as you can")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(MCDesign.Colors.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("You have one minute. Say any kind of animal — pets, farm animals, wild animals, sea creatures, insects, anything.")
                                .font(.system(size: 15))
                                .foregroundColor(MCDesign.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button(action: startTest) {
                                Text("Start Timer")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: 240)
                                    .frame(height: 52)
                                    .background(MCDesign.Colors.primary700)
                                    .cornerRadius(14)
                            }
                        }
                    } else {
                        // Active test
                        VStack(spacing: 20) {
                            // Timer (large, clinician-visible)
                            Text("\(timeRemaining)")
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(timeRemaining <= 10 ? MCDesign.Colors.error : MCDesign.Colors.textPrimary)

                            Text("seconds remaining")
                                .font(.system(size: 13))
                                .foregroundColor(MCDesign.Colors.textTertiary)

                            // Listening indicator
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(MCDesign.Colors.success)
                                    .frame(width: 10, height: 10)
                                Text("Listening...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MCDesign.Colors.success)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(MCDesign.Colors.success.opacity(0.1))
                            .cornerRadius(20)

                            // Found animals grid
                            if !foundAnimals.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Animals found:")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(MCDesign.Colors.textSecondary)

                                    FlowLayoutCompat(spacing: 6) {
                                        ForEach(foundAnimals, id: \.self) { animal in
                                            Text(animal.capitalized)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(MCDesign.Colors.primary700)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(MCDesign.Colors.primary700.opacity(0.08))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(12)
                            }

                            // Live transcript
                            if !liveTranscript.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Transcript")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MCDesign.Colors.textTertiary)
                                    Text(liveTranscript)
                                        .font(.system(size: 14))
                                        .foregroundColor(MCDesign.Colors.textSecondary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white)
                                .cornerRadius(10)
                            }

                            // Manual add
                            Button(action: finishEarly) {
                                Text("Stop Early")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(MCDesign.Colors.textSecondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .background(MCDesign.Colors.surfaceInset)
        .onDisappear { stopTest() }
    }

    private func startTest() {
        isRunning = true
        timeRemaining = 60
        foundAnimals = []
        liveTranscript = ""

        // Start speech recognition
        Task {
            _ = await speech.requestAuthorization()
            try? await speech.startListening()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
                // Pull transcript from speech service and score
                liveTranscript = speech.transcript
                updateScoring()
            } else {
                finishTest()
            }
        }
    }

    private func stopTest() {
        timer?.invalidate()
        timer = nil
        speech.stopListening()
    }

    private func finishEarly() {
        finishTest()
    }

    private func finishTest() {
        stopTest()
        liveTranscript = speech.transcript
        updateScoring()
        qmciState.verbalFluencyWords = foundAnimals
        qmciState.verbalFluencyTranscript = liveTranscript
        qmciState.completedSubtests.insert(.verbalFluency)
        onComplete()
    }

    private func updateScoring() {
        foundAnimals = scoreVerbalFluency(transcript: liveTranscript)
    }
}

// Simple flow layout for animal chips
struct FlowLayoutCompat: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        let maxW = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxW && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}

/// Alias for backward compatibility (QDRSView uses FlowLayout)
typealias FlowLayout = FlowLayoutCompat

#Preview {
    VerbalFluencyView(qmciState: QmciState(), onComplete: {})
}

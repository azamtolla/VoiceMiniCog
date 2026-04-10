//
//  LogicalMemoryView.swift
//  VoiceMiniCog
//
//  Qmci Logical Memory subtest — story recall.
//  Phase 1: Avatar reads story (text hidden from patient).
//  Phase 2: Patient retells story, scored against scoring units.
//

import SwiftUI

struct LogicalMemoryView: View {
    @ObservedObject var qmciState: QmciState
    let onComplete: () -> Void

    @State private var phase: StoryPhase = .listen
    @State private var recallTranscript = ""
    @State private var matchedUnits: [String] = []
    @State private var showScoring = false

    enum StoryPhase {
        case listen    // Avatar reads story
        case recall    // Patient retells
        case scored    // Show results
    }

    var story: LogicalMemoryStory {
        qmciState.currentStory
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Story Recall")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textPrimary)
                Spacer()

                if phase == .scored {
                    HStack(spacing: 4) {
                        Text("\(matchedUnits.count * 2)/\(story.maxScore)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MCDesign.Colors.primary700)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.white)
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)

                    switch phase {
                    case .listen:
                        listenPhase
                    case .recall:
                        recallPhase
                    case .scored:
                        scoredPhase
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .background(MCDesign.Colors.surfaceInset)
    }

    // MARK: - Listen Phase

    private var listenPhase: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#6366F1").opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "book.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Color(hex: "#6366F1"))
            }

            Text("Listen Carefully")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(MCDesign.Colors.textPrimary)

            Text("I'm going to read you a short story. Please listen carefully. When I'm done, I'll ask you to tell me everything you remember.")
                .font(.system(size: 16))
                .foregroundColor(MCDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Waveform animation placeholder
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#6366F1").opacity(0.5))
                        .frame(width: 4, height: CGFloat.random(in: 8...28))
                }
            }
            .frame(height: 32)
            .padding(.vertical, 8)

            // Clinician view: story text (for reference only — patient hears audio)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                    Text("Clinician reference (not shown to patient)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(MCDesign.Colors.textTertiary)

                Text(story.text)
                    .font(.system(size: 13))
                    .foregroundColor(MCDesign.Colors.textSecondary)
                    .italic()
            }
            .padding(12)
            .background(MCDesign.Colors.background)
            .cornerRadius(10)

            Button(action: { phase = .recall }) {
                Text("Story Read — Begin Recall")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "#6366F1"))
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Recall Phase

    private var recallPhase: some View {
        SpeechListenerView(
            prompt: "Tell me everything you remember from the story.",
            autoStopAfter: 45,
            onTranscript: { partial in
                recallTranscript = partial
            },
            onDone: { finalTranscript in
                recallTranscript = finalTranscript
                scoreRecall()
            }
        )
    }

    // MARK: - Scored Phase

    private var scoredPhase: some View {
        VStack(spacing: 20) {
            // Score
            Text("\(matchedUnits.count * 2)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(MCDesign.Colors.primary700)
            Text("out of \(story.maxScore) points")
                .font(.system(size: 14))
                .foregroundColor(MCDesign.Colors.textTertiary)

            Text("\(matchedUnits.count) of \(story.scoringUnits.count) details recalled")
                .font(.system(size: 15))
                .foregroundColor(MCDesign.Colors.textSecondary)

            // Detail breakdown
            VStack(alignment: .leading, spacing: 6) {
                Text("Scoring Units")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MCDesign.Colors.textSecondary)

                ForEach(story.scoringUnits, id: \.self) { unit in
                    let matched = matchedUnits.contains(unit)
                    HStack(spacing: 8) {
                        Image(systemName: matched ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(matched ? MCDesign.Colors.success : MCDesign.Colors.border)
                        Text(unit)
                            .font(.system(size: 14))
                            .foregroundColor(matched ? MCDesign.Colors.textPrimary : MCDesign.Colors.textTertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(12)

            Button(action: finishSubtest) {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(MCDesign.Colors.primary700)
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Scoring

    private func scoreRecall() {
        matchedUnits = scoreLogicalMemory(transcript: recallTranscript, scoringUnits: story.scoringUnits)
        phase = .scored
    }

    private func finishSubtest() {
        qmciState.logicalMemoryRecalledUnits = matchedUnits
        qmciState.logicalMemoryTranscript = recallTranscript
        qmciState.completedSubtests.insert(.logicalMemory)
        onComplete()
    }
}

#Preview {
    let state = QmciState()
    state.selectStory()
    return LogicalMemoryView(qmciState: state, onComplete: {})
}

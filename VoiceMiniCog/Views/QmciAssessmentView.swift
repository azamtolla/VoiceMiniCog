//
//  QmciAssessmentView.swift
//  VoiceMiniCog
//
//  Orchestrates all 6 Qmci subtests in sequence.
//  Each subtest is a dedicated view; this view manages transitions.
//
//  Flow: Orientation → Registration → Clock Drawing → Verbal Fluency
//        → Logical Memory → Delayed Recall → Done
//

import SwiftUI

struct QmciAssessmentView: View {
    @Bindable var state: AssessmentState
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var currentSubtest: QmciSubtest = .orientation
    @State private var showClockDrawing = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress header
            subtestProgressBar

            // Current subtest view
            Group {
                switch currentSubtest {
                case .orientation:
                    OrientationView(qmciState: state.qmciState) {
                        advanceTo(.registration)
                    }

                case .registration:
                    registrationView

                case .clockDrawing:
                    clockDrawingPhase

                case .verbalFluency:
                    VerbalFluencyView(qmciState: state.qmciState) {
                        advanceTo(.logicalMemory)
                    }

                case .logicalMemory:
                    LogicalMemoryView(qmciState: state.qmciState) {
                        advanceTo(.delayedRecall)
                    }

                case .delayedRecall:
                    delayedRecallView
                }
            }
        }
        .background(MCDesign.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("End") {
                    onCancel()
                }
                .foregroundColor(MCDesign.Colors.error)
            }
        }
        .onAppear {
            state.qmciState.selectWordList()
            state.qmciState.selectStory()
            state.currentPhase = .qmciOrientation
        }
    }

    // MARK: - Progress Bar

    private var subtestProgressBar: some View {
        VStack(spacing: MCDesign.Spacing.sm) {
            HStack {
                Text(currentSubtest.displayName)
                    .font(MCDesign.Fonts.reportHeading)
                    .foregroundColor(MCDesign.Colors.textPrimary)
                Spacer()
                Text("\(subtestIndex + 1) of \(QmciSubtest.allCases.count)")
                    .font(MCDesign.Fonts.smallCaption)
                    .foregroundColor(MCDesign.Colors.textTertiary)
            }

            MCProgressBar(
                progress: Double(subtestIndex + 1) / Double(QmciSubtest.allCases.count),
                color: MCDesign.Colors.primary500
            )
        }
        .padding(.horizontal, MCDesign.Spacing.lg)
        .padding(.vertical, MCDesign.Spacing.md)
        .background(MCDesign.Colors.surface)
        .mcShadow(MCDesign.Shadow.header)
    }

    private var subtestIndex: Int {
        QmciSubtest.allCases.firstIndex(of: currentSubtest) ?? 0
    }

    // MARK: - Registration (5 words)

    @State private var regPhase: RegistrationPhase = .present
    @State private var regTranscript = ""

    enum RegistrationPhase { case present, listen, scored }

    private var registrationView: some View {
        VStack(spacing: 0) {
            Spacer()

            switch regPhase {
            case .present:
                // Show words for patient to read
                VStack(spacing: MCDesign.Spacing.lg) {
                    MCIconCircle(
                        icon: "text.badge.star",
                        color: MCDesign.Colors.primary500,
                        size: MCDesign.Sizing.iconLarge
                    )

                    Text("Remember these words")
                        .font(MCDesign.Fonts.sectionTitle)
                        .foregroundColor(MCDesign.Colors.textPrimary)

                    Text("Listen carefully and try to remember them all.")
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(MCDesign.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MCDesign.Spacing.xl)

                    VStack(spacing: MCDesign.Spacing.md) {
                        ForEach(state.qmciState.registrationWords, id: \.self) { word in
                            Text(word.capitalized)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(MCDesign.Colors.primary700)
                        }
                    }
                    .padding(MCDesign.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(MCDesign.Colors.primary50)
                    .cornerRadius(MCDesign.Radius.large)
                    .padding(.horizontal, MCDesign.Spacing.xl)

                    MCPrimaryButton("Now repeat them back", icon: "mic.fill") {
                        regPhase = .listen
                    }
                    .padding(.horizontal, MCDesign.Spacing.xl)
                }

            case .listen:
                // Listen for patient repetition
                SpeechListenerView(
                    prompt: "Say the words you remember",
                    autoStopAfter: 15,
                    onDone: { transcript in
                        regTranscript = transcript
                        let result = scoreWordRecall(transcript: transcript, wordList: state.qmciState.registrationWords)
                        state.qmciState.registrationRecalledWords = result.recalled
                        regPhase = .scored
                    }
                )

            case .scored:
                // Show results
                VStack(spacing: MCDesign.Spacing.lg) {
                    Text("\(state.qmciState.registrationRecalledWords.count) of \(state.qmciState.registrationWords.count)")
                        .font(MCDesign.Fonts.scoreDisplay)
                        .foregroundColor(MCDesign.Colors.primary700)

                    Text("words repeated correctly")
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(MCDesign.Colors.textSecondary)

                    // Word-by-word result
                    VStack(spacing: MCDesign.Spacing.sm) {
                        ForEach(state.qmciState.registrationWords, id: \.self) { word in
                            let got = state.qmciState.registrationRecalledWords.contains(word.lowercased())
                            HStack {
                                Image(systemName: got ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(got ? MCDesign.Colors.success : MCDesign.Colors.border)
                                Text(word.capitalized)
                                    .font(MCDesign.Fonts.bodyMedium)
                                    .foregroundColor(got ? MCDesign.Colors.textPrimary : MCDesign.Colors.textTertiary)
                                Spacer()
                            }
                        }
                    }
                    .padding(MCDesign.Spacing.lg)
                    .background(MCDesign.Colors.surface)
                    .cornerRadius(MCDesign.Radius.medium)
                    .padding(.horizontal, MCDesign.Spacing.xl)

                    MCPrimaryButton("Continue to Clock Drawing", icon: "arrow.right") {
                        state.qmciState.completedSubtests.insert(.registration)
                        advanceTo(.clockDrawing)
                    }
                    .padding(.horizontal, MCDesign.Spacing.xl)
                }
            }

            Spacer()
        }
    }

    // MARK: - Clock Drawing

    private var clockDrawingPhase: some View {
        VStack(spacing: 0) {
            ClockDrawingView(state: state) { image, timeSec in
                state.clockImage = image
                state.clockTimeSec = timeSec

                // Score with on-device model
                Task.detached(priority: .userInitiated) {
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        await MainActor.run {
                            state.clockImageBase64 = data.base64EncodedString()
                        }
                    }

                    var aiScore = 1
                    if CDTOnDeviceScorer.shared.isReady {
                        if let result = try? await CDTOnDeviceScorer.shared.scoreClockDrawing(image: image) {
                            aiScore = result.aiClass
                        }
                    }

                    // Map Shulman 0-5 to Qmci 0-15 (Shulman * 3)
                    let qmciClockScore = min(aiScore * 5 + 5, 15) // rough mapping: 0→5, 1→10, 2→15

                    await MainActor.run {
                        state.clockScore = aiScore
                        state.clockScoreSource = .ai
                        state.qmciState.clockDrawingScore = qmciClockScore
                        state.qmciState.completedSubtests.insert(.clockDrawing)
                    }
                }

                advanceTo(.verbalFluency)
            }
        }
    }

    // MARK: - Delayed Recall (5 words)

    private var delayedRecallView: some View {
        DelayedRecallSubview(
            words: state.qmciState.registrationWords,
            onComplete: { recalledWords in
                state.qmciState.delayedRecallWords = recalledWords
                state.qmciState.completedSubtests.insert(.delayedRecall)
                state.qmciState.isComplete = true
                onComplete()
            }
        )
    }

    // MARK: - Navigation

    private func advanceTo(_ next: QmciSubtest) {
        withAnimation(MCDesign.Anim.standard) {
            currentSubtest = next
        }

        // Update phase
        switch next {
        case .orientation: state.currentPhase = .qmciOrientation
        case .registration: state.currentPhase = .qmciRegistration
        case .clockDrawing: state.currentPhase = .qmciClockDrawing
        case .verbalFluency: state.currentPhase = .qmciVerbalFluency
        case .logicalMemory: state.currentPhase = .qmciLogicalMemory
        case .delayedRecall: state.currentPhase = .qmciDelayedRecall
        }
    }
}

// MARK: - Delayed Recall Subview

/// Dedicated view for delayed word recall (5 words).
/// Patient tries to recall words from earlier registration phase.
private struct DelayedRecallSubview: View {
    let words: [String]
    let onComplete: ([String]) -> Void

    @State private var transcript = ""
    @State private var recalledWords: [String] = []
    @State private var showScoring = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if !showScoring {
                // Voice-first recall with auto-scoring
                SpeechListenerView(
                    prompt: "What were the \(words.count) words?",
                    autoStopAfter: 20,
                    onDone: { finalTranscript in
                        transcript = finalTranscript
                        let result = scoreWordRecall(transcript: finalTranscript, wordList: words)
                        recalledWords = result.recalled
                        showScoring = true
                    }
                )
            } else {
                // Scoring result
                VStack(spacing: MCDesign.Spacing.lg) {
                    Text("\(recalledWords.count)")
                        .font(MCDesign.Fonts.scoreDisplay)
                        .foregroundColor(MCDesign.Colors.primary700)

                    Text("of \(words.count) words recalled")
                        .font(MCDesign.Fonts.body)
                        .foregroundColor(MCDesign.Colors.textSecondary)

                    // Show which words were recalled
                    VStack(spacing: MCDesign.Spacing.sm) {
                        ForEach(words, id: \.self) { word in
                            let recalled = recalledWords.contains(word.lowercased())
                            HStack(spacing: MCDesign.Spacing.md) {
                                Image(systemName: recalled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(recalled ? MCDesign.Colors.success : MCDesign.Colors.border)
                                Text(word.capitalized)
                                    .font(MCDesign.Fonts.bodyMedium)
                                    .foregroundColor(recalled ? MCDesign.Colors.textPrimary : MCDesign.Colors.textTertiary)
                                Spacer()
                            }
                        }
                    }
                    .padding(MCDesign.Spacing.lg)
                    .background(MCDesign.Colors.surface)
                    .cornerRadius(MCDesign.Radius.medium)
                    .padding(.horizontal, MCDesign.Spacing.xl)

                    MCPrimaryButton("Finish Assessment", icon: "checkmark") {
                        onComplete(recalledWords)
                    }
                    .padding(.horizontal, MCDesign.Spacing.xl)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        QmciAssessmentView(
            state: AssessmentState(),
            onComplete: {},
            onCancel: {}
        )
    }
}

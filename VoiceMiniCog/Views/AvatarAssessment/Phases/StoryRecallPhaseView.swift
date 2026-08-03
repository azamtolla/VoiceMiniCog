//
//  StoryRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 7 — Logical Memory / Story Recall (QMCI subtest 6, 30 pts).
//
//  Flow:
//    1. .listening  — Avatar reads the story once, patient listens.
//    2. .recalling  — Avatar prompts "Tell me as much as you can", listens
//                     for patient retelling, asks "Anything else?" follow-up.
//    3. .scoring    — Clinician taps the units the patient recalled. Each
//                     unit is 2 points, 15 units per story, max 30 pts.
//                     Writes matched units into `qmciState.logicalMemoryRecalledUnits`.
//    4. Advances to the next phase (Completion).
//
//  Per QMCI protocol, only verbatim recall counts. The clinician is the
//  ground truth — the scoring grid is shown as a tap-to-mark card.
//

import SwiftUI

// MARK: - FlowLayout (wrapping horizontal layout for scoring unit chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - StoryRecallPhaseView

struct StoryRecallPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    let qmciState: QmciState

    @State private var phase: StoryPhase = .listening
    @State private var contentVisible = false
    @State private var followupAsked = false
    @State private var recalledFlags: [Bool] = []
    @State private var recallPromptSpeechEpoch = 0
    @State private var recallPromptListeningUnlocked = false
    /// Ceiling timer: auto-advance from .recalling → .scoring after 90 seconds
    /// to prevent unbounded recall time. QMCI protocol does not specify a hard
    /// ceiling for story recall, but 90s is generous and prevents stalls.
    @State private var recallCeilingWork: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum StoryPhase { case listening, recalling, scoring }

    // MARK: Computed

    private var story: LogicalMemoryStory { qmciState.currentStory }
    private var scoringUnits: [String] { story.scoringUnits }
    private var recalledCount: Int { recalledFlags.filter { $0 }.count }
    private var earnedPoints: Int { min(recalledCount * 2, 30) }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .listening, .recalling:
                listeningOrRecallingView
            case .scoring:
                scoringView
            }
        }
        .onAppear {
            avatarInterrupt()
            avatarSetAssessmentPhaseType(.storyRecall)
            avatarBeginSilenceWatch()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            avatarSetAssessmentContext(QMCIAvatarContext.storyRecall)
            // Initialize the scoring flags to match the current story's unit count.
            if recalledFlags.count != scoringUnits.count {
                recalledFlags = Array(repeating: false, count: scoringUnits.count)
            }
            // Avatar speaks the story intro + reads the story text.
            avatarSpeak(LeftPaneSpeechCopy.storyRecallIntro)
            // After a brief pause for the intro, read the story — BUT only
            // if we're still actually on the Story Recall phase in the
            // layout manager. Previously this only checked local
            // StoryPhase.listening, so a premature advance (e.g., from a
            // stale VerbalFluency fallback) would leave this closure
            // firing the story AFTER the completion screen was already up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                guard layoutManager.currentPhase == .storyRecall else { return }
                if phase == .listening {
                    avatarSpeak(story.voiceText)
                }
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .recalling {
                recallPromptSpeechEpoch += 1
                let epoch = recallPromptSpeechEpoch
                recallPromptListeningUnlocked = false
                layoutManager.avatarBehavior = .speaking
                avatarSpeak(LeftPaneSpeechCopy.storyRecallPrompt)
                let wc = LeftPaneSpeechCopy.storyRecallPrompt.split(separator: " ").count
                let fallback = max(12.0, Double(wc) * 0.35 + 5.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + fallback) {
                    unlockStoryRecallListeningIfNeeded(epoch: epoch)
                }

                // Ceiling timer: auto-advance to scoring after 90 seconds.
                recallCeilingWork?.cancel()
                let ceiling = DispatchWorkItem {
                    guard phase == .recalling else { return }
                    contentVisible = false
                    withAnimation(AssessmentTheme.Anim.contentFade) { phase = .scoring }
                    withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                        contentVisible = true
                    }
                }
                recallCeilingWork = ceiling
                DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: ceiling)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking)) { _ in
            unlockStoryRecallListeningIfNeeded(epoch: recallPromptSpeechEpoch)
        }
        .onReceive(NotificationCenter.default.publisher(for: .patientDoneSpeaking)) { _ in
            // QMCI protocol: one follow-up "Anything else?" after patient stops
            guard phase == .recalling, !followupAsked else { return }
            followupAsked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                avatarSpeak(LeftPaneSpeechCopy.storyRecallFollowup)
            }
        }
    }

    // MARK: - Listening / Recalling View

    private var listeningOrRecallingView: some View {
        VStack(spacing: 0) {

            // Phase name rendered by the chevron track — no header badge.
            Spacer()

            // MARK: Baton-pass card — immersive waveform ↔ "your turn" card.
            // Use .id(phase) + asymmetric transition so the two states feel
            // like a choreographed handoff rather than an in-place swap.
            Group {
                if phase == .listening {
                    immersiveWaveform
                } else {
                    yourTurnCard
                }
            }
            .id(phase)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 28)),
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    )
            )
            .motionSafe(AssessmentTheme.Motion.phaseEnter, value: phase)

            Spacer().frame(height: 16)
        }
    }

    // MARK: - Immersive waveform (listening state)

    /// Large centered waveform visualization shown while the avatar narrates.
    /// Uses a TimelineView-driven sinewave — fluid, not jumpy, and drops to
    /// a static pattern under reduce-motion.
    @ViewBuilder
    private var immersiveWaveform: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(layoutManager.accentColor)
                .assessmentIconHeaderAccent(layoutManager.accentColor)

            Text(LeftPaneSpeechCopy.storyRecallListeningTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)

            Text(LeftPaneSpeechCopy.storyRecallListeningSubtitle)
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)

            flowingWaveform
                .frame(height: 120)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(AssessmentTheme.Motion.phaseEnter) { phase = .recalling }
                layoutManager.setAvatarSpeaking()
            } label: {
                Text("Story Finished — Begin Recall")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .padding(.top, 4)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
    }

    @ViewBuilder
    private var flowingWaveform: some View {
        let color = layoutManager.accentColor
        if reduceMotion {
            // Static multi-bar waveform — no animation
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(color.opacity(0.55))
                        .frame(width: 5, height: CGFloat(14 + (i % 4) * 10))
                }
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                Canvas { context, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let barCount = 28
                    let spacing: CGFloat = 6
                    let barWidth = (size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
                    for i in 0..<barCount {
                        let phaseShift = Double(i) * 0.35
                        let amplitude = (sin(t * 3.2 - phaseShift) + 1) / 2 // 0...1
                        let secondary = (sin(t * 1.6 + phaseShift * 0.7) + 1) / 2
                        let combined = (amplitude * 0.7 + secondary * 0.3)
                        let height = max(6, CGFloat(combined) * size.height)
                        let x = CGFloat(i) * (barWidth + spacing)
                        let rect = CGRect(
                            x: x,
                            y: (size.height - height) / 2,
                            width: barWidth,
                            height: height
                        )
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        context.fill(
                            path,
                            with: .color(color.opacity(0.35 + combined * 0.45))
                        )
                    }
                }
            }
        }
    }

    // MARK: - "Your Turn" card (recalling state)

    /// Warm regularMaterial card that slides up when the baton passes from
    /// the avatar back to the patient. Mic icon with a listening bloom and
    /// gentle copy — "Take your time. Tell me everything you remember."
    @ViewBuilder
    private var yourTurnCard: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 16) {
            ZStack {
                // Listening bloom behind the mic
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let breath = (sin(t * 2.0 * .pi / AssessmentTheme.Motion.avatarPulseDuration) + 1) / 2
                        Circle()
                            .fill(layoutManager.accentColor.opacity(0.18 + breath * 0.12))
                            .frame(width: 96, height: 96)
                            .blur(radius: 18)
                            .scaleEffect(1.0 + CGFloat(breath) * 0.08)
                    }
                } else {
                    Circle()
                        .fill(layoutManager.accentColor.opacity(0.18))
                        .frame(width: 96, height: 96)
                        .blur(radius: 18)
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(layoutManager.accentColor)
            }
            .frame(height: 100)

            Text(LeftPaneSpeechCopy.storyRecallRecallingTitle)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)

            Text("Take your time. Tell me everything you remember.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                cancelCeilingTimer()
                withAnimation(AssessmentTheme.Motion.phaseExit) { phase = .scoring }
                contentVisible = false
                withAnimation(AssessmentTheme.Motion.phaseEnter.delay(0.05)) {
                    contentVisible = true
                }
            } label: {
                Text("Done — Score Recall")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .assessmentGlass(in: shape, tint: layoutManager.accentColor, prominence: .regular)
        .overlay(shape.stroke(layoutManager.accentColor.opacity(0.14), lineWidth: 1))
        .assessmentShadow(AssessmentTheme.Depth.cardResting)
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
    }

    // MARK: - Scoring View (Clinician Grid)

    private var scoringView: some View {
        VStack(spacing: 0) {

            Spacer().frame(height: 8)

            // MARK: Header
            Image(systemName: "checklist")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.bottom, 10)
                .assessmentIconHeaderAccent(layoutManager.accentColor)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            Text("Score Story Recall")
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 12)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            Text("Tap each word the patient recalled.\n2 points per word, 30 max.")
                .font(AssessmentTheme.Fonts.helper)
                .foregroundStyle(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.16), value: contentVisible)

            // MARK: Unit Grid
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(Array(scoringUnits.enumerated()), id: \.offset) { index, unit in
                        unitChip(index: index, unit: unit)
                    }
                }
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.20), value: contentVisible)

            // MARK: Score Display
            Text("\(earnedPoints)/30 points  •  \(recalledCount) of \(scoringUnits.count) recalled")
                .font(AssessmentTheme.Fonts.scoreDisplay)
                .foregroundStyle(layoutManager.accentColor)
                .padding(.top, 14)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: earnedPoints)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 10)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.24), value: contentVisible)

            Spacer()

            // MARK: Finish Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                // Persist the recalled units into QmciState for scoring.
                qmciState.logicalMemoryRecalledUnits = zip(scoringUnits, recalledFlags)
                    .filter { $0.1 }
                    .map { $0.0 }
                layoutManager.advanceToNextPhase()
            } label: {
                Text("Finish Assessment")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(layoutManager.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: layoutManager.accentColor.opacity(0.35),
                        radius: 8,
                        y: 4
                    )
            }
            .buttonStyle(AssessmentPrimaryButtonStyle())
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.30), value: contentVisible)

            Spacer().frame(height: 16)
        }
    }

    // MARK: - Unit Chip (Tap To Toggle)

    // MARK: - Ceiling Timer Cleanup

    private func cancelCeilingTimer() {
        recallCeilingWork?.cancel()
        recallCeilingWork = nil
    }

    private func unlockStoryRecallListeningIfNeeded(epoch: Int) {
        guard phase == .recalling else { return }
        guard epoch == recallPromptSpeechEpoch else { return }
        guard !recallPromptListeningUnlocked else { return }
        recallPromptListeningUnlocked = true
        layoutManager.setAvatarListening()
    }

    private func unitChip(index: Int, unit: String) -> some View {
        let recalled = recalledFlags[safeIndex: index] ?? false
        return Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            guard index < recalledFlags.count else { return }
            withAnimation(AssessmentTheme.Anim.buttonPress) {
                recalledFlags[index].toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: recalled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(recalled ? Color.white : AssessmentTheme.Content.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                recalled
                    ? layoutManager.accentColor
                    : Color.gray.opacity(0.10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        recalled ? Color.clear : Color.black.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe Subscript

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Listening") {
    StoryRecallPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: QmciState()
    )
    .background(AssessmentTheme.Content.background)
}

#Preview("Scoring") {
    let state = QmciState()
    state.selectStory()
    return StoryRecallPhaseView(
        layoutManager: AvatarLayoutManager(),
        qmciState: state
    )
    .background(AssessmentTheme.Content.background)
}

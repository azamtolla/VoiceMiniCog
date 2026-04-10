//
//  ClockDrawingPhaseView.swift
//  VoiceMiniCog
//
//  Phase 6 — Clock Drawing (EXPANDED layout).
//  The avatar shrinks to 30% width and dims to 0.4 opacity (handled by
//  AvatarLayoutManager); the content zone fills the remaining space with
//  a full-screen drawing canvas and a countdown timer.
//
//  CDT scoring rule (15 pts, Shulman 0–5): see CDTOnDeviceScorer.
//  This view captures strokes only; scoring happens at review time.
//
//  MARK: CLINICAL-UI — Clock drawing is a validated Qmci subtest (15 pts).
//  Design rationale: No undo button, no drawing guides beyond the dashed
//  circle, timer hidden from patient, every stroke captured for
//  biomarker extraction. See CLAUDE.md §Digital Biomarker Capture.
//

import SwiftUI

// MARK: - ClockDrawingPhaseView

struct ClockDrawingPhaseView: View {

    // MARK: Properties

    let layoutManager: AvatarLayoutManager
    @Bindable var assessmentState: AssessmentState

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var timeRemaining = 60 // QMCI protocol: exactly 1 minute
    @State private var timer: Timer?
    @State private var contentVisible = false

    // Biomarker capture — stroke timings and canvas dimensions for later PNG render
    @State private var canvasStartTime: Date = Date()
    @State private var canvasSize: CGSize = .zero
    @State private var didPersistBiomarkers = false

    // Pause biomarker: timestamp of the most recent stroke end. Used to
    // compute inter-stroke gaps; reset on view appear so stale state from a
    // prior session can't produce a phantom pause.
    @State private var lastStrokeEndTime: Date? = nil

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {

            // 1. Instruction text
            Text(LeftPaneSpeechCopy.clockDrawingOnScreen)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // 2. Drawing canvas — fills all available space
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let guideSize = size * 0.75

                ZStack {
                    // White card surface
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(
                            color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                            radius: 8,
                            y: 4
                        )

                    // Dashed circle guide
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                        )
                        .foregroundColor(Color.gray.opacity(0.25))
                        .frame(width: guideSize, height: guideSize)

                    // SwiftUI Canvas — renders completed lines + current stroke
                    Canvas { context, _ in
                        for stroke in lines {
                            drawStroke(stroke, in: context)
                        }
                        drawStroke(currentLine, in: context)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentLine.append(value.location)
                            }
                            .onEnded { _ in
                                if !currentLine.isEmpty {
                                    let stroke = currentLine
                                    lines.append(stroke)
                                    // Pause biomarker: if a prior stroke has
                                    // already ended, measure the inter-stroke
                                    // gap. QMCI spec: capture only gaps
                                    // strictly greater than 500 ms.
                                    let now = Date()
                                    if let lastEnd = lastStrokeEndTime {
                                        let gapMs = Int((now.timeIntervalSince(lastEnd) * 1000).rounded())
                                        if gapMs > 500 {
                                            let pause = ClockPauseEvent(
                                                startTimestamp: lastEnd.timeIntervalSince(canvasStartTime),
                                                durationMs: gapMs
                                            )
                                            assessmentState.qmciState.clockPauseEvents.append(pause)
                                        }
                                    }
                                    // Record stroke biomarker: timestamp at
                                    // commit (relative to canvasStartTime) and
                                    // the full point path for later analysis.
                                    let ts = now.timeIntervalSince(canvasStartTime)
                                    let event = ClockStrokeEvent(
                                        timestamp: ts,
                                        points: stroke.map { CGPointCodable($0) }
                                    )
                                    assessmentState.qmciState.clockStrokeEvents.append(event)
                                    lastStrokeEndTime = now
                                    currentLine = []
                                }
                            }
                    )
                }
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    canvasSize = CGSize(width: size, height: size)
                }
                .onChange(of: size) { _, newSize in
                    canvasSize = CGSize(width: newSize, height: newSize)
                }
            }
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 18)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.12), value: contentVisible)

            // 3. Bottom bar: timer only (Done Drawing moved to right-side status panel)
            HStack {
                Spacer()
                Text(formatTime(timeRemaining))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(timeRemaining <= 30 ? Color.red : AssessmentTheme.Content.textSecondary)
                Spacer()
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            // Reset canvas start time so stroke timestamps are relative to
            // when the patient actually saw the drawing surface.
            canvasStartTime = Date()
            // Clear any stale stroke-end reference from a prior session so
            // the first stroke never generates a phantom pause.
            lastStrokeEndTime = nil
            avatarSetContext("You are a clinical neuropsychologist administering the Clock Drawing subtest. The patient is drawing. Remain silent and observe. Do not provide hints, corrections, or commentary on the drawing. Do not tell the patient how much time remains. If the patient asks for help, say calmly: 'Please do your best.' Speak only when sent echo commands.")
            avatarSpeak(LeftPaneSpeechCopy.clockDrawingInstruction)
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            // Safety net: if the view disappears before the timer fires
            // (e.g. early advance), still persist whatever we have.
            persistBiomarkersIfNeeded()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                avatarSpeak(LeftPaneSpeechCopy.clockDrawingStop)
                timer?.invalidate()
                // Canvas locks here — capture biomarkers BEFORE advancing so
                // the next phase can read the persisted fields if needed.
                persistBiomarkersIfNeeded()
                layoutManager.advanceToNextPhase()
            }
        }
    }

    // MARK: - Biomarker Persistence

    /// Renders the current drawing to a PNG and stores it on the QmciState.
    /// Idempotent — safe to call from both the timer lockout path and the
    /// `onDisappear` safety net.
    private func persistBiomarkersIfNeeded() {
        guard !didPersistBiomarkers else { return }
        didPersistBiomarkers = true

        // PNG render — reconstruct the finished drawing as a standalone view
        // (no guide circle, no shadow, no background UI) and rasterize via
        // ImageRenderer (iOS 16+).
        let renderSize = canvasSize == .zero ? CGSize(width: 512, height: 512) : canvasSize
        let snapshot = ClockDrawingSnapshot(lines: lines, size: renderSize)
        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = UIScreen.main.scale
        if let uiImage = renderer.uiImage,
           let png = uiImage.pngData() {
            assessmentState.qmciState.clockDrawingImagePNG = png
        }
        // Stroke events are already appended on each gesture-end. Pause
        // events are not tracked in this view — skipping per spec guidance:
        // TODO: capture stroke biomarkers (pause events) if timing infra lands.
    }

    // MARK: - Drawing Helpers

    private func drawStroke(_ points: [CGPoint], in context: GraphicsContext) {
        var path = Path()
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(.black), lineWidth: 2.5)
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - ClockDrawingSnapshot

/// Minimal view used solely by `ImageRenderer` to rasterize the finished
/// clock drawing to PNG bytes. Matches the stroke style of the main Canvas.
private struct ClockDrawingSnapshot: View {
    let lines: [[CGPoint]]
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            for stroke in lines {
                var path = Path()
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.black), lineWidth: 2.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
    }
}

// MARK: - Preview

#Preview("Clock Drawing Phase") {
    ClockDrawingPhaseView(
        layoutManager: AvatarLayoutManager(),
        assessmentState: AssessmentState()
    )
    .background(AssessmentTheme.Content.background)
}

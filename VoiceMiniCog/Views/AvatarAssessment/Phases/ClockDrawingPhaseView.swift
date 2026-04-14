//
//  ClockDrawingPhaseView.swift
//  VoiceMiniCog
//
//  Phase 6 — Clock Drawing (EXPANDED layout).
//  The avatar is rendered at full opacity inside a circular controls panel
//  (right side) handled by AvatarLayoutManager and ClockDrawingControlsView.
//  The drawing canvas occupies the left content zone.
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
    @State private var timeRemaining = 180 // QMCI protocol allows up to 3 minutes (Shulman administration). Hidden from patient.
    @State private var timer: Timer?
    @State private var contentVisible = false

    @Environment(\.displayScale) private var displayScale

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

            PhaseHeaderBadge(
                phaseName: "Clock Drawing",
                icon: "clock.fill",
                accentColor: AssessmentTheme.Phase.clockDrawing
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20).padding(.leading, 20)

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

        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            avatarInterrupt()
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            // Reset all drawing state for clean phase entry (handles re-entry edge case).
            lines = []
            currentLine = []
            didPersistBiomarkers = false
            canvasStartTime = Date()
            lastStrokeEndTime = nil
            avatarSetAssessmentContext(QMCIAvatarContext.clockDrawing)
            avatarSpeak(LeftPaneSpeechCopy.clockDrawingInstruction)
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { _ in
            self.timeRemaining -= 1
            if self.timeRemaining <= 0 {
                avatarSpeak(LeftPaneSpeechCopy.clockDrawingStop)
                self.timer?.invalidate()
                // Canvas locks here — capture biomarkers BEFORE advancing so
                // the next phase can read the persisted fields if needed.
                self.persistBiomarkersIfNeeded()
                MainActor.assumeIsolated {
                    self.layoutManager.advanceToNextPhase()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage,
           let png = uiImage.pngData() {
            assessmentState.qmciState.clockDrawingImagePNG = png
        }
        // Stroke and pause events are appended live in the gesture's onEnded handler.
    }

    // MARK: - Drawing Helpers

    private func drawStroke(_ points: [CGPoint], in context: GraphicsContext) {
        guard let first = points.first else { return }
        if points.count == 1 {
            var dot = Path()
            dot.addEllipse(in: CGRect(x: first.x - 1.25, y: first.y - 1.25, width: 2.5, height: 2.5))
            context.fill(dot, with: .color(.black))
            return
        }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - ClockDrawingSnapshot

/// Minimal view used solely by `ImageRenderer` to rasterize the finished
/// clock drawing to PNG bytes. Matches the stroke style of the main Canvas.
private struct ClockDrawingSnapshot: View {
    let lines: [[CGPoint]]
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            // Force opaque white background — ImageRenderer doesn't always honor SwiftUI .background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(.white)
            )
            for stroke in lines {
                guard let first = stroke.first else { continue }
                if stroke.count == 1 {
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: first.x - 1.25, y: first.y - 1.25, width: 2.5, height: 2.5))
                    context.fill(dot, with: .color(.black))
                    continue
                }
                var path = Path()
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
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

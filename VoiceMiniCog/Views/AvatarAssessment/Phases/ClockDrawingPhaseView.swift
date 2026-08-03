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
    @State private var timeRemaining = 60 // exactly 1 minute per QMCI
    @State private var timer: Timer?
    @State private var contentVisible = false

    // Entrance animation state.
    // CLINICAL-UI NOTE: The QMCI clock drawing subtest prohibits any
    // on-screen guide beyond the dashed boundary circle (no tick marks,
    // no numbers) — patients must draw the clock face from scratch.
    // So the entrance choreography is limited to: (1) card scale-up,
    // (2) dashed-circle trim-stroke. Tick marks / numbers from the
    // design brief were intentionally NOT added. See CLAUDE.md §Clinical-validity surface.
    @State private var cardAppeared: Bool = false
    @State private var guideTrim: CGFloat = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.displayScale) private var displayScale

    // Biomarker capture — stroke timings and canvas dimensions for later PNG render
    @State private var canvasStartTime: Date = Date()
    @State private var canvasSize: CGSize = .zero
    @State private var didPersistBiomarkers = false

    // Pause biomarker: timestamp of the most recent stroke end. Used to
    // compute inter-stroke gaps; reset on view appear so stale state from a
    // prior session can't produce a phantom pause.
    @State private var lastStrokeEndTime: Date? = nil

    // v2 biomarker: wall-clock at the first onChanged call of the current
    // in-flight stroke. Set once when currentLine becomes non-empty, cleared
    // on commit. SwiftUI DragGesture has no explicit start callback, so we
    // detect the start by `currentLine.isEmpty` transitioning to non-empty.
    @State private var currentStrokeStart: Date? = nil

    // v2: minimum-strokes gate for the optional clinician "Done" button.
    // Below this count, advancing early would routinely yield uninterpretable
    // partial drawings; QMCI Shulman scoring needs at least face + numbers +
    // hands roughly captured.
    private let doneButtonMinimumStrokes = 3

    // PencilKit (Path-1 additive) — runtime A/B flag. When the
    // `voiceMiniCog.use_pencilkit_cdt` UserDefaults bool is true, the SwiftUI
    // Canvas drawing surface is swapped for the PKCanvasView-backed
    // CDTCanvasCard. Avatar wiring, dashed-circle guide, abandonment timer,
    // entrance choreography, and `assessmentState.qmciState.clockStrokeEvents`
    // persistence all remain owned by this view; the card is purely the
    // ink-capture surface.
    private static let usePencilKitFlagKey = "voiceMiniCog.use_pencilkit_cdt"
    @State private var usePencilKit: Bool = UserDefaults.standard.bool(forKey: ClockDrawingPhaseView.usePencilKitFlagKey)
    @State private var pencilStrokes: [CDTStroke] = []
    @State private var pencilStartTime: Date? = nil

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {

            // Phase name rendered by the chevron track — no header badge.

            // 1. Instruction text
            Text(LeftPaneSpeechCopy.clockDrawingOnScreen)
                .font(AssessmentTheme.Fonts.question)
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
                .animation(AssessmentTheme.Anim.contentEnter.delay(0.06), value: contentVisible)

            // 2. Drawing canvas — fills all available space.
            // PencilKit (Path-1) toggles in via `usePencilKit`. The PencilKit
            // card is purely the ink surface; the dashed-circle guide lives
            // on the legacy SwiftUI Canvas only (would need re-implementing
            // as a UIView background to layer behind PKCanvasView).
            if usePencilKit {
                CDTCanvasCard(
                    strokes:             $pencilStrokes,
                    assessmentStartTime: $pencilStartTime,
                    title:                LeftPaneSpeechCopy.clockDrawingOnScreen,
                    subtitle:             nil,
                    onDone:              { endPhaseEarly() }
                )
                .onChange(of: pencilStrokes) { _, newStrokes in
                    // Mirror PencilKit captures into the legacy persistence
                    // path so AssessmentPersistence, QMCI scoring, and
                    // PCPReport need no changes.
                    assessmentState.qmciState.clockStrokeEvents =
                        CDTBiomarkerBridge.toClockStrokeEvents(
                            newStrokes,
                            canvasStartTime: canvasStartTime
                        )
                }
                .padding(.horizontal, 4)
            } else {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let guideSize = size * 0.75

                ZStack {
                    // Warm material canvas — replaces the stark white card.
                    // regularMaterial gives a soft translucent feel that sits
                    // on the shared canvas, with a warm cream tint over top
                    // for paper-like warmth and a 20pt corner radius.
                    let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                    cardShape
                        .fill(.regularMaterial)
                        .overlay(
                            cardShape.fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.99, blue: 0.97).opacity(0.9),
                                        Color(red: 0.99, green: 0.97, blue: 0.94).opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(cardShape.stroke(Color.black.opacity(0.04), lineWidth: 0.5))
                        .assessmentShadow(cardAppeared ? AssessmentTheme.Depth.cardRaised : AssessmentTheme.Depth.cardResting)
                        .scaleEffect(cardAppeared ? 1.0 : 0.94)
                        .opacity(cardAppeared ? 1.0 : 0.0)

                    // Dashed circle guide — trims in around the ring so the
                    // patient visually "sees" the boundary draw itself. This
                    // is the only drawing-guide aid permitted by the QMCI
                    // protocol (see clinical note on state properties above).
                    Circle()
                        .trim(from: 0.0, to: guideTrim)
                        .stroke(
                            Color.gray.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [8, 4])
                        )
                        .rotationEffect(.degrees(-90)) // start at 12 o'clock
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
                                // Detect stroke start: first sample of a new
                                // in-flight line. DragGesture has no separate
                                // begin callback.
                                if currentLine.isEmpty {
                                    currentStrokeStart = Date()
                                }
                                currentLine.append(value.location)
                            }
                            .onEnded { _ in
                                if !currentLine.isEmpty {
                                    let stroke = currentLine
                                    lines.append(stroke)
                                    let now = Date()

                                    // Pause biomarker: if a prior stroke has
                                    // already ended, measure the inter-stroke
                                    // gap. QMCI spec: capture only gaps
                                    // strictly greater than 500 ms in the
                                    // dedicated pause-event array.
                                    let pauseBefore: TimeInterval
                                    if let lastEnd = lastStrokeEndTime {
                                        let gap = now.timeIntervalSince(lastEnd)
                                        pauseBefore = gap
                                        let gapMs = Int((gap * 1000).rounded())
                                        if gapMs > 500 {
                                            let pause = ClockPauseEvent(
                                                startTimestamp: lastEnd.timeIntervalSince(canvasStartTime),
                                                durationMs: gapMs
                                            )
                                            assessmentState.qmciState.clockPauseEvents.append(pause)
                                        }
                                    } else {
                                        pauseBefore = 0
                                    }

                                    // Record stroke biomarker (v2 fields).
                                    // pressureSamples deliberately empty —
                                    // SwiftUI Canvas + DragGesture exposes no
                                    // force values. See ClockStrokeEvent doc.
                                    let ts = now.timeIntervalSince(canvasStartTime)
                                    let event = ClockStrokeEvent(
                                        timestamp:       ts,
                                        startTime:       currentStrokeStart,
                                        endTime:         now,
                                        points:          stroke.map { CGPointCodable($0) },
                                        pressureSamples: [],
                                        pauseBefore:     pauseBefore,
                                        isCorrection:    false   // re-derived by markOverlaps below
                                    )
                                    assessmentState.qmciState.clockStrokeEvents.append(event)

                                    // Re-derive isCorrection across the full
                                    // stroke history so a late stroke that
                                    // overlaps an earlier mark gets flagged.
                                    assessmentState.qmciState.clockStrokeEvents =
                                        assessmentState.qmciState.clockStrokeEvents.markOverlaps()

                                    lastStrokeEndTime = now
                                    currentStrokeStart = nil
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
            .overlay(alignment: .bottomTrailing) { doneButtonOverlay }
            }   // end else (legacy SwiftUI Canvas branch)

        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .padding(.bottom, 32)
        .onAppear {
            avatarInterrupt()
            avatarSetAssessmentPhaseType(.clockDrawing)
            // Deliberately NOT arming silence watch — patient is drawing,
            // not speaking. The clock timer is the abandonment bound here.
            withAnimation(AssessmentTheme.Anim.contentEnter.delay(0.05)) {
                contentVisible = true
            }
            // Reset all drawing state for clean phase entry (handles re-entry edge case).
            lines = []
            currentLine = []
            didPersistBiomarkers = false
            canvasStartTime = Date()
            lastStrokeEndTime = nil

            // Entrance choreography: card scales in (~0.45s), then the
            // dashed guide circle trim-strokes itself around (~0.7s).
            // Total ~1.15s, matching the "under ~1.2s" brief budget.
            cardAppeared = false
            guideTrim = 0.0
            if reduceMotion {
                // Pure opacity fallback — no spatial movement.
                withAnimation(.easeInOut(duration: 0.25)) {
                    cardAppeared = true
                    guideTrim = 1.0
                }
            } else {
                withAnimation(AssessmentTheme.Motion.phaseEnter) {
                    cardAppeared = true
                }
                withAnimation(.easeOut(duration: 0.7).delay(0.35)) {
                    guideTrim = 1.0
                }
            }
            avatarSetAssessmentContext(QMCIAvatarContext.clockDrawing)
            avatarSpeak(LeftPaneSpeechCopy.clockDrawingInstruction)
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            // Safety net: persist clock drawing PNG if the phase exits early
            // (e.g., clinician taps "Done Drawing" before the timer expires).
            persistBiomarkersIfNeeded()
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

    // MARK: - Optional Done Button

    /// Bottom-trailing "Done" button revealed once the patient has committed
    /// at least `doneButtonMinimumStrokes`. Lets a clinician (or the patient
    /// who declares themselves finished) advance early without waiting out
    /// the full 60s. Below the threshold we hide it entirely — partial
    /// drawings of fewer than 3 strokes are not Shulman-scorable and would
    /// produce noise in research analysis.
    @ViewBuilder
    private var doneButtonOverlay: some View {
        let strokeCount = assessmentState.qmciState.clockStrokeEvents.count
        if strokeCount >= doneButtonMinimumStrokes {
            Button(action: endPhaseEarly) {
                Text("Done")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(MCDesign.Colors.primary700)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .animation(.easeOut(duration: 0.2), value: strokeCount)
        }
    }

    /// Mirrors the timer-expiry path: stop the timer, persist biomarkers,
    /// advance the phase. No "stop drawing" echo here — the patient (or
    /// clinician) initiated the end voluntarily, so the avatar prompt that
    /// normally lands at t=0 would be inappropriate.
    private func endPhaseEarly() {
        guard timer != nil else { return }   // re-entry guard
        timer?.invalidate()
        timer = nil
        persistBiomarkersIfNeeded()
        layoutManager.advanceToNextPhase()
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

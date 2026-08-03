//
//  CDTCanvasView.swift
//  VoiceMiniCog
//
//  PencilKit-based CDT canvas (additive Path 1 — feature-flagged).
//
//  This file ships ALONGSIDE the existing SwiftUI Canvas + DragGesture path
//  in `ClockDrawingPhaseView.swift`. It is selected at runtime via the
//  `voiceMiniCog.use_pencilkit_cdt` UserDefaults flag, allowing on-device
//  A/B comparison against the validated Qmci UX before any deprecation
//  decision. Existing `ClockStrokeEvent` persistence remains unchanged —
//  PencilKit strokes are converted via `CDTBiomarkerBridge.toClockStrokeEvents`
//  at the boundary so the QMCI scoring path, PCPReport, and partial-score
//  flow keep working without modification.
//
//  Why PencilKit here:
//  - Real Apple Pencil force values (`PKStrokePoint.force`) — finger input
//    yields force = 0; we sentinel that to 0.5 so the array stays well-formed
//    for downstream analysis but you can detect finger sessions by
//    `pressure.allSatisfy { $0 == 0.5 }`.
//  - Tilt + azimuth available on Pencil for future biomarker work.
//  - Built-in palm rejection when used with .anyInput drawing policy.
//

import SwiftUI
import PencilKit
import UIKit

// MARK: - CDTCanvasView (UIViewRepresentable around PKCanvasView)

struct CDTCanvasView: UIViewRepresentable {

    @Binding var strokes: [CDTStroke]
    @Binding var assessmentStartTime: Date?

    /// When true, the canvas rejects further input (e.g., after timer expiry).
    var isEditingDisabled: Bool = false

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        // Single-purpose clinical canvas: no tool picker, no system undo UI,
        // no ruler. The patient sees only ink.
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        // Pencil-preferred mode: when the user's system setting indicates
        // they prefer Pencil-only drawing (or a Pencil is currently paired),
        // reject finger input to eliminate palm-rejection edge cases. When
        // no Pencil is available we fall back to .anyInput so the canvas
        // still works for finger drawing during sim/dev testing.
        canvas.drawingPolicy = UIPencilInteraction.prefersPencilOnlyDrawing
            ? .pencilOnly
            : .anyInput
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.delegate = context.coordinator
        canvas.isUserInteractionEnabled = !isEditingDisabled
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.isUserInteractionEnabled = !isEditingDisabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {

        var parent: CDTCanvasView
        private var processedStrokeCount: Int = 0
        private var lastStrokeEndTime: Date? = nil

        init(_ parent: CDTCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let allStrokes = canvasView.drawing.strokes
            // Process only newly-added strokes (PencilKit never reorders the
            // strokes array, and we never delete here, so suffix iteration
            // is safe). This keeps the work O(new strokes), not O(total).
            guard allStrokes.count > processedStrokeCount else { return }
            let newStrokes = allStrokes[processedStrokeCount..<allStrokes.count]

            let now = Date()
            // Approximate per-stroke timing. PKStroke does not expose
            // wall-clock start/end of the user's gesture; the only signal
            // PencilKit gives is "drawing changed". We use a single Date()
            // per delegate callback: startTime ≈ end-of-prior-stroke (or
            // now-on-first), endTime = now. Real wall-clock gesture timing
            // would require a separate UIPanGestureRecognizer overlay.
            for pkStroke in newStrokes {
                var pts: [CGPoint] = []
                var pressures: [CGFloat] = []
                var altitudes: [CGFloat] = []
                var azimuths: [CGFloat] = []
                pkStroke.path.forEach { point in
                    pts.append(point.location)
                    // PKStrokePoint.force is non-optional CGFloat (not the
                    // optional the spec implies). Real Pencil delivers
                    // measured pressure; finger input yields 0. Sentinel
                    // 0.5 for finger so downstream code can distinguish
                    // "unmeasured" from "very light pressure".
                    pressures.append(point.force > 0 ? point.force : 0.5)
                    // altitude = angle of Pencil from perpendicular (radians).
                    // azimuth  = compass-like Pencil direction (radians).
                    // Both are meaningful only when a Pencil produced the
                    // sample; finger input leaves them at PencilKit's
                    // defaults which we still capture verbatim — analysis
                    // can filter against the pencilSource case.
                    altitudes.append(point.altitude)
                    azimuths.append(point.azimuth)
                }

                let startTime = lastStrokeEndTime ?? now
                let endTime = now
                let pauseBefore: TimeInterval = lastStrokeEndTime.map {
                    startTime.timeIntervalSince($0)
                } ?? 0

                let cdt = CDTStroke(
                    strokeId: UUID(),
                    startTime: startTime,
                    endTime: endTime,
                    points: pts,
                    pressure: pressures,
                    altitudes: altitudes,
                    azimuths: azimuths,
                    pauseBefore: pauseBefore,
                    isCorrection: false   // re-derived below
                )

                // First-stroke side effect: stamp the assessment start time
                // on the parent binding. Idempotent — only fires when nil.
                if parent.assessmentStartTime == nil {
                    parent.assessmentStartTime = startTime
                }
                parent.strokes.append(cdt)
                lastStrokeEndTime = endTime
            }

            processedStrokeCount = allStrokes.count
            // Re-derive isCorrection across the full history so a late stroke
            // overlapping an earlier mark gets flagged.
            parent.strokes = parent.strokes.markOverlaps()
        }
    }
}

// MARK: - CDTCanvasCard (composable card with title + Done button)

struct CDTCanvasCard: View {

    @Binding var strokes: [CDTStroke]
    @Binding var assessmentStartTime: Date?

    let title: String
    let subtitle: String?
    let onDone: (() -> Void)?

    /// Drawing surface is locked once `onDone` fires (parent sets to true
    /// to prevent late-arriving strokes after phase advance).
    var isLocked: Bool = false

    /// Threshold below which the Done button is hidden — partial drawings
    /// of fewer than 3 strokes are not Shulman-scorable.
    private let doneButtonMinimumStrokes = 3

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 8)

            ZStack {
                let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                cardShape
                    .fill(.regularMaterial)
                    .overlay(cardShape.stroke(Color.black.opacity(0.04), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                CDTCanvasView(
                    strokes: $strokes,
                    assessmentStartTime: $assessmentStartTime,
                    isEditingDisabled: isLocked
                )
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { doneButton }
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if strokes.count >= doneButtonMinimumStrokes, let onDone {
            Button(action: onDone) {
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
            .animation(.easeOut(duration: 0.2), value: strokes.count)
        }
    }
}

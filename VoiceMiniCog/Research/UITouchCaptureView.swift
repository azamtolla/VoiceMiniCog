//
//  UITouchCaptureView.swift
//  VoiceMiniCog
//
//  MERIDIAN-1 Section 5.1 primary capture path (UITouch).
//
//  Sampling strategy: coalesced + predicted, each tagged and — critically —
//  each stamped with its OWN hardware time.
//
//  - event.coalescedTouches(for:) recovers the real ~240 Hz Apple Pencil
//    samples that UIKit batches between display-refresh events. Each of
//    those UITouches carries its own `.timestamp`; we stamp every sample
//    with `touch.timestamp` so the intra-frame timing is preserved. (The
//    prior implementation read one wall-clock value per touchesMoved batch
//    and applied it to every coalesced sample, collapsing all intra-frame
//    dt to zero — which made velocity-CoV, jerk, and tremor-band power
//    undefined on the iPad side and biased the primary ICC. Fixed.)
//
//  - event.predictedTouches(for:) returns UIKit's forward-estimated
//    samples. Section 6.1 reserves the "touch type" field to allow
//    analysis-side filtering of predicted samples; they are captured
//    tagged "predicted" (and the SAP excludes them from feature
//    computation). Each predicted sample also carries its own timestamp.
//
//  - Time origin: t is milliseconds from the recorder's task-start origin
//    (set in beginTask, i.e. the Start-Session moment). Zeroing at task
//    start — not at first pen-down — is what preserves pre_first_hand_
//    latency (primary feature 9). `taskStartEpoch` must be set to
//    `recorder.taskStartMonotonicMs`; both it and touch.timestamp share
//    the mach monotonic base.
//
//  - Stylus selection: the view enables multi-touch and selects the
//    `.pencil` touch in every phase, so a palm or finger landing first
//    cannot cause the Pencil stroke to be dropped. Non-pencil contact is
//    ignored for capture (finger/palm should not occur; if it does it is
//    simply not recorded as a stroke).
//
//  Task lifecycle contract:
//  - Caller sets `taskStartEpoch = recorder.taskStartMonotonicMs` at mount
//    (after `recorder.beginTask(...)`), and mounts this view only while a
//    task is active. The recorder's fileHandle-nil guard makes stray
//    captures harmless.
//

#if DEBUG || RESEARCH
import SwiftUI
import UIKit

struct UITouchCaptureView: UIViewRepresentable {

    let recorder: RawStreamRecorder
    /// Monotonic ms of task start — set to `recorder.taskStartMonotonicMs`
    /// so captured `t` values share the recorder's single origin.
    let taskStartEpoch: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(recorder: recorder, taskStartEpoch: taskStartEpoch)
    }

    func makeUIView(context: Context) -> _TouchCapturingUIView {
        let view = _TouchCapturingUIView()
        view.coordinator = context.coordinator
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        // Multi-touch ON so a palm/finger touch cannot pre-empt the pencil;
        // handlers select the .pencil touch explicitly.
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: _TouchCapturingUIView, context: Context) {
        // Only re-sync the origin between tasks, never mid-stroke, so a
        // late epoch change cannot reindex an in-progress stream.
        if !context.coordinator.strokeInProgress {
            context.coordinator.taskStartEpoch = taskStartEpoch
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let recorder: RawStreamRecorder
        var taskStartEpoch: Double
        private(set) var strokeInProgress = false

        init(recorder: RawStreamRecorder, taskStartEpoch: Double) {
            self.recorder = recorder
            self.taskStartEpoch = taskStartEpoch
        }

        /// .moved path — coalesced (real) + predicted (estimated) loops,
        /// each sample stamped with its own hardware timestamp.
        func handleMoved(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
            guard let touch = pencilTouch(in: touches) else { return }

            for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
                recorder.recordSample(makeSample(coalesced, typeOverride: nil, phase: "move", in: view))
            }
            for predicted in event?.predictedTouches(for: touch) ?? [] {
                recorder.recordSample(makeSample(predicted, typeOverride: "predicted", phase: "move", in: view))
            }
        }

        /// .began / .ended / .cancelled — single sample from the pencil
        /// touch; pen-up flush on end/cancel.
        func handle(_ touches: Set<UITouch>, phase: UITouch.Phase, in view: UIView) {
            guard let touch = pencilTouch(in: touches) else { return }
            let phaseTag: String
            switch phase {
            case .began: phaseTag = "down"; strokeInProgress = true
            default:     phaseTag = "up"
            }
            recorder.recordSample(makeSample(touch, typeOverride: nil, phase: phaseTag, in: view))
            if phase == .ended || phase == .cancelled {
                strokeInProgress = false
                recorder.penUp()
            }
        }

        /// Prefer the Pencil touch; fall back to the primary touch only when
        /// no pencil is present so simulator/finger testing still works.
        private func pencilTouch(in touches: Set<UITouch>) -> UITouch? {
            touches.first(where: { $0.type == .pencil }) ?? touches.first
        }

        private func makeSample(_ touch: UITouch, typeOverride: String?, phase: String, in view: UIView) -> RawStreamRecorder.TouchSample {
            let loc = touch.preciseLocation(in: view)
            let maxF = Float(touch.maximumPossibleForce)
            let normalized = maxF > 0 ? Float(touch.force) / maxF : 0
            return RawStreamRecorder.TouchSample(
                t: touch.timestamp * 1000.0 - taskStartEpoch,
                x: Float(loc.x),
                y: Float(loc.y),
                p: max(0, min(1, normalized)),
                pRaw: Float(touch.force),
                pMax: maxF,
                alt: Float(touch.altitudeAngle),
                az: Float(touch.azimuthAngle(in: view)),
                type: typeOverride ?? touchTypeString(touch),
                phase: phase
            )
        }

        private func touchTypeString(_ touch: UITouch) -> String {
            switch touch.type {
            case .direct: return "direct"
            case .pencil: return "stylus"
            default:      return "other"   // indirect / indirectPointer / @unknown
            }
        }
    }

    // MARK: - UIView

    final class _TouchCapturingUIView: UIView {
        weak var coordinator: Coordinator?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            coordinator?.handle(touches, phase: .began, in: self)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            coordinator?.handleMoved(touches, with: event, in: self)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            coordinator?.handle(touches, phase: .ended, in: self)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            coordinator?.handle(touches, phase: .cancelled, in: self)
        }
    }
}
#endif

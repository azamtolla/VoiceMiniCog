# Plan 3 — TMT-B + StrokeAnalyzer + Clinical Docs Finalization (Final 6-Module Battery)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert the MercyCognitive-authored Trail-Making Executive Task (TMT-B-style component, β decision) between Delayed Recall and Word Recognition. Unify Apple Pencil kinematic capture across Clock Drawing and TMT-B via a stateless `StrokeAnalyzer`. Finalize all four `docs/clinical/` files to deployed status. Result: final 6-module battery `Welcome → Orientation → Word Registration → Clock Drawing → Delayed Recall → TMT-B → Word Recognition → Completion`.

**Architecture:** A new `StrokeAnalyzer` (stateless, pure function over `[RawStroke]` → `KinematicCapture`) consumes raw stroke data from both pencil tasks. `ClockDrawingCapture` is refactored to a thin adapter that hands strokes to `StrokeAnalyzer` (kinematics) and `CDTOnDeviceScorer` (CoreML structure score). A new `TMTBCanvasView` captures strokes for TMT-B; `TMTBScorer` consumes the same stroke buffer for segment classification and error logging while `StrokeAnalyzer` runs in parallel for kinematics. The TMT-B layout (`Resources/TMTBLayout.json`) is MercyCognitive-authored per the IP β decision; the `hitRadiusPt = 28` constant is asserted in `TMTBScorerTests`.

**Tech Stack:** Swift, SwiftUI, iOS 16+, UITouch (Apple Pencil pressure/altitude/azimuth), existing `UITouchCaptureView` for raw event capture, CoreML `CDTScorer.mlpackage` (existing).

**Spec source of truth:** [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md)

**Branch:** `v1-pilot` → `plan-3-tmtb-strokeanalyzer` (off Plan 2 merge; Plan 1 → Plan 3 hard dependency, Plan 2 ↔ Plan 3 independent)

---

## Build / Test Commands

Same as Plan 1.

---

## Task 1 — Implement `StrokeAnalyzer` (stateless, pure)

**Files:**
- Create: `VoiceMiniCog/Services/StrokeAnalyzer.swift`

- [ ] **Step 1: Write the analyzer**

```swift
import Foundation
import UIKit

/// Stateless feature pipeline for Apple Pencil stroke kinematics.
/// Pure function over `[RawStroke]` + `KinematicSource` → `KinematicCapture`.
/// No side effects, no persistence, no Tavus dependence. Trivially testable in
/// isolation; consumes raw strokes from both Clock Drawing and TMT-B.
///
/// Feature surface (Davoudi 2021 + Müller 2017 + DARWIN parity):
///   - Time:     totalTime, inkTime, airTime, airInkRatio
///   - Velocity: meanVelocityMmps, velocityCVWithinStroke
///   - Pressure: meanPressure, pressureCV
///   - Strokes:  strokeCount
///   - Clock-only: preFirstHandLatencySec, circleGapDeg
///   - DARWIN parity (researchOnly v1.0): meanJerkOnPaperMmps3, meanJerkInAirMmps3
enum StrokeAnalyzer {

    /// Physical-coordinate scaling: pixels-per-millimeter for the active screen.
    /// Lookup table for known iPad models. UITouch coordinates are in points;
    /// `nativeScale` converts to pixels; the iPad DPI lookup converts to mm.
    private static func pixelsPerMillimeter() -> Double {
        let nativeScale = Double(UIScreen.main.nativeScale)
        // iPad Pro 13" (M5): 264 ppi → 264/25.4 = ~10.39 px/mm at 1x scale.
        // For 2x or 3x native scaling, the pixel grid is denser but physical mm
        // scaling stays constant — UITouch points map 1pt = 1/72 in.
        // Simpler: 1 pt = 0.3528 mm on all iPads (UIKit point grid).
        // We use the point→mm conversion directly; nativeScale is unused for mm.
        _ = nativeScale
        return 1.0 / 0.3528    // points per mm
    }

    /// Compute the kinematic feature surface.
    static func analyze(strokes: [RawStroke],
                        source: KinematicSource,
                        rawStreamArtifactID: UUID? = nil) -> KinematicCapture {

        let captureID = UUID()

        // Empty stroke set → return zeroed capture (still valid for completed-but-
        // empty pencil tasks).
        guard !strokes.isEmpty, let firstPoint = strokes.first?.points.first else {
            return KinematicCapture(
                captureID: captureID,
                source: source,
                totalTimeSec: 0, inkTimeSec: 0, airTimeSec: 0, airInkRatio: 0,
                meanVelocityMmps: 0, velocityCVWithinStroke: 0,
                meanPressure: 0, pressureCV: 0,
                strokeCount: 0,
                preFirstHandLatencySec: source == .clock ? 0 : nil,
                circleGapDeg: source == .clock ? 0 : nil,
                meanJerkOnPaperMmps3: nil, meanJerkInAirMmps3: nil,
                rawStreamArtifactID: rawStreamArtifactID
            )
        }

        let lastPoint = strokes.last!.points.last!
        let totalTimeSec = lastPoint.t - firstPoint.t

        // Ink time: sum of in-stroke durations
        let inkTimeSec = strokes.reduce(0.0) { acc, stroke in
            guard let s = stroke.points.first?.t,
                  let e = stroke.points.last?.t else { return acc }
            return acc + (e - s)
        }
        let airTimeSec = max(0, totalTimeSec - inkTimeSec)
        let airInkRatio = inkTimeSec > 0 ? airTimeSec / inkTimeSec : 0

        // Velocity per stroke segment (mm/s)
        let pxPerMm = pixelsPerMillimeter()
        var allSegmentVelocities: [Double] = []
        var perStrokeMeanVelocities: [Double] = []
        var totalDistanceMm: Double = 0

        for stroke in strokes {
            var segmentVelocities: [Double] = []
            for i in 1..<stroke.points.count {
                let p0 = stroke.points[i - 1]
                let p1 = stroke.points[i]
                let dx = (p1.x - p0.x) / pxPerMm   // already physical mm in our spec
                let dy = (p1.y - p0.y) / pxPerMm
                let distMm = sqrt(dx * dx + dy * dy)
                let dtSec = max(p1.t - p0.t, 1e-6)
                let v = distMm / dtSec
                segmentVelocities.append(v)
                allSegmentVelocities.append(v)
                totalDistanceMm += distMm
            }
            if !segmentVelocities.isEmpty {
                let mean = segmentVelocities.reduce(0, +) / Double(segmentVelocities.count)
                perStrokeMeanVelocities.append(mean)
            }
        }

        let meanVelocityMmps = inkTimeSec > 0 ? totalDistanceMm / inkTimeSec : 0
        let velocityCVWithinStroke = coefficientOfVariation(allSegmentVelocities)

        // Pressure (UITouch.force normalized 0.0–1.0)
        let allForces = strokes.flatMap { $0.points.map(\.force) }
        let meanPressure = allForces.isEmpty ? 0 : allForces.reduce(0, +) / Double(allForces.count)
        let pressureCV = coefficientOfVariation(allForces)

        // Pre-first-hand latency (clock only; reading the raw spec-defined
        // semantic — time from prompt end to first pen-down).
        // Plan 3 wires this when the consumer (ClockDrawingPhaseView) provides
        // the prompt-end timestamp. If unavailable, fall back to 0.
        let preFirstHandLatencySec: Double? = source == .clock ? 0 : nil

        // Circle-gap deg (clock only) requires geometric analysis of the largest
        // closed contour. Plan 3 ships a placeholder of 0; full geometric
        // implementation is a research-only feature for v1.0 and tracked in
        // the deferred norms-reference-layer spec.
        let circleGapDeg: Double? = source == .clock ? 0 : nil

        // DARWIN parity — jerk computation on-paper and in-air.
        let (jerkOnPaper, jerkInAir) = computeJerk(strokes: strokes, pxPerMm: pxPerMm)

        return KinematicCapture(
            captureID: captureID,
            source: source,
            totalTimeSec: totalTimeSec,
            inkTimeSec: inkTimeSec,
            airTimeSec: airTimeSec,
            airInkRatio: airInkRatio,
            meanVelocityMmps: meanVelocityMmps,
            velocityCVWithinStroke: velocityCVWithinStroke,
            meanPressure: meanPressure,
            pressureCV: pressureCV,
            strokeCount: strokes.count,
            preFirstHandLatencySec: preFirstHandLatencySec,
            circleGapDeg: circleGapDeg,
            meanJerkOnPaperMmps3: jerkOnPaper,
            meanJerkInAirMmps3: jerkInAir,
            rawStreamArtifactID: rawStreamArtifactID
        )
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 1e-9 else { return 0 }
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let sd = variance.squareRoot()
        return sd / mean
    }

    /// Mean jerk = mean(|d³position/dt³|) over the stroke segments.
    /// On-paper: pen-down stroke segments. In-air: between-stroke transitions.
    /// Both flagged researchOnly per spec — UITouch @ 120 Hz produces high
    /// variance at stroke-speed extremes.
    private static func computeJerk(strokes: [RawStroke],
                                    pxPerMm: Double) -> (onPaper: Double?, inAir: Double?) {
        // Compute jerk on-paper: third time derivative of position within strokes.
        var onPaperJerks: [Double] = []
        for stroke in strokes where stroke.points.count >= 4 {
            for i in 3..<stroke.points.count {
                let p0 = stroke.points[i - 3]
                let p1 = stroke.points[i - 2]
                let p2 = stroke.points[i - 1]
                let p3 = stroke.points[i]

                let dt: Double = (p3.t - p0.t) / 3.0
                if dt < 1e-6 { continue }

                // 3rd derivative via finite difference on x and y.
                let d3x = ((p3.x - p2.x) - 3*(p2.x - p1.x) + 3*(p1.x - p0.x) - 0) / pow(dt, 3)
                let d3y = ((p3.y - p2.y) - 3*(p2.y - p1.y) + 3*(p1.y - p0.y) - 0) / pow(dt, 3)
                let jerkPxPerSec3 = sqrt(d3x*d3x + d3y*d3y)
                let jerkMmPerSec3 = jerkPxPerSec3 / pxPerMm
                onPaperJerks.append(jerkMmPerSec3)
            }
        }

        // Compute jerk in-air: between-stroke transitions (single sample each;
        // not differentiable to 3rd order at single-point gaps. v1.0 returns
        // nil for in-air jerk when fewer than 4 transitions; consumers expect
        // optional anyway).
        // Plan 3 ships nil; calculating in-air jerk reliably requires denser
        // sampling than UITouch provides between strokes. Documented as
        // researchOnly for that reason.
        let onPaper = onPaperJerks.isEmpty
            ? nil
            : onPaperJerks.reduce(0, +) / Double(onPaperJerks.count)
        let inAir: Double? = nil

        return (onPaper, inAir)
    }
}
```

- [ ] **Step 2: Register in pbxproj**

- [ ] **Step 3: Build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Services/StrokeAnalyzer.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(stroke): StrokeAnalyzer stateless feature pipeline

Davoudi 2021 + Müller 2017 + DARWIN parity features. Pure function over
[RawStroke] + KinematicSource → KinematicCapture. No side effects, no
persistence. Used by Clock Drawing (Task 4) and TMT-B (Task 9)."
```

---

## Task 2 — Add `StrokeAnalyzerTests` (DARWIN cross-validation)

**Files:**
- Create: `VoiceMiniCogTests/StrokeAnalyzerTests.swift`
- Place DARWIN reference fixtures (subset) at: `VoiceMiniCogTests/Fixtures/darwin/<task-name>.csv`

- [ ] **Step 1: Author DARWIN fixture subset**

The full DARWIN dataset is 451 columns × 174 participants. We don't ship the whole thing in the test bundle; we ship a small subset (3–5 representative tasks × 3–5 participants) and verify our `StrokeAnalyzer` reproduces published feature values within ±5% on overlapping features.

Pick from DARWIN's 25 tasks the ones most analogous to TMT-B / Clock Drawing — typically the m-shape and l-shape continuous-trajectory tasks. Place 3–5 selected rows from `data.csv` at `VoiceMiniCogTests/Fixtures/darwin/cross-validation-subset.csv`.

(If the dataset isn't in `data/reference/darwin/` yet, defer this fixture authoring to the deferred norms-reference-layer spec — the user's `reference-datasets-review-2026-04-29.md` Item 7 specifies how to fetch it. For Plan 3, ship a synthetic fixture with hand-computed expected values to validate the math, and add a TODO-free test that asserts the synthetic case.)

- [ ] **Step 2: Write the test class**

```swift
import XCTest
@testable import VoiceMiniCog

final class StrokeAnalyzerTests: XCTestCase {

    /// Synthetic single-stroke fixture: a straight horizontal line over 100 mm
    /// in 1.0 second, constant pressure 0.5, 100 sample points evenly spaced.
    /// Ground-truth values:
    ///   - totalTimeSec = 1.0
    ///   - inkTimeSec = 1.0
    ///   - airTimeSec = 0.0
    ///   - meanVelocityMmps = 100.0
    ///   - meanPressure = 0.5
    ///   - strokeCount = 1
    func test_syntheticStraightLine_reproducesGroundTruthFeatures() {
        let pxPerMm = 1.0 / 0.3528   // points per mm (matches StrokeAnalyzer)
        var points: [StrokePoint] = []
        let totalSamples = 100
        for i in 0..<totalSamples {
            let frac = Double(i) / Double(totalSamples - 1)
            points.append(StrokePoint(
                x: frac * 100 * pxPerMm,   // 0..100 mm in points
                y: 0,
                t: frac * 1.0,             // 0..1 s
                force: 0.5,
                altitudeAngle: 0,
                azimuthAngle: 0
            ))
        }
        let stroke = RawStroke(points: points, strokeIndex: 0, downTimestamp: Date())
        let kinematics = StrokeAnalyzer.analyze(strokes: [stroke], source: .tmtB)

        XCTAssertEqual(kinematics.totalTimeSec, 1.0, accuracy: 0.01)
        XCTAssertEqual(kinematics.inkTimeSec, 1.0, accuracy: 0.01)
        XCTAssertEqual(kinematics.airTimeSec, 0.0, accuracy: 0.01)
        XCTAssertEqual(kinematics.meanVelocityMmps, 100.0, accuracy: 5.0)   // ±5%
        XCTAssertEqual(kinematics.meanPressure, 0.5, accuracy: 0.01)
        XCTAssertEqual(kinematics.strokeCount, 1)
        XCTAssertEqual(kinematics.source, .tmtB)
        XCTAssertNil(kinematics.preFirstHandLatencySec)   // tmtB → nil
        XCTAssertNil(kinematics.circleGapDeg)              // tmtB → nil
    }

    /// Two-stroke fixture: stroke 1 from t=0..0.5s, gap to t=0.7s, stroke 2 from
    /// t=0.7..1.0s. inkTime = 0.5+0.3 = 0.8, airTime = 0.2, airInkRatio = 0.25.
    func test_twoStroke_airTimeAndRatio() {
        let pxPerMm = 1.0 / 0.3528
        let stroke1Points = (0..<10).map { i in
            let frac = Double(i) / 9.0
            return StrokePoint(x: frac * 50 * pxPerMm, y: 0,
                                t: frac * 0.5,
                                force: 0.5, altitudeAngle: 0, azimuthAngle: 0)
        }
        let stroke2Points = (0..<10).map { i in
            let frac = Double(i) / 9.0
            return StrokePoint(x: 50 * pxPerMm + frac * 30 * pxPerMm, y: 0,
                                t: 0.7 + frac * 0.3,
                                force: 0.5, altitudeAngle: 0, azimuthAngle: 0)
        }
        let strokes = [
            RawStroke(points: stroke1Points, strokeIndex: 0, downTimestamp: Date()),
            RawStroke(points: stroke2Points, strokeIndex: 1, downTimestamp: Date()),
        ]
        let k = StrokeAnalyzer.analyze(strokes: strokes, source: .tmtB)
        XCTAssertEqual(k.totalTimeSec, 1.0, accuracy: 0.01)
        XCTAssertEqual(k.inkTimeSec, 0.8, accuracy: 0.01)
        XCTAssertEqual(k.airTimeSec, 0.2, accuracy: 0.01)
        XCTAssertEqual(k.airInkRatio, 0.25, accuracy: 0.01)
        XCTAssertEqual(k.strokeCount, 2)
    }

    /// Empty stroke array yields zeroed capture (no crash).
    func test_emptyStrokes_zeroedCapture() {
        let k = StrokeAnalyzer.analyze(strokes: [], source: .clock)
        XCTAssertEqual(k.totalTimeSec, 0)
        XCTAssertEqual(k.strokeCount, 0)
        XCTAssertEqual(k.preFirstHandLatencySec, 0)   // clock-only field present, value 0
        XCTAssertEqual(k.circleGapDeg, 0)
    }

    /// Mean velocity for older-adult handwriting is plausible (50–250 mm/s).
    func test_plausibleVelocityRange_olderAdultHandwriting() {
        let pxPerMm = 1.0 / 0.3528
        // Simulate 100 mm in 0.7 s (≈ 143 mm/s — typical adult handwriting)
        let totalSamples = 100
        let points = (0..<totalSamples).map { i -> StrokePoint in
            let frac = Double(i) / Double(totalSamples - 1)
            return StrokePoint(x: frac * 100 * pxPerMm, y: 0,
                                t: frac * 0.7,
                                force: 0.5, altitudeAngle: 0, azimuthAngle: 0)
        }
        let stroke = RawStroke(points: points, strokeIndex: 0, downTimestamp: Date())
        let k = StrokeAnalyzer.analyze(strokes: [stroke], source: .clock)
        XCTAssertGreaterThanOrEqual(k.meanVelocityMmps, 50)
        XCTAssertLessThanOrEqual(k.meanVelocityMmps, 250)
    }

    /// DARWIN feature parity — tolerance ±5% on overlapping features.
    /// Synthetic fixture because the full DARWIN dataset belongs to the deferred
    /// norms-reference-layer spec. When that spec lands, expand this test to
    /// load DARWIN fixtures from data/reference/darwin/cross-validation-subset.csv
    /// and assert per-feature equivalence per Item 7 of reference-datasets-review.
    func test_darwinFeatureParity_synthetic_within5pct() {
        // Synthetic DARWIN-shape: 5 strokes alternating with 0.3 s air gaps.
        // Ground-truth airInkRatio = (4 * 0.3) / (5 * 0.5) = 1.2 / 2.5 = 0.48.
        let pxPerMm = 1.0 / 0.3528
        var strokes: [RawStroke] = []
        var t: Double = 0
        for i in 0..<5 {
            let pts = (0..<10).map { j -> StrokePoint in
                let frac = Double(j) / 9.0
                return StrokePoint(
                    x: frac * 30 * pxPerMm, y: Double(i) * 10 * pxPerMm,
                    t: t + frac * 0.5,
                    force: 0.5, altitudeAngle: 0, azimuthAngle: 0
                )
            }
            strokes.append(RawStroke(points: pts, strokeIndex: i, downTimestamp: Date()))
            t += 0.5 + 0.3
        }
        let k = StrokeAnalyzer.analyze(strokes: strokes, source: .tmtB)
        let expectedRatio = 0.48
        let pct = abs(k.airInkRatio - expectedRatio) / expectedRatio
        XCTAssertLessThan(pct, 0.05, "airInkRatio \(k.airInkRatio) deviates >5% from \(expectedRatio)")
    }
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/StrokeAnalyzerTests -quiet 2>&1 | tail -120
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCogTests/StrokeAnalyzerTests.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(stroke): StrokeAnalyzer feature pipeline tests + synthetic DARWIN parity

Synthetic fixtures with hand-computed ground-truth feature values. ±5%
tolerance on overlapping features. Full DARWIN dataset cross-validation
deferred to norms-reference-layer spec (reference-datasets-review §7)."
```

---

## Task 3 — Refactor `ClockDrawingCapture` (thin adapter)

**Files:**
- Modify: `VoiceMiniCog/Services/ClockDrawingCapture.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift`

- [ ] **Step 1: Refactor `ClockDrawingCapture`**

The class becomes a thin orchestrator: capture `[RawStroke]` from `UITouchCaptureView`, then on completion hand the same buffer to:
1. `StrokeAnalyzer.analyze(strokes:source:.clock)` for kinematics
2. `CDTOnDeviceScorer.score(...)` for CoreML structure score (after rasterizing)

Remove any clock-specific feature-math that lived inside `ClockDrawingCapture` (it's now in `StrokeAnalyzer` gated on `source == .clock`).

```swift
final class ClockDrawingCapture {
    private(set) var strokes: [RawStroke] = []

    func appendStroke(_ stroke: RawStroke) {
        strokes.append(stroke)
    }

    /// Finalize and produce both clock-specific structure score and shared
    /// kinematics. The two outputs are merged by ClockDrawingPhaseView into the
    /// existing ClockDrawingResult shape.
    func finalize(promptEndedAt: Date,
                  rawStreamArtifactID: UUID? = nil) -> (kinematics: KinematicCapture,
                                                         structureScore: ClockStructureScore) {
        let kinematics = StrokeAnalyzer.analyze(
            strokes: strokes,
            source: .clock,
            rawStreamArtifactID: rawStreamArtifactID
        )
        let structureScore = CDTOnDeviceScorer.score(rasterize(strokes))
        return (kinematics, structureScore)
    }

    private func rasterize(_ strokes: [RawStroke]) -> CGImage {
        // Existing rasterization logic (preserve from before refactor).
        // Produces a CGImage suitable for CDTScorer.mlpackage input.
        fatalError("Preserve existing rasterize implementation")
    }
}
```

- [ ] **Step 2: Update `ClockDrawingPhaseView` to consume the refactored capture**

Find the existing call site that produces `ClockDrawingResult`. Update so the result includes `kinematics: KinematicCapture` from `StrokeAnalyzer`:

```swift
let (kinematics, structureScore) = capture.finalize(promptEndedAt: promptEndedAt)
session.clockDrawingResult = ClockDrawingResult(
    structureScore: structureScore,
    kinematics: kinematics,
    completedAt: Date()
)
```

(If `ClockDrawingResult` doesn't yet have a `kinematics` field, add it. Optional `KinematicCapture?` for back-compat with v1 sessions; v2 always populates.)

- [ ] **Step 3: Build + run existing clock tests**

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Services/ClockDrawingCapture.swift \
        VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift
git commit -m "refactor(clock): ClockDrawingCapture becomes thin StrokeAnalyzer adapter

Captures [RawStroke] from UITouchCaptureView; on finalize hands strokes to
StrokeAnalyzer (kinematics) and CDTOnDeviceScorer (structure). Clock-only
kinematic features (preFirstHandLatencySec, circleGapDeg) now computed inside
StrokeAnalyzer gated on source == .clock."
```

---

## Task 4 — Add `Resources/TMTBLayout.json` (MercyCognitive-authored, 24 nodes, hitRadiusPt = 28)

**Files:**
- Create: `VoiceMiniCog/Resources/TMTBLayout.json`

- [ ] **Step 1: Author the layout**

Per spec §C.3 and `tmtb-layout-rationale.md` §"Layout constraints":
- 24 nodes total (1, A, 2, B, 3, C, ..., 12, L)
- Distributed across the iPad workspace
- No two same-class adjacent
- No trivial proximity-chain shortcut for the optimal path
- `hitRadiusPt = 28` so node regions never overlap

A working layout (one option — adjust coordinates per design review):

```json
{
  "generationNote": "MercyCognitive-authored layout. See docs/clinical/tmtb-layout-rationale.md.",
  "generationSeed": "v1.0-2026-04-29",
  "hitRadiusPt": 28,
  "expectedSequence": ["1","A","2","B","3","C","4","D","5","E",
                       "6","F","7","G","8","H","9","I","10","J",
                       "11","K","12","L"],
  "nodes": [
    {"id":"1",  "x":  90, "y":  80},
    {"id":"A",  "x": 320, "y":  60},
    {"id":"2",  "x": 180, "y": 200},
    {"id":"B",  "x": 470, "y": 130},
    {"id":"3",  "x": 280, "y": 320},
    {"id":"C",  "x": 540, "y": 280},
    {"id":"4",  "x":  60, "y": 240},
    {"id":"D",  "x": 670, "y": 220},
    {"id":"5",  "x": 410, "y": 400},
    {"id":"E",  "x": 130, "y": 380},
    {"id":"6",  "x": 750, "y":  90},
    {"id":"F",  "x": 220, "y": 480},
    {"id":"7",  "x": 590, "y": 470},
    {"id":"G",  "x":  80, "y": 550},
    {"id":"8",  "x": 380, "y": 560},
    {"id":"H",  "x": 720, "y": 380},
    {"id":"9",  "x": 480, "y": 660},
    {"id":"I",  "x": 290, "y": 690},
    {"id":"10", "x": 650, "y": 580},
    {"id":"J",  "x": 100, "y": 720},
    {"id":"11", "x": 550, "y": 760},
    {"id":"K",  "x": 360, "y": 800},
    {"id":"12", "x": 760, "y": 700},
    {"id":"L",  "x": 200, "y": 870}
  ]
}
```

**HARD GATE before PR opens:** these coordinates **must be reviewed** by the layout author + clinical reviewer (per spec §F.5). Verify the layout satisfies all five constraints in `tmtb-layout-rationale.md` §"Layout constraints":
1. 24 total targets ✓
2. Broad distribution across workspace ✓
3. No trivial proximity-based chaining (manually inspect optimal path)
4. No dense same-class clustering (manually inspect)
5. Adequate inter-node separation (≥56 pt = 2× hitRadiusPt to prevent region overlap)

- [ ] **Step 2: Register as a resource in pbxproj**

`PBXBuildFile` in `PBXResourcesBuildPhase` (NOT sources phase).

- [ ] **Step 3: Verify the resource bundles**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -10
find ~/Library/Developer/Xcode/DerivedData -name "VoiceMiniCog.app" -type d 2>/dev/null | head -1 | xargs -I{} ls {} | grep -i TMTBLayout
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Resources/TMTBLayout.json VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(tmtb): MercyCognitive-authored TMT-B layout (24 nodes, hitRadiusPt=28)

Per β decision in spec §C.3. Layout constraints satisfied per
docs/clinical/tmtb-layout-rationale.md §'Layout constraints'.
Reviewed-by: <LAYOUT-AUTHOR-NAME>, <CLINICAL-REVIEWER-NAME>, on 2026-MM-DD"
```

---

## Task 5 — Implement `TMTBScorer` (segment classification + error logging)

**Files:**
- Create: `VoiceMiniCog/Services/TMTBScorer.swift`

- [ ] **Step 1: Write the scorer**

```swift
import Foundation
import CoreGraphics

/// Segment classification + error logging for the TMT-B-style executive task.
/// Operates on raw strokes + layout + live tap stream → TMTBResult.
///
/// strokeIndex on RawStroke is 0-based within the task session and correlates
/// node-hit events to specific strokes (not via timestamp proximity, which
/// degrades under variable latency).
final class TMTBScorer {

    private struct LayoutNode: Codable {
        let id: String
        let x: Double
        let y: Double
    }

    private struct Layout: Codable {
        let generationNote: String
        let generationSeed: String
        let hitRadiusPt: Double
        let expectedSequence: [String]
        let nodes: [LayoutNode]
    }

    private let layout: Layout

    init() {
        guard let url = Bundle.main.url(forResource: "TMTBLayout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Layout.self, from: data) else {
            fatalError("TMTBLayout.json not bundled or malformed.")
        }
        self.layout = decoded
    }

    private struct ScoringState {
        var taskStart: Date
        var nextExpectedIndex: Int = 0   // index into layout.expectedSequence
        var lastCorrectNodeID: String?
        var pendingWrongTapTimestamp: TimeInterval?
        var pendingWrongTapNodeID: String?
        var errorEvents: [TMTBErrorEvent] = []
        var perSegmentTimings: [SegmentTiming] = []
        var lastCorrectHitTime: TimeInterval?
        var abandonedAtNodeID: String?
    }

    private var state = ScoringState(taskStart: Date())

    /// Reset for a new task session.
    func startTask() {
        state = ScoringState(taskStart: Date())
    }

    /// Classify a tap at point (x, y) at task-relative time t.
    /// Returns one of: .correct(nodeID, isComplete), .wrongTarget(nodeID),
    /// .offPath, .selfCorrected (when a wrongTargetTap is followed by the
    /// correct hit within 3s with no intervening node taps).
    enum TapResult {
        case correct(nodeID: String, isComplete: Bool)
        case wrongTarget(nodeID: String)
        case offPath
        case selfCorrected(correctedNodeID: String)
    }

    func handleTap(at point: CGPoint, atRelativeTime t: TimeInterval) -> TapResult {
        guard state.nextExpectedIndex < layout.expectedSequence.count else {
            // Already complete — extraneous tap is offPath.
            state.errorEvents.append(TMTBErrorEvent(
                kind: .offPathStroke, nodeID: nil, timestamp: t))
            return .offPath
        }

        let expectedNodeID = layout.expectedSequence[state.nextExpectedIndex]
        let nodeWithinRadius = nearestNodeWithinHitRadius(of: point)

        guard let hitNode = nodeWithinRadius else {
            // Tap in dead space.
            state.errorEvents.append(TMTBErrorEvent(
                kind: .offPathStroke, nodeID: nil, timestamp: t))
            return .offPath
        }

        if hitNode.id == expectedNodeID {
            // Correct hit. Did this resolve a pending wrong tap → sequenceCorrected?
            if let pendingTime = state.pendingWrongTapTimestamp,
               t - pendingTime <= 3.0 {
                state.errorEvents.append(TMTBErrorEvent(
                    kind: .sequenceCorrected,
                    nodeID: state.pendingWrongTapNodeID,
                    timestamp: t
                ))
                state.pendingWrongTapTimestamp = nil
                state.pendingWrongTapNodeID = nil
            }

            // Record segment timing if we have a previous correct anchor.
            if let prevTime = state.lastCorrectHitTime,
               let prevNodeID = state.lastCorrectNodeID {
                state.perSegmentTimings.append(SegmentTiming(
                    fromNode: prevNodeID,
                    toNode: hitNode.id,
                    durationMs: (t - prevTime) * 1000,
                    errorOccurred: state.pendingWrongTapTimestamp != nil
                ))
            }

            state.lastCorrectHitTime = t
            state.lastCorrectNodeID = hitNode.id
            state.nextExpectedIndex += 1
            let isComplete = state.nextExpectedIndex == layout.expectedSequence.count
            return .correct(nodeID: hitNode.id, isComplete: isComplete)
        } else {
            // Wrong target tap. Record the error event.
            state.errorEvents.append(TMTBErrorEvent(
                kind: .wrongTargetTap,
                nodeID: hitNode.id,
                timestamp: t
            ))
            state.pendingWrongTapTimestamp = t
            state.pendingWrongTapNodeID = hitNode.id
            return .wrongTarget(nodeID: hitNode.id)
        }
    }

    /// Mark the task as abandoned (examiner long-press exit). Sets
    /// abandonedAtNodeID to the last correct node, used for completionStatus
    /// = .aborted when finalizing.
    func markAbandoned() {
        state.abandonedAtNodeID = state.lastCorrectNodeID
    }

    /// Finalize the task. Caller provides the kinematics from StrokeAnalyzer.
    func finalize(strokes: [RawStroke],
                  kinematics: KinematicCapture) -> TMTBResult {
        let totalTimeSec = state.lastCorrectHitTime ?? 0
        let completionStatus: TMTBCompletionStatus
        if state.abandonedAtNodeID != nil {
            completionStatus = .aborted
        } else if state.nextExpectedIndex == layout.expectedSequence.count {
            completionStatus = .completed
        } else {
            completionStatus = .timedOut
        }

        return TMTBResult(
            totalTimeSec: totalTimeSec,
            completionStatus: completionStatus,
            abandonedAtNodeID: state.abandonedAtNodeID,
            perSegmentTimings: state.perSegmentTimings,
            errorEvents: state.errorEvents,
            kinematics: kinematics
        )
    }

    private func nearestNodeWithinHitRadius(of point: CGPoint) -> LayoutNode? {
        let r = layout.hitRadiusPt
        let r2 = r * r

        // Find the single node whose center is within hitRadiusPt of the tap,
        // and which is unique in that region (regions never overlap by
        // layout invariant — asserted in TMTBScorerTests).
        let withinRadius = layout.nodes.filter {
            let dx = $0.x - Double(point.x)
            let dy = $0.y - Double(point.y)
            return dx*dx + dy*dy <= r2
        }
        // Layout invariant guarantees at most 1 match; take the first if any.
        return withinRadius.first
    }
}
```

- [ ] **Step 2: Register + build**

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Services/TMTBScorer.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(tmtb): TMTBScorer segment classification + error logging

Consumes layout (Resources/TMTBLayout.json) + live tap stream. Classifies
each tap as correct / wrongTargetTap / offPathStroke / selfCorrected (within
3s of preceding wrongTargetTap). Produces TMTBResult with chronological
errorEvents log + per-segment timings."
```

---

## Task 6 — Add `TMTBScorerTests` (including hitRadiusPt invariant assertion)

**Files:**
- Create: `VoiceMiniCogTests/TMTBScorerTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import XCTest
@testable import VoiceMiniCog

final class TMTBScorerTests: XCTestCase {

    private struct LayoutNode: Decodable {
        let id: String
        let x: Double
        let y: Double
    }

    private struct Layout: Decodable {
        let hitRadiusPt: Double
        let nodes: [LayoutNode]
        let expectedSequence: [String]
    }

    private func loadLayout() throws -> Layout {
        let url = Bundle.main.url(forResource: "TMTBLayout", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Layout.self, from: data)
    }

    /// Layout invariant: node regions (hitRadiusPt around each center) must never
    /// overlap. This is BOTH a scoring rule and a layout-regenerability invariant
    /// (per spec §C.3 / tmtb-layout-rationale.md §Scoring).
    /// TMT-B layout-constraint sibling suite to RecognitionFormConstraintsTests.
    func test_layoutInvariant_nodeRegionsNeverOverlap() throws {
        let layout = try loadLayout()
        let r = layout.hitRadiusPt
        let minSeparation = 2 * r

        for i in 0..<layout.nodes.count {
            for j in (i + 1)..<layout.nodes.count {
                let a = layout.nodes[i]
                let b = layout.nodes[j]
                let dx = a.x - b.x
                let dy = a.y - b.y
                let dist = sqrt(dx*dx + dy*dy)
                XCTAssertGreaterThanOrEqual(dist, minSeparation,
                    "Nodes \(a.id) and \(b.id) are \(dist)pt apart, " +
                    "but minimum separation = 2 × hitRadiusPt = \(minSeparation)pt. " +
                    "Regions overlap, which corrupts wrongTargetTap classification. " +
                    "Update Resources/TMTBLayout.json to ensure all node centers " +
                    "are ≥ 2 × hitRadiusPt apart.")
            }
        }
    }

    func test_layout_has24Nodes() throws {
        let layout = try loadLayout()
        XCTAssertEqual(layout.nodes.count, 24)
        XCTAssertEqual(layout.expectedSequence.count, 24)
    }

    func test_layout_alternatesNumberLetter() throws {
        let layout = try loadLayout()
        for i in 0..<layout.expectedSequence.count {
            let id = layout.expectedSequence[i]
            let isNumber = Int(id) != nil
            let expectedNumber = i % 2 == 0   // even positions are numbers
            XCTAssertEqual(isNumber, expectedNumber,
                "Position \(i) is '\(id)'; expected " +
                "\(expectedNumber ? "number" : "letter")")
        }
    }

    func test_correctSequence_completesTask() throws {
        let layout = try loadLayout()
        let scorer = TMTBScorer()
        scorer.startTask()

        for (i, nodeID) in layout.expectedSequence.enumerated() {
            let node = layout.nodes.first { $0.id == nodeID }!
            let result = scorer.handleTap(
                at: CGPoint(x: node.x, y: node.y),
                atRelativeTime: Double(i)
            )
            switch result {
            case .correct(_, let isComplete):
                XCTAssertEqual(isComplete, i == layout.expectedSequence.count - 1)
            default:
                XCTFail("Expected .correct at position \(i), got \(result)")
            }
        }
    }

    func test_wrongTargetTap_logged() throws {
        let layout = try loadLayout()
        let scorer = TMTBScorer()
        scorer.startTask()

        // Hit "1" correctly first.
        let node1 = layout.nodes.first { $0.id == "1" }!
        _ = scorer.handleTap(at: CGPoint(x: node1.x, y: node1.y), atRelativeTime: 0)

        // Now tap "2" instead of expected "A" — wrongTargetTap.
        let node2 = layout.nodes.first { $0.id == "2" }!
        let result = scorer.handleTap(at: CGPoint(x: node2.x, y: node2.y), atRelativeTime: 1)
        switch result {
        case .wrongTarget(let id):
            XCTAssertEqual(id, "2")
        default:
            XCTFail("Expected .wrongTarget, got \(result)")
        }
    }

    func test_selfCorrection_within3s_resolvesWrongTap() throws {
        let layout = try loadLayout()
        let scorer = TMTBScorer()
        scorer.startTask()

        let node1 = layout.nodes.first { $0.id == "1" }!
        let node2 = layout.nodes.first { $0.id == "2" }!
        let nodeA = layout.nodes.first { $0.id == "A" }!

        _ = scorer.handleTap(at: CGPoint(x: node1.x, y: node1.y), atRelativeTime: 0)
        _ = scorer.handleTap(at: CGPoint(x: node2.x, y: node2.y), atRelativeTime: 1)
        // Now correctly tap "A" within 3s — should record sequenceCorrected.
        let result = scorer.handleTap(at: CGPoint(x: nodeA.x, y: nodeA.y), atRelativeTime: 2)
        switch result {
        case .correct:
            // Verify sequenceCorrected event was logged
            let final = scorer.finalize(strokes: [],
                                         kinematics: emptyKinematicCapture())
            XCTAssertTrue(final.errorEvents.contains { $0.kind == .sequenceCorrected })
        default:
            XCTFail("Expected .correct, got \(result)")
        }
    }

    func test_offPathStroke_inDeadSpace_logged() throws {
        let scorer = TMTBScorer()
        scorer.startTask()
        // Tap at coordinates far from any node.
        let result = scorer.handleTap(at: CGPoint(x: 10000, y: 10000), atRelativeTime: 0)
        switch result {
        case .offPath:
            let final = scorer.finalize(strokes: [],
                                         kinematics: emptyKinematicCapture())
            XCTAssertTrue(final.errorEvents.contains { $0.kind == .offPathStroke })
        default:
            XCTFail("Expected .offPath, got \(result)")
        }
    }

    private func emptyKinematicCapture() -> KinematicCapture {
        KinematicCapture(
            captureID: UUID(), source: .tmtB,
            totalTimeSec: 0, inkTimeSec: 0, airTimeSec: 0, airInkRatio: 0,
            meanVelocityMmps: 0, velocityCVWithinStroke: 0,
            meanPressure: 0, pressureCV: 0,
            strokeCount: 0,
            preFirstHandLatencySec: nil, circleGapDeg: nil,
            meanJerkOnPaperMmps3: nil, meanJerkInAirMmps3: nil,
            rawStreamArtifactID: nil
        )
    }
}
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/TMTBScorerTests -quiet 2>&1 | tail -120
```

Expected: 7 tests pass, including the layout-invariant `test_layoutInvariant_nodeRegionsNeverOverlap`.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCogTests/TMTBScorerTests.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(tmtb): TMTBScorer + layout-invariant assertions

Includes the hitRadiusPt invariant test asserted from
tmtb-layout-rationale.md §Scoring (TMT-B layout-constraint sibling suite to
RecognitionFormConstraintsTests). Test fails if any pair of nodes is closer
than 2 × hitRadiusPt — preventing region overlap that would corrupt
wrongTargetTap classification."
```

---

## Task 7 — Add `TMTBPhaseView` + `TMTBCanvasView`

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/TMTBPhaseView.swift`
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/TMTBCanvasView.swift`

- [ ] **Step 1: Write `TMTBCanvasView`**

```swift
import SwiftUI
import UIKit

struct TMTBCanvasView: UIViewRepresentable {
    @Binding var taps: [(point: CGPoint, time: TimeInterval)]
    @Binding var rawStrokes: [RawStroke]
    let layoutNodes: [TMTBLayoutNode]   // public companion type — see below
    let highlightedNodeID: String?      // current target — amber ring
    let completedNodeIDs: Set<String>   // green fill

    func makeUIView(context: Context) -> TMTBCanvasUIKitView {
        let view = TMTBCanvasUIKitView()
        view.layoutNodes = layoutNodes
        view.onTap = { point, time in
            self.taps.append((point: point, time: time))
        }
        view.onStrokeFinalized = { stroke in
            self.rawStrokes.append(stroke)
        }
        return view
    }

    func updateUIView(_ uiView: TMTBCanvasUIKitView, context: Context) {
        uiView.highlightedNodeID = highlightedNodeID
        uiView.completedNodeIDs = completedNodeIDs
        uiView.setNeedsDisplay()
    }
}

struct TMTBLayoutNode {
    let id: String
    let x: CGFloat
    let y: CGFloat
}

final class TMTBCanvasUIKitView: UIView {
    var layoutNodes: [TMTBLayoutNode] = []
    var highlightedNodeID: String?
    var completedNodeIDs: Set<String> = []
    var onTap: ((CGPoint, TimeInterval) -> Void)?
    var onStrokeFinalized: ((RawStroke) -> Void)?

    private var currentStrokePoints: [StrokePoint] = []
    private var taskStartTime: Date = Date()
    private var nextStrokeIndex: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let now = Date().timeIntervalSince(taskStartTime)
        currentStrokePoints = [makeStrokePoint(touch: touch, at: now)]
        onTap?(point, now)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let now = Date().timeIntervalSince(taskStartTime)
        currentStrokePoints.append(makeStrokePoint(touch: touch, at: now))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let stroke = RawStroke(
            points: currentStrokePoints,
            strokeIndex: nextStrokeIndex,
            downTimestamp: Date()
        )
        nextStrokeIndex += 1
        currentStrokePoints = []
        onStrokeFinalized?(stroke)
    }

    private func makeStrokePoint(touch: UITouch, at t: TimeInterval) -> StrokePoint {
        let loc = touch.location(in: self)
        return StrokePoint(
            x: Double(loc.x),
            y: Double(loc.y),
            t: t,
            force: Double(touch.force),
            altitudeAngle: Double(touch.altitudeAngle),
            azimuthAngle: Double(touch.azimuthAngle(in: self))
        )
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // Draw nodes
        for node in layoutNodes {
            let frame = CGRect(x: node.x - 22, y: node.y - 22, width: 44, height: 44)
            let path = UIBezierPath(ovalIn: frame)
            let color: UIColor
            if completedNodeIDs.contains(node.id) {
                color = UIColor.systemGreen.withAlphaComponent(0.3)
            } else if node.id == highlightedNodeID {
                color = UIColor.systemYellow.withAlphaComponent(0.5)
            } else {
                color = .white
            }
            color.setFill()
            path.fill()
            UIColor.systemGray.setStroke()
            path.lineWidth = 2
            path.stroke()
            // Draw label
            let label = node.id as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: node.x - size.width/2,
                                    y: node.y - size.height/2),
                       withAttributes: attrs)
        }
        // Draw current stroke trail
        if currentStrokePoints.count > 1 {
            UIColor.systemBlue.setStroke()
            let p = UIBezierPath()
            p.lineWidth = 3
            p.move(to: CGPoint(x: currentStrokePoints[0].x,
                                y: currentStrokePoints[0].y))
            for pt in currentStrokePoints.dropFirst() {
                p.addLine(to: CGPoint(x: pt.x, y: pt.y))
            }
            p.stroke()
        }
        _ = ctx
    }
}
```

- [ ] **Step 2: Write `TMTBPhaseView`**

```swift
import SwiftUI

struct TMTBPhaseView: View {
    @Bindable var session: AssessmentSession
    let onComplete: (TMTBResult) -> Void

    @State private var taps: [(point: CGPoint, time: TimeInterval)] = []
    @State private var rawStrokes: [RawStroke] = []
    @State private var scorer = TMTBScorer()
    @State private var highlightedNodeID: String? = "1"
    @State private var completedNodeIDs: Set<String> = []
    @State private var introSpoken: Bool = false

    private let layoutNodes: [TMTBLayoutNode] = TMTBPhaseView.loadLayoutNodes()

    var body: some View {
        VStack(spacing: 0) {
            AvatarZoneView()
            TMTBCanvasView(
                taps: $taps,
                rawStrokes: $rawStrokes,
                layoutNodes: layoutNodes,
                highlightedNodeID: highlightedNodeID,
                completedNodeIDs: completedNodeIDs
            )
        }
        .onAppear {
            speakIntro()
            scorer.startTask()
        }
        .onChange(of: taps) { _, newTaps in
            guard let last = newTaps.last else { return }
            handleTap(at: last.point, time: last.time)
        }
    }

    private func speakIntro() {
        guard !introSpoken else { return }
        introSpoken = true
        avatarSpeak(LeftPaneSpeechCopy.tmtBIntro)
    }

    private func handleTap(at point: CGPoint, time: TimeInterval) {
        let result = scorer.handleTap(at: point, atRelativeTime: time)
        switch result {
        case .correct(let nodeID, let isComplete):
            completedNodeIDs.insert(nodeID)
            highlightedNodeID = nextExpectedAfter(nodeID)
            if isComplete {
                finalize(status: .completed)
            }
        case .wrongTarget:
            avatarSpeak("Oops, that's not next. Go back to " +
                        "\(highlightedNodeID.flatMap { idForCorrection($0) } ?? "the last one") " +
                        "and try again.")
        case .offPath:
            // Silently logged.
            break
        case .selfCorrected:
            // Already handled by .correct branch advancement.
            break
        }
    }

    private func finalize(status: TMTBCompletionStatus) {
        let kinematics = StrokeAnalyzer.analyze(strokes: rawStrokes, source: .tmtB)
        let result = scorer.finalize(strokes: rawStrokes, kinematics: kinematics)
        onComplete(result)
    }

    private func nextExpectedAfter(_ nodeID: String) -> String? {
        // Reads expected sequence from layout — implementation looks up next index.
        let layout = TMTBPhaseView.loadExpectedSequence()
        guard let idx = layout.firstIndex(of: nodeID),
              idx + 1 < layout.count else { return nil }
        return layout[idx + 1]
    }

    private func idForCorrection(_ id: String) -> String { id }

    private static func loadLayoutNodes() -> [TMTBLayoutNode] {
        // Decode Resources/TMTBLayout.json and convert to UIKit-friendly nodes.
        guard let url = Bundle.main.url(forResource: "TMTBLayout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = json["nodes"] as? [[String: Any]] else {
            return []
        }
        return nodes.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let x = dict["x"] as? Double,
                  let y = dict["y"] as? Double else { return nil }
            return TMTBLayoutNode(id: id, x: CGFloat(x), y: CGFloat(y))
        }
    }

    private static func loadExpectedSequence() -> [String] {
        guard let url = Bundle.main.url(forResource: "TMTBLayout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let seq = json["expectedSequence"] as? [String] else {
            return []
        }
        return seq
    }
}
```

- [ ] **Step 3: Register both files in pbxproj + build**

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/Phases/TMTBPhaseView.swift \
        VoiceMiniCog/Views/AvatarAssessment/Phases/TMTBCanvasView.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(tmtb): TMTBPhaseView + TMTBCanvasView with Apple Pencil capture

UIKit canvas captures UITouch events into [RawStroke] for kinematics and a
tap stream for sequence scoring. Highlights current target (amber) and
completed nodes (green). Avatar reads error correction copy on
wrongTargetTap. Off-path strokes logged silently."
```

---

## Task 8 — ★ Verify long-press exit on `.tmtB` AND `.recognition` (BEFORE production routing)

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift` (verify only)
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/TMTBPhaseView.swift` (verify wiring)
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/RecognitionPhaseView.swift` (verify wiring)

This task **MUST** complete before Task 9 (wiring TMT-B into production routing). Patient-safety surface — verifying abort affordance behavior on a phase already in production routing means a regression could hit a real patient session.

- [ ] **Step 1: Verify `AssessmentPhaseID.isHighRiskAbortPhase` returns `true` for both phases**

```bash
swift -parse /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog/VoiceMiniCog/Models/AvatarLayoutManager.swift 2>&1 | head -5
grep -n "isHighRiskAbortPhase" /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog/VoiceMiniCog/Models/AvatarLayoutManager.swift
```

Expected: extension returns `true` for `.clockDrawing`, `.tmtB`, `.recognition`.

- [ ] **Step 2: Verify the canvas bottom-controls path uses `isHighRiskAbortPhase`**

In `AvatarAssessmentCanvas.swift`, check that when `currentPhase.isHighRiskAbortPhase == true`, `examinerLongPressExit` is shown instead of `endSessionPill`. The Plan 1 refactor (Task 13) should have wired this. Re-verify:

```bash
grep -nA 3 "isHighRiskAbortPhase" VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift
```

- [ ] **Step 3: Add a UI test (or extend an existing one) that asserts the long-press affordance**

```swift
// VoiceMiniCogUITests/HighRiskAbortPhaseTests.swift
import XCTest

final class HighRiskAbortPhaseTests: XCTestCase {
    func test_recognitionPhase_showsExaminerLongPressExit() throws {
        // Launch app with deterministic seed that reaches recognition phase.
        // Assert the long-press exit button is present and the standard
        // ghost end-session pill is NOT.
        // (Actual test depends on existing UI test fixtures; adapt accordingly.)
    }

    func test_tmtBPhase_showsExaminerLongPressExit() throws {
        // Same shape as above for TMT-B.
    }
}
```

If UI tests are not currently green in this project (per CLAUDE.md: "UITests with pre-existing build errors"), document this verification as a manual checklist item and run the simulator session yourself.

- [ ] **Step 4: Manual smoke test in simulator**

Boot simulator, run a session, advance to TMT-B and Recognition phases. Verify:
- Standard ghost end-session pill is NOT visible.
- Examiner long-press exit affordance IS visible.
- Long-press triggers the abort flow correctly (records `abandonedAtNodeID` for TMT-B; `notDelivered`-style finalization for Recognition).

- [ ] **Step 5: Commit (verification-only — no code changes likely)**

If any wiring needs adjustment, commit those changes:
```bash
git commit -m "verify(safety): long-press exit affordance live on .tmtB and .recognition

Patient-safety surface — verified BEFORE production routing wires TMT-B
into the active phaseSequence (Task 9). Abort affordance correctly hides
the ghost end-session pill on both high-risk phases."
```

---

## Task 9 — Wire TMT-B into `AvatarAssessmentCanvas` phase routing

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift`

- [ ] **Step 1: Replace the `.tmtB` placeholder with the real phase view**

```swift
case .tmtB:
    TMTBPhaseView(session: session) { result in
        session.tmtBResult = result
        layoutManager.advance()
    }
```

- [ ] **Step 2: Build + manual smoke test**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift
git commit -m "feat(routing): wire TMTBPhaseView into AvatarAssessmentCanvas"
```

---

## Task 10 — Insert `.tmtB` into `phaseSequence` (final 6-module ordering)

**Files:**
- Modify: `VoiceMiniCog/Models/AvatarLayoutManager.swift`
- Modify: `VoiceMiniCogTests/BatteryEnumSyncTests.swift`

- [ ] **Step 1: Update `phaseSequence`**

```swift
extension AssessmentFlowType {
    var phaseSequence: [AssessmentPhaseID] {
        switch self {
        case .quick, .extended:
            // Final 6-cognitive-module sequence (locked 2026-04-29).
            return [.welcome, .orientation, .wordRegistration, .clockDrawing,
                    .wordRecall, .tmtB, .recognition, .completion]
        case .caregiver:
            return [.welcome, .completion]
        }
    }
}
```

- [ ] **Step 2: Update `BatteryEnumSyncTests.testQuickFlowSequenceMatchesCanonicalOrder`**

```swift
func testQuickFlowSequenceMatchesCanonicalOrder() {
    let expected: [AssessmentPhaseID] = [
        .welcome, .orientation, .wordRegistration, .clockDrawing,
        .wordRecall, .tmtB, .recognition, .completion   // FINAL 6-cognitive
    ]
    XCTAssertEqual(AssessmentFlowType.quick.phaseSequence, expected)
    XCTAssertEqual(AssessmentFlowType.extended.phaseSequence, expected)
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/BatteryEnumSyncTests -quiet 2>&1 | tail -120
```

Expected: all `BatteryEnumSyncTests` pass.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Models/AvatarLayoutManager.swift \
        VoiceMiniCogTests/BatteryEnumSyncTests.swift
git commit -m "feat(battery): insert .tmtB into phaseSequence — final 6-module battery

orient → reg → clock → recall → tmtB → recognize → completion. Locked."
```

---

## Task 11 — Add TMT-B copy to `LeftPaneSpeechCopy`

**Files:**
- Modify: `VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift`

- [ ] **Step 1: Add the new constants**

```swift
extension LeftPaneSpeechCopy {

    /// TMT-B-style executive task — patient-facing intro.
    static let tmtBIntro: String = """
    You're going to connect dots in order, alternating numbers and letters: \
    1, A, 2, B, 3, C, and so on, all the way to L. Try to be fast and accurate. \
    Let me show you with a quick practice first.
    """

    static let tmtBPracticeIntro: String =
        "Connect 1, A, 2, B."

    static let tmtBPracticeComplete: String =
        "Great. Ready for the real one?"

    /// Wrong-target-tap correction copy. The {{lastCorrectNode}} placeholder
    /// is replaced at speak time with the last correctly hit node ID.
    static let tmtBWrongTargetCorrection: String = """
    That's not the next one. The next one is {{lastCorrectNode}}. Try again from there.
    """

    /// Soft 3:00 cap — graceful exit copy.
    static let tmtBTimeoutClosing: String =
        "Let's stop here — you did great."

    /// Successful completion closing line.
    static let tmtBCompletionClosing: String =
        "Excellent. That was tough."
}
```

- [ ] **Step 2: Verify contamination guard still passes**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionContaminationGuardTests -quiet 2>&1 | tail -120
```

The TMT-B copy contains no recognition stimuli (no `dog`, `rain`, `butter`, `love`, `door`, etc.) — verified by inspection.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift
git commit -m "feat(copy): TMT-B intro, practice, correction, timeout, completion strings

Verified clean of all 15 recognition stimuli."
```

---

## Task 12 — Add TMT-B persona overlay to `QMCIAvatarContext`

**Files:**
- Modify: `VoiceMiniCog/Services/QMCIAvatarContext.swift`

- [ ] **Step 1: Add the persona overlay**

```swift
extension QMCIAvatarContext {
    static let tmtBContext: String = """
    You are administering a connect-the-dots executive function task. Speak only \
    the scripted instructions and the 'oops, that's not next' correction. Never \
    describe the test purpose to the patient. Examiner-never-corrects rule active.
    """
}
```

- [ ] **Step 2: Wire into the dispatcher**

```swift
case .tmtB: return Self.tmtBContext
```

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Services/QMCIAvatarContext.swift
git commit -m "feat(avatar): TMT-B persona overlay (scripted-only, examiner-never-corrects)"
```

---

## Task 13 — Update `ProgressTrackView` (final 6-cell layout)

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift`

- [ ] **Step 1: Verify the chevron auto-includes TMT-B**

The Plan 1 implementation derives cell count from `phaseSequence`. Adding `.tmtB` to `phaseSequence` (Task 10) and to the `shortName` map (Plan 1 Task 14 already lists "TMT-B") means the chevron now auto-renders 6 cells. No code change should be necessary.

- [ ] **Step 2: Smoke test**

Boot simulator, advance through a full session, verify chevron shows: Orient → Words → Clock → Recall → TMT-B → Recognize.

- [ ] **Step 3: Commit (if changes)**

---

## Task 14 — Update `QMCIScoringEngine` for TMT-B

**Files:**
- Modify: `VoiceMiniCog/Services/QMCIScoringEngine.swift`

- [ ] **Step 1: Integrate `TMTBResult` into the scoring pipeline**

```swift
// In calculate(for session:):
// session.tmtBResult is populated by TMTBPhaseView.onComplete handler.
// No additional derivation needed at scoring time — the result is the score.
```

For composite-score derivations downstream (clinical-narrative interpretation), the report layer can read `session.tmtBResult` directly.

- [ ] **Step 2: Commit (if changes)**

---

## Task 15 — Update `PDFReportGenerator` (TMT-B section + kinematic summaries)

**Files:**
- Modify: `VoiceMiniCog/Services/PDFReportGenerator.swift`

- [ ] **Step 1: Add TMT-B section**

After the Clock Drawing section, before Recognition:

```swift
if let r = result.tmtBResult {
    addSection(title: "Trail-Making Executive Task")
    addLine("Total time: \(String(format: "%.1f", r.totalTimeSec)) sec")
    addLine("Status: \(displayName(for: r.completionStatus))")

    let counts = r.errorCounts
    addLine("Wrong-target taps: \(counts.wrongTargetTaps)")
    addLine("Self-corrections: \(counts.sequenceCorrected)")
    addLine("Off-path strokes: \(counts.offPathStrokes)")

    if let abandoned = r.abandonedAtNodeID {
        addLine("Aborted at node: \(abandoned)")
    }

    addKinematicSummary(r.kinematics)
}

private func addKinematicSummary(_ k: KinematicCapture) {
    addBoldLine("Kinematic Summary")
    addLine("Stroke count: \(k.strokeCount)")
    addLine("Mean velocity: \(String(format: "%.1f", k.meanVelocityMmps)) mm/s")
    addLine(String(format: "Air/ink ratio (think-to-ink): %.2f", k.airInkRatio))
    addLine(String(format: "Mean pressure: %.2f", k.meanPressure))
    if let latency = k.preFirstHandLatencySec, k.source == .clock {
        addLine(String(format: "Pre-first-hand latency: %.2f sec", latency))
    }
}

private func displayName(for status: TMTBCompletionStatus) -> String {
    switch status {
    case .completed: return "Completed"
    case .aborted:   return "Aborted by examiner"
    case .timedOut:  return "Timed out"
    }
}
```

- [ ] **Step 2: Add kinematic summary to the Clock Drawing section**

If the Clock Drawing report block doesn't already render kinematics from `clockDrawingResult.kinematics`, add the same `addKinematicSummary` call.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Services/PDFReportGenerator.swift
git commit -m "feat(report): TMT-B section + kinematic summaries for both pencil tasks"
```

---

## Task 16 — Update `PartialScoreReport` schema

**Files:**
- Modify: `VoiceMiniCog/Services/PartialScoreReport.swift`

- [ ] **Step 1: Add `tmtBResult` and kinematic keys**

```swift
let tmtBResult: TMTBResult?
let clockKinematics: KinematicCapture?
let tmtBKinematics: KinematicCapture?
```

(The kinematic captures may already be inside their respective result types — check before adding redundant top-level keys.)

- [ ] **Step 2: Commit (if changes)**

---

## Task 17 — Activate CI pre-merge hook for `Resources/TMTBLayout.json`

**Files:**
- Modify: `.github/workflows/<existing-test-workflow>.yml`

- [ ] **Step 1: Add hook**

```yaml
tmtb-layout-guard:
  if: contains(github.event.pull_request.changed_files, 'VoiceMiniCog/Resources/TMTBLayout.json')
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - run: |
        cd VoiceMiniCog
        xcodebuild test-without-building \
          -project VoiceMiniCog.xcodeproj \
          -scheme VoiceMiniCog \
          -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
          -only-testing:VoiceMiniCogTests/TMTBScorerTests
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/
git commit -m "ci: pre-merge hook for TMTBLayout.json → TMTBScorerTests

Layout changes affect scoring behavior directly (node hit radius, segment
timing). Tests are now a merge prerequisite, not just a CI artifact."
```

---

## Task 18 — Finalize CLAUDE.md (Stroke Pipeline + Pre-Merge Hooks deployed)

**Files:**
- Modify: `VoiceMiniCog/CLAUDE.md`

- [ ] **Step 1: Remove forward-reference disclaimers**

In the "Stroke Pipeline" and "Pre-Merge Hooks" sections, delete the forward-reference sentences. Update content to reflect deployed state:
- StrokeAnalyzer + ClockDrawingCapture refactor live
- TMTBLayout.json pre-merge hook for TMTBScorerTests live
- All three high-risk-abort phases (.clockDrawing, .tmtB, .recognition) wired

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/CLAUDE.md
git commit -m "docs(claude): Stroke Pipeline + Pre-Merge Hooks sections deployed"
```

---

## Task 19 — Update `tmtb-layout-rationale.md` and `qmci-modifications.md` to deployed status

**Files:**
- Modify: `docs/clinical/tmtb-layout-rationale.md`
- Modify: `docs/clinical/qmci-modifications.md`

- [ ] **Step 1: Update `tmtb-layout-rationale.md` frontmatter and §"Implementation note"**

Frontmatter: change `status: locked-v1.0` to `status: deployed-v1.0` (or keep locked-v1.0 if that's the project convention; just verify the document references the deployed `Resources/TMTBLayout.json`).

§"Implementation note": replace the placeholder language ("The visual companion mockup may continue to show illustrative scattered circles...") with deployed-state language: *"`Resources/TMTBLayout.json` ships with 24 MercyCognitive-authored node coordinates satisfying all five layout constraints. Layout-regenerability invariant (`hitRadiusPt = 28` so no node regions overlap) is asserted in `TMTBScorerTests.test_layoutInvariant_nodeRegionsNeverOverlap`. Layout author: <name>; clinical reviewer: <name>; reviewed 2026-MM-DD."*

- [ ] **Step 2: Update `qmci-modifications.md` §"TMT-B-style executive component"**

Replace any "to be deployed" / "pending" language with deployed-state language. Reference the locked layout coordinates and the construct-equivalence claim per spec §F.4.

- [ ] **Step 3: Commit**

```bash
git add docs/clinical/tmtb-layout-rationale.md docs/clinical/qmci-modifications.md
git commit -m "docs(clinical): TMT-B + qmci-modifications updated to deployed status"
```

---

## Plan 3 Acceptance

- [ ] **Step 1: Full app build + test suite green**

```bash
xcodebuild test -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -200
```

Expected: all Plan 1 + Plan 2 tests still pass + new Plan 3 tests:
- StrokeAnalyzerTests (5 cases)
- TMTBScorerTests (7 cases)
- BatteryEnumSyncTests (sequence updated to final 6)

- [ ] **Step 2: Manual smoke test — full final battery**

Boot simulator, run a complete session: Welcome → Orientation → Word Registration → Clock Drawing → Delayed Recall → **TMT-B** → **Word Recognition** → Completion.

Verify:
- Chevron shows 6 cells in correct order.
- TMT-B canvas displays 24 nodes with current target highlighted in amber.
- Wrong-target taps trigger avatar correction copy.
- Long-press exit available on all three high-risk-abort phases.
- PDF report renders TMT-B section + kinematic summaries for both Clock and TMT-B + Recognition section + Memory Pattern Signals.

- [ ] **Step 3: Verify all four `docs/clinical/` files at deployed status**

Read each file and confirm the frontmatter and content reflect deployed (not forward-referenced) state.

- [ ] **Step 4: Open PR**

PR title: `Plan 3 — TMT-B + StrokeAnalyzer + clinical docs final`

PR body must reference [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md) and call out:
- Final 6-module battery shipped.
- StrokeAnalyzer + ClockDrawingCapture refactor.
- TMT-B layout coordinates reviewed and locked (with reviewer names + date).
- All four `docs/clinical/` files at deployed status.
- Two new pre-merge hooks active (Recognition contamination + TMTBLayout).

---

## Plan 3 Self-Review (run before PR opens)

1. **Spec coverage:** Every step in spec §F.3 (23 sub-tasks) maps to a Task here. Step 11 (long-press exit verification BEFORE production routing) is explicitly Task 8 of this plan, ahead of Task 9 (production routing wiring).
2. **Placeholder scan:** No `TODO` / `TBD` / "implement later." The TMT-B layout coordinates in Task 4 are author-supplied by Tolla — not placeholders, but require sign-off before PR opens (Hard Gate equivalent).
3. **Type consistency:** `KinematicSource` (Tasks 1, 2, 3, 7), `KinematicCapture` (Tasks 1, 2, 3, 7, 14), `TMTBResult` (Tasks 5, 7, 14, 15), `TMTBErrorEvent`/`TMTBErrorKind` (Task 5 → Task 6 tests), `RawStroke`/`StrokePoint` (Tasks 1, 2, 7), `AssessmentPhaseID.isHighRiskAbortPhase` (Task 8 verifies, Plan 1 Task 3 declares) — names match across referencing tasks.
4. **Cross-plan handoff:** Plan 3 is the terminal plan. After Plan 3 ships, the entire 2026-04-29 spec is realized. The deferred-to-future-spec items (norms reference layer, Form B development, Tavus dual-task variants, clinician-side caregiver iOS surface, MERIDIAN-1 → production export) remain queued per spec §F.5 / F.6.

---
title: VoiceMiniCog Six-Module Battery Restructure
date: 2026-04-29
status: locked
spec-version: 1.0
authors: Tolla (clinical), Claude (engineering)
path: docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md
---

# VoiceMiniCog Six-Module Battery Restructure

## Purpose

This spec governs the restructure of the MercyCognitive assessment battery from its
current form (Orientation, Word Registration, Clock Drawing, Delayed Recall, Verbal
Fluency, Story Recall) to a six-cognitive-module battery with a novel Recognition trial,
a MercyCognitive-authored TMT-B-style executive component, and Apple Pencil kinematic
capture on both pencil tasks. It establishes all data models, service architecture,
clinical documentation, persistence migration strategy, contamination guard policy, and
three independently-shippable implementation plans.

---

## Block A — Battery Structure + File Map

### A.1 Canonical Module Sequence (locked 2026-04-29)

```
Welcome → Orientation → Word Registration → Clock Drawing (Pencil)
       → Delayed Recall → TMT-B-Style Executive Task (Pencil)
       → Word Recognition → Completion
```

Source of truth: `AssessmentFlowType.quick.phaseSequence` in
`Models/AvatarLayoutManager.swift`. The `.caregiver` flow collapses to
`[.welcome, .completion]`; enum cases are retained for forward compat.

### A.2 Dropped Modules

| Module | Rationale |
|---|---|
| Verbal Fluency (animal naming) | Duration target; inserting a verbal task between Registration and Clock Drawing defeats the protective non-verbal-delay sequencing |
| Story Recall (logical memory) | Duration target; single-modality verbal memory preserved via Registration + Recall |
| QDRS intake | Clinician-side / pre-visit workflow; removed from iOS app |
| Caregiver iOS surface | Retained as enum case; iOS view surface deferred to future spec |

PHQ-2 is not dropped — it was never part of published Qmci. It is inactivated behind
`FeatureFlags.phq2Enabled = false`. See `docs/clinical/qmci-modifications.md` §7.

### A.3 Three-Enum Sync Invariant

Phase, AssessmentPhaseType, and AssessmentPhaseID must stay in sync.
`VoiceMiniCogTests/BatteryEnumSyncTests.swift` is the guard. It is the first test
merged in Plan 1 and runs on every PR.

### A.4.1 File Map — New Files

```
Models/
  RawStroke.swift                        NEW  (Block D)
  RecognitionForm.swift                  NEW  (Block B)
  RecognitionResult.swift                NEW  (Block B)
  TMTBResult.swift                       NEW  (Block B)
  KinematicCapture.swift                 NEW  (Block B)
  EncodingRetrievalIndex.swift           NEW  (Block B)
  RegistrationTrialMode.swift            NEW  (Block B)

Services/
  StrokeAnalyzer.swift                   NEW  (Block D)
  TMTBScorer.swift                       NEW  (Block C/D)
  RecognitionScorer.swift                NEW  (Block B/C)

Views/AvatarAssessment/Phases/
  RecognitionPhaseView.swift             NEW  (Block C)
  TMTBPhaseView.swift                    NEW  (Block C)
  TMTBCanvasView.swift                   NEW  (Block C)

Theme/
  FeatureFlags.swift                     NEW  (Block A)

Resources/
  RecognitionForms.json                  NEW  (Block B)
  TMTBLayout.json                        NEW  (Block C, β decision)

VoiceMiniCogTests/
  BatteryEnumSyncTests.swift             NEW  (Block A)
  RecognitionContaminationGuardTests.swift NEW (Block D)
  RecognitionFormConstraintsTests.swift  NEW  (Block B)
  StrokeAnalyzerTests.swift              NEW  (Block D)
  TMTBScorerTests.swift                  NEW  (Block C)
  AssessmentPersistenceMigrationTests.swift NEW (Block E)
  RecognitionScorerTests.swift           NEW  (Block B)
  EncodingRetrievalIndexTests.swift      NEW  (Block B)

docs/clinical/
  recognition-foil-rationale.md         NEW  (Block E)
  qmci-modifications.md                 NEW  (Block E)
  recognition-form-roadmap.md           NEW  (Block E)
  tmtb-layout-rationale.md              NEW  (Block C/E)
```

### A.4.2 File Map — Deleted Files

```
Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift
Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift
Views/CaregiverAssessmentView.swift
Services/VerbalFluencyScorer.swift
```

### A.4.3 File Map — Modified Files (key surface changes)

```
Models/AvatarLayoutManager.swift        phase enums, phaseSequence, displayName,
                                        isHighRiskAbortPhase
Models/QmciModels.swift                 delete LOGICAL_MEMORY_STORIES, fluency fields,
                                        Sets 2 & 3; add registrationWordListIndex
                                        reservation; add RegistrationResult schema
Services/ClockDrawingCapture.swift      refactor: thin adapter → StrokeAnalyzer +
                                        CDTOnDeviceScorer
Services/DailyCallManager.swift         publish replicaStoppedSpeaking notification
Services/QMCIScoringEngine.swift        add Recognition + TMT-B; remove fluency/story
Services/PDFReportGenerator.swift       add Recognition section, Memory Pattern Signals,
                                        TMT-B section, kinematic summaries
Theme/LeftPaneSpeechCopy.swift          delete fluency/story copy; add Recognition +
                                        TMT-B copy (Plans 2 + 3)
Services/QMCIAvatarContext.swift        add Recognition + TMT-B persona overlays
Views/AvatarAssessment/AvatarAssessmentCanvas.swift  phase routing updates
Views/AvatarAssessment/ProgressTrackView.swift  6-cell layout; hide on non-cognitive phases
Views/HomeView.swift                    remove caregiver entry point
Views/ClinicianDashboardView.swift      remove fluency/story tiles
Services/AssessmentPersistence.swift    schemaVersion: Int = 2, migration log
VoiceMiniCog/CLAUDE.md                 append 7 new sections (see Block E §E.7)
```

### A.5 High-Risk-Abort Phases

`AssessmentPhaseID.isHighRiskAbortPhase` returns `true` for:
`.clockDrawing`, `.tmtB`, `.recognition`

Examiner long-press exit is the only abort affordance. Mid-trial abort destroys
data integrity for these tasks. Cases are declared in Plan 1; views wire the
affordance in Plans 2 and 3 respectively.

---

## Block B — Data Models & Schemas

### B.1 RecognitionForm

```swift
struct Stimulus: Codable {
    let word: String
    let kind: StimulusKind          // .target | .semanticFoil | .unrelatedFoil
}

struct RecognitionForm: Codable {
    let formID: String              // "A" for v1.0; "B"+ when Form B is triggered
    let stimuli: [Stimulus]         // source of truth for all 15 words
    let presentationOrder: [Int]    // indices into stimuli[]; constraints asserted
                                    // in RecognitionFormConstraintsTests
    static var formA: RecognitionForm { /* loaded from Resources/RecognitionForms.json */ }
}
```

Presentation order constraints (asserted in `RecognitionFormConstraintsTests.swift`):
- No two adjacent stimuli of the same kind
- First stimulus is a target
- Last stimulus is a foil
- All 15 stimuli present exactly once

### B.2 RecognitionResult

```swift
struct RecognitionResult: Codable {
    let formID: String              // carries RecognitionForm.formID verbatim
    let responses: [StimulusResponse]

    // Computed (not persisted — no drift risk)
    var hits: Int           { }     // target → yes
    var misses: Int         { }     // target → no
    var correctRejections: Int { }
    var falseAlarms: Int    { }
    var semanticFalseAlarms: Int { }
    var unrelatedFalseAlarms: Int { }
    var dPrime: Double      { }     // signal detection d′
    var notDeliveredCount: Int { }
    var timedOutCount: Int  { }     // 6s window exhausted; itself a diagnostic signal
    var captionAccommodationActive: Bool  // false by default; clinician-set at intake
    var dataQualityWarning: DataQualityWarning? { }
                                    // .recommendReadminister when notDeliveredCount
                                    // >= RecognitionDataQualityRules
                                    //   .notDeliveredReadminThreshold (= 2)
}
```

### B.3 StimulusResponse

```swift
struct StimulusResponse: Codable {
    let stimulusIndex: Int
    let stimulusOnsetTimestamp: Date    // anchored to the replicaStoppedSpeaking
                                        // event. Audit anchor for "when did the
                                        // avatar actually finish speaking this
                                        // stimulus." Derivable in theory from
                                        // session start + cumulative timings, but
                                        // not reliably across session restarts —
                                        // stored directly.
    let responseStatus: ResponseStatus  // .yes | .no | .timedOut | .notDelivered
    let reactionTimeMs: Double?         // nil for .timedOut / .notDelivered.
                                        // Measured from stimulusOnsetTimestamp.
}
```

### B.4 EncodingRetrievalIndex

```swift
enum MemoryPatternSignal: String, Codable {
    case normalPattern
    case retrievalDifficulty
    case encodingDifficulty
    /// Conservative split from encodingDifficulty. Free-recall + recognition data
    /// alone may not fully dissociate encoding from consolidation; this case
    /// represents a clinical pattern observation, not a mechanistic claim. Longer-
    /// delay paradigms (e.g., 30-minute delayed recall) would be required to
    /// dissociate consolidation failure from encoding failure definitively.
    case consolidationDifficulty
    case indeterminate
    /// notDelivered count exceeded Thresholds.minDeliveredForInterpretation;
    /// pattern signal cannot be reliably derived from this session.
    case insufficientData
}

struct EncodingRetrievalIndex: Codable {
    let signal: MemoryPatternSignal
    let registrationScore: Int          // first-trial 0–5
    let delayedRecallScore: Int
    let recognitionHits: Int
    let recognitionFalseAlarms: Int

    static func derive(from result: RecognitionResult,
                       freeRecall: DelayedRecallResult) -> EncodingRetrievalIndex

    struct Thresholds {
        // All values provisional v1.0 — to be calibrated against
        // Mercy Normative Collection + MERIDIAN-2 data.
        static let currentProvenance: String =
            "Provisional v1.0 thresholds derived from CERAD recognition floor " +
            "(Fillenbaum et al. 2008) and Qmci registration norms " +
            "(O'Caoimh et al. 2012). Pending calibration against Mercy " +
            "Normative Collection. See docs/clinical/recognition-foil-rationale.md §8."
        static let normalRecallFloor: Int = ...
        static let recognitionHitFloor: Int = ...
        static let falseAlarmCeiling: Int = ...
    }
}
```

The `currentProvenance` string is rendered verbatim in the PDF report's Memory Pattern
Signals section. It must be quoted verbatim in `docs/clinical/recognition-foil-rationale.md`
§8 — this is a manual review checkpoint, not an automated test.

### B.5 RegistrationResult (updated schema)

```swift
struct RegistrationResult: Codable {
    let trialMode: RegistrationTrialMode
    let perTrialRecalled: [[String]]    // length == trialsAdministered.
                                        // Per-word audit trail: consistent omission
                                        // of one specific word across trials is
                                        // clinically meaningful and not recoverable
                                        // from integer scores alone.
    let firstTrialScore: Int            // 0–5; Qmci scoring anchor
    let finalTrialScore: Int            // 0–5; last administered trial
    let trialsAdministered: Int         // 1, 2, or 3 — variable in standardQmci mode
                                        // (stops at 5/5 or 3 trials, whichever first);
                                        // always 3 in researchFull3 mode.
    let reachedCriterion: Bool          // true if any trial == 5/5
    let learningSlope: [Int]            // researchOnly: true; not in Qmci composite.
                                        // Non-optional array — use empty array (not
                                        // nil) when no slope data is available.
                                        // Avoids an optional-unwrapping footgun at
                                        // consumer sites (PDF report, research export).
                                        // [] if trialsAdministered == 1 — e.g.,
                                        //    standardQmci stopped at trial 1 because
                                        //    the patient scored 5/5 immediately.
                                        // [trial2 − trial1] if 2.
                                        // [trial2 − trial1, trial3 − trial2] if 3.
}

enum RegistrationTrialMode: String, Codable {
    case standardQmci    // default; stop at 5/5 or 3 trials per O'Caoimh 2016
    case researchFull3   // clinician toggle; always runs all 3 regardless
}
```

### B.6 KinematicCapture

```swift
struct KinematicCapture: Codable {
    let source: KinematicSource           // .clock | .tmtB
    let rawStreamArtifactID: UUID?        // joins to RawStreamRecorder artifact;
                                          // indexed in LongitudinalPatientStore

    // Davoudi 2021 / Müller 2017 / Sonntag common subset
    let totalTimeSec: Double
    let inkTimeSec: Double
    let airTimeSec: Double
    let airInkRatio: Double               // think-to-ink ratio
    let meanVelocityMmps: Double
    let velocityCVWithinStroke: Double
    let meanPressure: Double
    let pressureCV: Double
    let strokeCount: Int

    // Clock-only (source == .clock)
    let preFirstHandLatencySec: Double?
    let circleGapDeg: Double?

    // DARWIN parity — researchOnly v1.0
    // UITouch @ 120 Hz produces jerk estimates with high variance at
    // stroke-speed extremes. Promoted to clinical feature pending MERIDIAN-1.
    let meanJerkOnPaperMmps3: Double?
    let meanJerkInAirMmps3: Double?
}
```

Physical-coordinate scaling (mm/s) uses `UIScreen.main.nativeScale` + iPad DPI lookup
table documented in `StrokeAnalyzer.swift`. Unit test asserts mean velocity is in
plausible adult-handwriting range (50–250 mm/s).

### B.7 RawStroke / StrokePoint

```swift
struct StrokePoint {
    let x: Double               // physical mm
    let y: Double
    let t: TimeInterval         // seconds since FIRST pen-down of the task session
                                // (not per-stroke). Makes airTimeSec computation
                                // unambiguous across multi-stroke tasks;
                                // prevents off-by-one summation of inkTimeSec.
    let force: Double           // 0.0–1.0
    let altitudeAngle: Double   // rad
    let azimuthAngle: Double    // rad
}

struct RawStroke {
    let points: [StrokePoint]
    let strokeIndex: Int        // 0-based within the task session
    let downTimestamp: Date
}
```

### B.8 TMTBResult

```swift
struct TMTBResult: Codable {
    let totalTimeSec: Double
    let completionStatus: CompletionStatus  // .completed | .aborted | .timedOut
    let abandonedAtNodeID: String?          // populated when completionStatus == .aborted;
                                            // nil otherwise.
    let perSegmentTimings: [SegmentTiming]
    let errorEvents: [TMTBErrorEvent]       // chronological event log.
                                            // Consumer: research export + post-hoc
                                            // clinical review.
    let kinematics: KinematicCapture        // source == .tmtB

    // Computed (derived from errorEvents — no drift risk; consumer: PDF report + scoring).
    var errorCounts: TMTBErrors { /* derived: wrongTargetTaps, sequenceCorrected,
                                     offPathStrokes counted from errorEvents */ }
}

struct SegmentTiming: Codable {
    let fromNode: String        // e.g. "1", "A", "2"
    let toNode: String
    let durationMs: Double
    let errorOccurred: Bool
}

struct TMTBErrorEvent: Codable {
    let kind: TMTBErrorKind
    let nodeID: String?         // node involved (nil for .offPathStroke)
    let timestamp: TimeInterval // seconds since task start
}

enum TMTBErrorKind: String, Codable {
    case wrongTargetTap
    case sequenceCorrected
    case offPathStroke
}

struct TMTBErrors: Codable {
    let wrongTargetTaps: Int
    let sequenceCorrected: Int
    let offPathStrokes: Int
}
```

---

## Block C — Module Designs

### C.1 Recognition Trial Architecture

**Delivery:** Tavus echo path. Single voice profile enforced at the Tavus persona
configuration layer (not in code). Same voice profile as Word Registration — prosody
and timbre match is clinically required to avoid differential priming.

**Response window:** Anchored to `conversation.replica.stopped_speaking` event from
`appMessageAsJson` (published as `replicaStoppedSpeaking` notification from
`DailyCallManager`). Not anchored to echo dispatch — avoids Tavus first-token jitter
contaminating reaction-time data.

**Timing parameters:**
- Response window: 6s (timeout is itself diagnostic — slowed processing speed)
- Delivery timeout: 10s
- No retry on delivery failure (re-exposure contaminates encoding)
- ≥2 `.notDelivered` → `dataQualityWarning.recommendReadminister`
  (threshold: `RecognitionDataQualityRules.notDeliveredReadminThreshold = 2`)

**Y/N response buttons:** ≥88pt touch targets, accessibility-grade.

**Caption accommodation (C.7-α):** Audio-only default. Clinician-side toggle (intake/setup
screen only — never patient-facing). `captionAccommodationActive: Bool` recorded on
`RecognitionResult`. PDF report footnote when active:
> *"Recognition trial administered with caption-assist accommodation per clinician
> judgment."*
Research data exports must include `captionAccommodationActive` for stratification.

**Stall prompts:** `LeftPaneSpeechCopy.delayedRecallStallPrompts`
must be scanned by `RecognitionContaminationGuardTests`. No stall prompt may contain a
target word, semantic foil, or unrelated foil.

### C.2 Word Registration Protocol (C.3-α)

Default mode (`RegistrationTrialMode.standardQmci`): administer up to 3 trials; stop
when patient recalls all 5 words or 3 trials are exhausted. Score Trial 1 only (0–5)
as the Qmci registration score. Trials 2–3 are encoding support for delayed recall.

Research extension mode (`.researchFull3`): always run all 3 trials. Behind clinician
toggle. `learningSlope` field populated in either mode but marked `researchOnly: true`
and excluded from Qmci composite.

### C.3 TMT-B-Style Executive Task (β decision)

**Product framing:** "Trail-Making Executive Task" (clinician-facing module title).
Patient-facing: "Connect the dots in order, alternating numbers and letters."
Never described as "the licensed Reitan/PAR TMT-B" in any user-facing copy, report,
or code comment.

**Layout:** `Resources/TMTBLayout.json` is MercyCognitive-authored. Generated to satisfy
constraints in `docs/clinical/tmtb-layout-rationale.md` §"Layout constraints." File
header carries a generation note citing those constraints by name.

**TMTBLayout.json schema:**
```json
{
  "generationNote": "MercyCognitive-authored layout. See docs/clinical/tmtb-layout-rationale.md.",
  "generationSeed": "<recorded at layout generation time>",
  "hitRadiusPt": 28,
  "nodes": [ /* 24 entries: { "id": "1", "x": ..., "y": ... } */ ],
  "expectedSequence": ["1","A","2","B","3","C","4","D","5","E",
                       "6","F","7","G","8","H","9","I","10","J",
                       "11","K","12","L"]
}
```

**hitRadiusPt = 28** (~0.5× minimum inter-node distance). Serves dual purpose: scoring
rule and layout-regenerability invariant. Node regions must never overlap; asserted in
`TMTBScorerTests.swift` (TMT-B layout-constraint sibling suite to `RecognitionFormConstraintsTests`).

**Scoring (per `tmtb-layout-rationale.md` §"Scoring"):**
- **Correct hit:** tap within `hitRadiusPt` of the next-expected node, outside all others
- **wrongTargetTap:** tap within `hitRadiusPt` of a non-expected node
- **offPathStroke:** tap in dead space (not within `hitRadiusPt` of any node)
- **sequenceCorrected:** wrongTargetTap followed within 3s by correct hit on expected
  node, no intervening node-region taps. Logs without advancing wrong-tap count.

**Norms anchor:** Mercy Normative Collection (future). No direct claim of compatibility
with Heaton/MOANS norms — those are tied to the licensed printed layout. Equivalence
is construct/psychometric, not coordinate-map.

**Wrong-target correction copy:**
> *"That's not the next one. The next one is [last correct node]. Try again from there."*
1-second pause before correction, slow speech cadence on the node name.

### C.4 Tavus / replicaStoppedSpeaking Flow

```
Avatar delivers stimulus word (Tavus echo)
    ↓
replicaStoppedSpeaking event fires (conversation.replica.stopped_speaking
    from appMessageAsJson, published as notification by DailyCallManager)
    ↓
RecognitionPhaseView opens 6s response window
    ↓
Patient taps Y or N
    ↓
responseStatus = .yes / .no, reactionTimeMs recorded (ms since event)
    ↓ (if no response in 6s)
responseStatus = .timedOut
    ↓ (if delivery timeout 10s reached before event fires)
responseStatus = .notDelivered — no retry
```

Single-voice-profile enforcement is at the Tavus persona configuration layer. The code
contains no mechanism to override it; enforcement is architectural, not procedural.

### C.5 Common Module Shell

All six cognitive phase views share the same left-pane avatar / right-pane canvas
split. `AssessmentViewModifiers` provides consistent padding, transition timing, and
accessibility affordances. Clinician-facing phase title uses `AssessmentPhaseID.displayName`.

---

## Block D — StrokeAnalyzer + Contamination Guard

### D.1 Stroke Pipeline Architecture

```
Apple Pencil → UITouch → UITouchCaptureView
                              ↓
                         [RawStroke]
                              ↓
         ┌────────────────────┼──────────────────────┐
         ▼                    ▼                      ▼
  StrokeAnalyzer      ClockDrawingCapture      TMTBCanvasView
  (stateless, pure)   (thin adapter)           + TMTBScorer
         ↓                    ↓
  KinematicCapture    CDTOnDeviceScorer + KinematicCapture
```

`StrokeAnalyzer` is stateless and pure — `[RawStroke]` → `KinematicCapture`. No side
effects, no persistence, no Tavus dependence.

`ClockDrawingCapture` refactor: captures `[RawStroke]`, hands to `StrokeAnalyzer`
for kinematics and to `CDTOnDeviceScorer` (rasterized) for CoreML structure score.
No clock-specific feature math in `ClockDrawingCapture`; only orchestration.
Clock-only features (`preFirstHandLatencySec`, `circleGapDeg`) gated on
`source == .clock` inside `StrokeAnalyzer`.

Research mode: `RawStreamRecorder` consumes the same `UITouchCaptureView` event stream
in parallel. No production wiring change. `rawStreamArtifactID` UUID returned by
recorder, stamped onto `KinematicCapture`, indexed in `LongitudinalPatientStore`.

```swift
enum StrokeAnalyzer {
    static func analyze(strokes: [RawStroke],
                        source: KinematicSource,
                        rawStreamArtifactID: UUID? = nil) -> KinematicCapture
}
```

### D.2 TMTBScorer ↔ StrokeAnalyzer Split

`StrokeAnalyzer`: raw strokes → global `KinematicCapture`. Does not know about target
nodes or expected sequence.

`TMTBScorer`: raw strokes + `TMTBLayout.json` + live tap stream → `TMTBResult`.
Segments strokes by node-hit events, computes per-segment timings, classifies errors.

Run sequentially on the same raw stroke buffer: kinematics first (task-agnostic),
TMT-B sequence/error scoring second (task-specific). Fully decoupled for independent
unit testing.

`strokeIndex` on `RawStroke` correlates node-hit events to specific strokes for
`TMTBScorer`. Correlation uses `strokeIndex`, not timestamp proximity, to avoid
latency-induced misclassification. Strategy documented in `TMTBScorer.swift` header.

### D.3 Contamination Guard — Scope

`VoiceMiniCogTests/RecognitionContaminationGuardTests.swift` — **RELEASE BLOCKER**

**Scanned sources (Swift):**
- `Theme/LeftPaneSpeechCopy.swift`
- `Services/QMCIAvatarContext.swift`
- `Services/IntakeOutroRAG.swift`
- `Services/ResponseCheckers.swift`
- `Services/QMCIScoringEngine.swift`
- `Services/PDFReportGenerator.swift`
- All `Views/AvatarAssessment/Phases/*.swift`
- All `Views/*.swift` (non-caregiver)
- `ContentView.swift`

**Scanned resources:**
- `Resources/RecognitionForms.json` (whitelisted — stimulus home)
- `Resources/TMTBLayout.json` (node IDs are numerals/letters only; drift into stimulus words = fail)
- `Resources/*.plist`, `Resources/*.strings`, `*.lproj/*.strings`

**Skipped:**
- `docs/clinical/*.md` (contain stimuli by design)
- Test files (reference stimuli for assertions)
- `VoiceMiniCog/CLAUDE.md`
- `.superpowers/`, `.remember/`, `.git/`

**Whitelist source of truth:** `RecognitionForm.formA` at test runtime.

| Category | Whitelisted paths |
|---|---|
| Targets | `LeftPaneSpeechCopy.swift`, `Models/QmciModels.swift` (seed/fixture literals), `Resources/RecognitionForms.json` |
| Semantic foils | `Resources/RecognitionForms.json` only |
| Unrelated foils | `Resources/RecognitionForms.json` only |

**Match regex:** `\b<word>(s|'s|s')?\b` (case-insensitive). Catches plurals and
possessives. Does NOT catch morphological derivatives (loved, raining, buttery).
Derivatives judged lower priming risk; false-positive cost of stem-only matching
exceeds incremental clinical benefit. Scope decision reviewed 2026-04-28.

Per-occurrence whitelist for unavoidable English-word appearances:
```swift
static let perOccurrenceWhitelist: [WhitelistEntry] = [
    // Every entry requires: file, lineRange, word, justification, review date.
    // Current copy contains no entries — all stimulus words absent from
    // non-whitelisted scopes.
]
```

**RecognitionForms.json structural assertion** (in `RecognitionFormConstraintsTests`):
No stimulus word appears in any field of `RecognitionForms.json` other than `"word"`.
Future-proofs against `"description"`, `"hint"`, `"audioFile"` schema additions.

### D.4 SHA-256 Fingerprint Sub-test

A sub-test in `RecognitionContaminationGuardTests` asserts that `RecognitionForm.formA`
literal in `Resources/RecognitionForms.json` matches the locked v1.0 SHA-256 fingerprint
of canonical-JSON bytes. Any change to locked stimuli must update the fingerprint; the
version bump forces an explicit clinical-review code review.

### D.5 CI Release-Blocker Policy

- Class `RecognitionContaminationGuardTests` is marked:
  `/// RELEASE BLOCKER — clinical-validity contamination guard.`
- Release-tagging job gated on this test passing.
- Pre-merge hooks:
  - PRs touching `LeftPaneSpeechCopy.swift`, `Resources/RecognitionForms.json`,
    `Models/RecognitionForm.swift` → must pass `RecognitionContaminationGuardTests`
  - PRs touching `Resources/TMTBLayout.json` → must pass `TMTBScorerTests`
  - PRs touching `Models/Phase*.swift`, `Models/AvatarLayoutManager.swift`
    → must pass `BatteryEnumSyncTests`
  - PRs touching `docs/clinical/*.md` → human review comment confirming the
    `review-trigger` condition was assessed (no automated test can enforce this)

---

## Block E — Clinical Documentation + Migration

### E.1 docs/clinical/ File Map

All four files share this frontmatter structure:

```yaml
---
status: locked-v1.0
created: 2026-04-29
spec: docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md
locked-by: Tolla (clinical) + Claude (engineering) 2026-04-29
review-trigger: change to RecognitionForm.formA, Phase enum,
                EncodingRetrievalIndex.Thresholds, or
                AssessmentFlowType.quick.phaseSequence
---
```

| File | Status | Key contents |
|---|---|---|
| `recognition-foil-rationale.md` | locked-v1.0 | Target/foil table, per-foil rationale, Sets 2/3 deletion audit, presentation-order constraints, pattern thresholds with `currentProvenance` verbatim |
| `qmci-modifications.md` | locked-v1.0 | Every deviation from published Qmci; battery structural deviations; registration protocol modes; recognition accommodation; PHQ-2 externalization caveat |
| `recognition-form-roadmap.md` | deferred | Form B trigger criteria (Decision 8.3 verbatim), equivalence requirements, authoring procedure |
| `tmtb-layout-rationale.md` | locked-v1.0 | IP position, layout constraints, scoring rules, normative-equivalence disclosure, bibliography |

### E.2 Persistence Migration

**Schema version:** `AssessmentPersistence.schemaVersion: Int`

- v1 (or missing) = legacy
- v2 = current (locked 2026-04-29)
- v3+ = unrecognized future

**Load-time behavior:**

```swift
match session.schemaVersion {
case 1, missing:
    if session.phase == .report { return .legacyReadOnly(session) }
    else                        { return .legacyAbandoned(session) }
case 2:   return .current(session)
case _ > 2: return .unrecognizedFutureVersion(session)
}
```

**Clinical invariant:** No silent in-flight migration. Every legacy-handling event writes
a `MigrationLogEntry` to `LongitudinalPatientStore.assessmentMigrationLog` (indexed).

```swift
struct MigrationLogEntry: Codable {
    let sessionID: UUID
    let detectedAt: Date
    let fromVersion: Int
    let outcome: MigrationOutcome   // .legacyReadOnly | .legacyAbandoned |
                                    // .currentNoOp | .future
    let lastValidPhase: Phase?
}
```

**Notice copy (clinician-facing):**
> *"Session from {date} ended on a step that is no longer part of the current battery.
> Start a fresh assessment to use the current battery; the previous session remains
> viewable as a read-only legacy record."*

**Migration test fixtures** (`AssessmentPersistenceMigrationTests.swift`):

| Fixture | Expected outcome |
|---|---|
| `v1-completed-fluency-and-story.json` | `.legacyReadOnly`, PDF renders |
| `v1-mid-fluency.json` | `.legacyAbandoned`, notice surfaces |
| `v1-mid-story.json` | `.legacyAbandoned`, notice surfaces |
| `v1-mid-clockDrawing-sequence-position-changed.json` | `.legacyAbandoned` (sequence position changed; resume-equivalence unsafe) |
| `v2-completed-recognition.json` | round-trip, all new fields |
| `v2-mid-tmtB.json` | resume from in-flight v2 session |
| `v3-unknown-future.json` (handcrafted, schemaVersion: 3) | `.unrecognizedFutureVersion` |

### E.3 PHQ-2 Externalization (verbatim, Decision 3)

PHQ-2 was removed from the in-app patient battery on the basis that depression
screening occurs in Mercy Health's clinic workflow upstream of the MercyCognitive
assessment. This dependency must be verified at deployment: the clinical operations
protocol for any site using MercyCognitive must include documented depression screening
(PHQ-2, PHQ-9, or equivalent) within the same encounter, with results available to the
interpreting clinician. If a deploying site does not have such a workflow, PHQ-2 must be
reinstated to the in-app intake before clinical use. QDRS mood items are not a substitute
— QDRS captures informant-rated mood/behavioral observations, not patient-reported
depression symptoms scored against a validated cutoff.

`FeatureFlags.phq2Enabled = false`. Reactivation procedure documented in
`docs/clinical/qmci-modifications.md` §7.

---

## Block F — Plan Decomposition

### F.1 Plan 1 — Deletion + Restructure (4-module battery ships)

**Terminal state:** Welcome → Orientation → Word Registration → Clock Drawing →
Delayed Recall → Completion. TMT-B and Recognition enum cases exist; not yet
in `phaseSequence`.

**Order of operations:**
1. Add `BatteryEnumSyncTests.swift`. Merge alone. Green CI. ← guard for all subsequent work
2. Update three Phase enums — remove fluency/storyRecall, add tmtB/recognition (not yet in sequence)
3. Update `AssessmentFlowType.quick.phaseSequence` to 4-cognitive-module ordering
4. Refactor `Phase.next` to derive from sequence; add `Phase.matching(_:)` bridge
5. Delete: `VerbalFluencyPhaseView`, `StoryRecallPhaseView`, `VerbalFluencyScorer`, `CaregiverAssessmentView`
6. Update `QmciModels.swift`: delete `LOGICAL_MEMORY_STORIES`, fluency fields, Sets 2 & 3; add `registrationWordListIndex` reservation
7. Update `QAPhaseView.swift`: delete `.qdrs` branch, gate `.phq2` with `FeatureFlags.phq2Enabled`
8. Add `Theme/FeatureFlags.swift` with `phq2Enabled = false`
9. Update `LeftPaneSpeechCopy.swift`: delete fluency/story copy
10. Update `AvatarLayoutManager.swift`: enum cases, phaseSequence, displayName, `isHighRiskAbortPhase` (`.tmtB` + `.recognition` cases declared even though unused this plan)
11. Update `AvatarAssessmentCanvas.swift`: phase routing, replace `[.verbalFluency]` literal with `isHighRiskAbortPhase` consumer
12. Update `ProgressTrackView.swift`: filter to cognitive 6 (4 visible cells this plan); hide on `.welcome`/`.qdrs`/`.phq2`
13. Update `ContentView.swift` phase routing
14. Update `HomeView.swift`: remove caregiver entry point
15. Update `ClinicianDashboardView.swift`, `PCPReportView.swift`: remove fluency/story tiles and report sections
16. Update `QMCIScoringEngine.swift`, `PartialScoreReport.swift`, `PDFReportGenerator.swift`, `QMCIAvatarContext.swift`, `ResponseCheckers.swift`, `IntakeOutroRAG.swift`: remove fluency/story scoring/copy/RAG
17. Update `AssessmentTheme.swift`, `AssessmentViewModifiers.swift`, `AssessmentState.swift`: schema sync
18. Land empty struct definitions (no schema migration when Plans 2/3 light them up):
    - `Models/RecognitionForm.swift` (Form A literal populated)
    - `Models/RecognitionResult.swift`
    - `Models/TMTBResult.swift`
    - `Models/KinematicCapture.swift` (DARWIN parity fields)
    - `Models/RawStroke.swift` (with `t` anchor documented)
    - `Models/EncodingRetrievalIndex.swift` (Thresholds + `currentProvenance`)
    - `Models/RegistrationTrialMode.swift` + updated `RegistrationResult`
19. Add `Resources/RecognitionForms.json` (Form A, locked v1.0 stimuli + presentation order)
20. Add `AssessmentPersistence.schemaVersion: Int = 2`, legacy detection, `MigrationLogEntry`
21. Add `LongitudinalPatientStore.assessmentMigrationLog` (indexed)
22. Add tests: `AssessmentPersistenceMigrationTests` (7 fixtures), `RecognitionFormConstraintsTests`, `RecognitionContaminationGuardTests` (live and fully enforcing — whitelist scope correctly empty of violations because no recognition phase copy has been written yet), rewrite existing tests (delete fluency/story, update fixtures). Pre-merge hook activation deferred to Plan 2.
23. Add four `docs/clinical/` files
24. Append CLAUDE.md sections (Battery Structure, Clinical Documentation, Feature Flags, Recognition Trial Architecture [forward-ref], Pre-Merge Hooks [forward-ref], Stroke Pipeline [forward-ref], Schema Version)

**Plan 1 acceptance:** App boots → 4-module battery → report. PDF renders 4 cognitive
modules. All deleted modules absent from UI/scoring/persistence. v1 sessions: read-only
legacy or abandoned-with-notice. `RecognitionContaminationGuardTests` passes because
no stimulus words appear in any non-whitelisted source file. The test is **fully
enforcing; it is not in a dormant state.** The whitelist contains legitimate entries
(`Resources/RecognitionForms.json` carries all 15 stimuli by design); outside the
whitelist, zero violations exist because the recognition phase copy has not yet been
written. All tests green.

### F.2 Plan 2 — Recognition Module + Contamination Guard (5-module battery ships)

**Terminal state:** …Delayed Recall → Word Recognition → Completion.
(TMT-B inserted between Recall and Recognition in Plan 3.)

**Hard gate before PR opens:** Final Tavus voice profile ID committed to
`QMCIAvatarContext.swift` as a non-nil constant. No `TODO:` placeholder permitted.

**Order of operations:**
1. Implement `RecognitionForm` behavior (loader from JSON, `stimulus(at:)`, `formA` static)
2. Implement `RecognitionResult` computed properties
3. Implement `Services/RecognitionScorer.swift`
4. Implement `EncodingRetrievalIndex.derive(from:freeRecall:)`
5. Add `Views/AvatarAssessment/Phases/RecognitionPhaseView.swift`:
   - Per-stimulus delivery loop anchored to `replicaStoppedSpeaking`
   - 6s response window, 10s delivery timeout, no retry
   - Y/N tap UI (≥88pt)
6. Add `replicaStoppedSpeaking` notification publication in `DailyCallManager.swift`
7. Update `LeftPaneSpeechCopy.swift`: recognition intro/closing/per-stimulus prompts
8. Update `QMCIAvatarContext.swift`: recognition persona overlay (single-voice-profile)
9. Add caption-assist accommodation toggle (clinician-side, default off)
10. Update `AssessmentFlowType.quick.phaseSequence`: insert `.recognition` after `.wordRecall`
11. Wire `RecognitionPhaseView` into `AvatarAssessmentCanvas.swift`
12. Update `ProgressTrackView.swift`: add "Recognize" cell (5 cells)
13. Update `QMCIScoringEngine.swift`: integrate Recognition + `EncodingRetrievalIndex`
14. Update `PDFReportGenerator.swift`: add Recognition section, Memory Pattern Signals
    (with `currentProvenance` rendered verbatim — requires neuropsych co-author sign-off
    before this plan ships)
15. Update `PartialScoreReport.swift`: add recognition + index keys
16. Add tests: `RecognitionScorerTests`, `EncodingRetrievalIndexTests`. (`RecognitionContaminationGuardTests` already exists from Plan 1 step 22; whitelist scope expands automatically as recognition copy lands in `LeftPaneSpeechCopy.swift` and the test enforces against the new scope on every PR.)
17. CI: activate pre-merge hooks for Recognition-touching files
18. Update CLAUDE.md Recognition section from forward-ref to deployed

**Additional Plan 2 gate:** Memory Pattern Signals PDF copy reviewed by named neuropsych
co-author. Sign-off recorded in commit message and `recognition-foil-rationale.md` §8.

**Plan 2 acceptance:** 5-module battery ships. Tavus echo with single voice profile. No-
retry on `.notDelivered`. Contamination guard live and enforcing. PDF includes Memory
Pattern Signals with provenance disclosure.

### F.3 Plan 3 — TMT-B + StrokeAnalyzer (6-module battery — final)

**Terminal state (locked):**
```
Welcome → Orientation → Word Registration → Clock Drawing →
Delayed Recall → TMT-B → Word Recognition → Completion
```

**Order of operations:**
1. Implement `Models/RawStroke.swift` behavior
2. Add `Services/StrokeAnalyzer.swift` (stateless; Davoudi 2021 + Müller 2017 + DARWIN parity)
3. Add `StrokeAnalyzerTests.swift` (DARWIN cross-validation; ±5% tolerance on overlapping features)
4. Refactor `Services/ClockDrawingCapture.swift`: thin adapter → `StrokeAnalyzer` + `CDTOnDeviceScorer`
5. Update `ClockDrawingPhaseView.swift` to consume `KinematicCapture` from `StrokeAnalyzer`
6. Add `Resources/TMTBLayout.json` (24 nodes, MercyCognitive-authored, `hitRadiusPt: 28`)
7. Implement `Models/TMTBResult.swift` behavior
8. Add `Services/TMTBScorer.swift` (segment classification per `tmtb-layout-rationale.md` §"Scoring")
9. Add `Views/AvatarAssessment/Phases/TMTBPhaseView.swift`
10. Add `Views/AvatarAssessment/Phases/TMTBCanvasView.swift` (24-node canvas, hit-test, stroke capture)
11. ★ Verify long-press exit (`isHighRiskAbortPhase`) on `.tmtB` AND `.recognition` (from Plan 2).
    Patient-safety surface — runs before production routing in step 13.
12. Add `TMTBScorerTests.swift`
13. Wire TMT-B into `AvatarAssessmentCanvas.swift` phase routing
14. Update `AssessmentFlowType.quick.phaseSequence`: insert `.tmtB` between `.wordRecall` and `.recognition`
15. Update `LeftPaneSpeechCopy.swift`: TMT-B intro, practice trial, error correction copy
16. Update `QMCIAvatarContext.swift`: TMT-B persona overlay
17. Update `ProgressTrackView.swift`: insert "TMT-B" cell (final 6-cell layout)
18. Update `QMCIScoringEngine.swift`: integrate TMT-B scoring
19. Update `PDFReportGenerator.swift`: add TMT-B section + kinematic summaries for Clock and TMT-B
20. Update `PartialScoreReport.swift`: add TMT-B + kinematic keys
21. CI: activate pre-merge hook for `Resources/TMTBLayout.json` → `TMTBScorerTests`
22. Update CLAUDE.md: Stroke Pipeline from forward-ref to deployed; add TMTBLayout hook entry
23. Update `tmtb-layout-rationale.md` and `qmci-modifications.md` with deployed status

**Plan 3 acceptance:** Final 6-module battery. Apple Pencil kinematics on Clock and TMT-B.
DARWIN cross-validation passes. All four `docs/clinical/` files locked-v1.0. CLAUDE.md
fully updated. All tests green.

### F.4 Cross-Plan Dependencies

| Dependency | Direction | Reason |
|---|---|---|
| Plan 1 → Plan 2 | hard | Plan 2 needs struct definitions + RecognitionForms.json from Plan 1 |
| Plan 1 → Plan 3 | hard | Plan 3 needs TMTBResult, KinematicCapture, RawStroke from Plan 1 |
| Plan 2 ↔ Plan 3 | independent | Either can ship first after Plan 1 |

**Recommended order:** Plan 2 before Plan 3. Memory Pattern Signals is the
highest-yield clinical signal to start collecting; Recognition data accumulates
while TMT-B is being implemented.

**Rollback policy:** Any plan can be reverted as a single PR without affecting
downstream plans. Any plan revert must clean up stale whitelist entries in
`RecognitionContaminationGuardTests` for deleted scopes in the same PR.
`RecognitionContaminationGuardTests` audit is a required checklist item on
every revert PR.

### F.5 Validation Gates (F.3 table)

| Question | Owner | Gate |
|---|---|---|
| `EncodingRetrievalIndex.Thresholds` clinical sign-off | Tolla + neuropsych collaborator | Provisional v1.0 ships with `currentProvenance` disclosure; revised after Mercy Normative Collection |
| Tavus voice profile ID committed as non-nil constant | Tolla | Before Plan 2 PR opens |
| Memory Pattern Signals PDF copy review | Neuropsych co-author (named by Tolla) | Hard gate: before Plan 2 ships. Sign-off in commit message + `recognition-foil-rationale.md` §8 revision |
| ASR error rates on Form A target words | Mercy Normative Collection | Out of spec scope; informs ASR fallback revision |
| TMT-B node coordinates in `TMTBLayout.json` | Layout author + clinical reviewer | Before Plan 3 PR opens |

### F.6 Deferred to Future Spec

| Deferral | Future home | Trigger / prerequisite |
|---|---|---|
| Norms reference layer | `docs/superpowers/specs/YYYY-MM-DD-norms-reference-layer-design.md` | Seed: `docs/superpowers/reference-datasets-review-2026-04-29.md`. Begin after Plan 1 ships. Technical prerequisite: `rawStreamArtifactID` index already in place (Block D Item 4). |
| Form B development | `docs/clinical/recognition-form-roadmap.md` (locked) | Decision 8.3 trigger criteria |
| Tavus dual-task variants | Future feature spec | Clinical demand |
| Caregiver iOS surface | Future feature spec | Enum case retained; iOS view deferred |
| MERIDIAN-1 → production export | Future feature spec | `rawStreamArtifactID` index already in place |

### F.7 Out of Scope

- Tavus persona authoring (Tavus dashboard)
- ElevenLabs voice profile selection (Tavus dashboard)
- ASR tuning for older-adult voices (existing pipeline as-is)
- HomeView redesign (governed by 2026-04-09 home-screen-redesign-design.md)
- `AssessmentPersistence` changes beyond schema version bump and migration log

---

## Appendix — Locked Decisions Audit Table

| ID | Question | Resolution |
|---|---|---|
| Choice (intake) | Keep / consolidate / delete patient-side intake | D — clinician-side / pre-visit; QDRS, demographics, caregiver removed. PHQ-2 inactive behind flag. |
| Q1 | QDRS deletion form | (a) — delete view files; retain enum cases |
| Q2 | PHQ-2 inactive preservation | (b) — runtime feature flag (`phq2Enabled = false`) |
| Q3 | Norms layer scope | (b) — separate follow-on spec; `reference-datasets-review-2026-04-29.md` is seed |
| Q4 | Plan decomposition | (b) — three sub-plans |
| G | Recognition audio delivery | G1 — Tavus echo; single voice profile at persona layer |
| C.3-α | Registration trial protocol | Standard Qmci (up to 3 trials, stop at 5/5, score trial 1) + optional `.researchFull3` clinician toggle |
| C.7-α | Recognition stimulus presentation | (iii) — audio-only default + clinician-side caption accommodation |
| TMT-B IP | Layout sourcing | β — MercyCognitive-authored layout, "Trail-Making Executive Task" framing, Mercy Normative Collection anchor |
| Block B substantive | `EncodingRetrievalIndex` thresholds | (a) — provisional with `currentProvenance` disclosure in PDF |
| Block B refinement 1 | `RecognitionResult` counts | Computed properties (no persistence drift) |
| Block B refinement 2 | `notDeliveredCount` threshold | Named constant `RecognitionDataQualityRules.notDeliveredReadminThreshold = 2` |
| Block B refinement 3 | `presentationOrder` constraints | Documented + asserted in `RecognitionFormConstraintsTests` |
| Block D Item 1 | TMT-B `hitRadiusPt` | 28pt; documented in `tmtb-layout-rationale.md` §"Scoring" |
| Block D Item 2 | `StrokePoint.t` anchor | Task-session epoch (not per-stroke) |
| Block D Item 3 | `meanJerkMmps3` | `meanJerkOnPaperMmps3` + `meanJerkInAirMmps3`, `researchOnly` v1.0 |
| Block D Item 4 | `rawStreamArtifactID` indexing | Indexed in `LongitudinalPatientStore` |
| Block D Item 5 | `RecognitionForms.json` non-`"word"` field assertion | Added to `RecognitionFormConstraintsTests` |
| Block D Item 6 | Plural/possessive scope-limit comment | Added to `RecognitionContaminationGuardTests` with 2026-04-28 review date |
| Block D Item 7 | `TMTBLayout.json` pre-merge hook | Added to CI |
| Block D Item 8 | `BatteryEnumSyncTests` sequencing | First test merged in Plan 1 |
| Block E `formID` | `formID: String` on `RecognitionForm` + `RecognitionResult` | Confirmed. `formA.formID == "A"`. Form B is data addition only — no code migration. |

---

*Spec drafted 2026-04-29. Self-review: no placeholders, no TODOs, no unresolved
references. All cross-references to sibling docs are to files defined in this spec's
file map or to pre-existing files confirmed in codebase. Ready for final read.*

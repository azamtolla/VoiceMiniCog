# Plan 2 — Recognition Module + Contamination Guard Activation (5-Module Battery Ships)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Word Recognition Trial as Module 5 of the cognitive battery: Welcome → Orientation → Word Registration → Clock Drawing → Delayed Recall → **Word Recognition** → Completion. Wire the Tavus delivery flow anchored to `replicaStoppedSpeaking`, populate the Plan-1 struct stubs with full behavior, surface the Memory Pattern Signals report block with provenance disclosure, and activate `RecognitionContaminationGuardTests` as a pre-merge hook for Recognition-touching files.

**Architecture:** Recognition stimuli are delivered through Tavus echo with the same single voice profile as Word Registration (timbre/prosody match across encoding ↔ recognition is enforced at the Tavus persona configuration layer). Each stimulus's response window opens on the `conversation.replica.stopped_speaking` event from `appMessageAsJson` (published as `replicaStoppedSpeaking` notification by `DailyCallManager`) — this anchors reaction-time data to the avatar's actual speech end, not echo dispatch, eliminating Tavus first-token jitter. Tavus delivery failures mark the stimulus `.notDelivered` with no retry (re-exposure would contaminate encoding); ≥2/15 not-delivered triggers `dataQualityWarning.recommendReadminister`. The PDF report's new "Memory Pattern Signals" section renders `EncodingRetrievalIndex.signal` alongside the verbatim provisional-thresholds provenance string.

**Tech Stack:** Swift, SwiftUI, iOS 16+, Daily Client iOS SDK (existing), Tavus REST + Interactions Protocol (existing).

**Spec source of truth:** [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md)

**Branch:** `v1-pilot` → `plan-2-recognition-module` (off Plan 1 merge)

---

## Hard Gates Before PR Opens

### Gate 1 — Tavus voice profile ID committed
The final Tavus voice profile ID **MUST** be committed to `QMCIAvatarContext.swift` as a non-nil String constant before the Plan 2 PR is opened (not before merge — before *open*).

```swift
/// Tavus voice profile ID for the MercyCognitive single-voice-profile
/// invariant. Same profile drives Word Registration and Word Recognition —
/// timbre/prosody match across encoding ↔ recognition is clinically required
/// to avoid differential-priming artifacts.
static let mercyCognitiveVoiceProfileID: String = "<insert before PR opens>"
```

No `TODO:` placeholder permitted in an open PR. If the ID is unavailable when work begins, pause the PR and obtain it from Tolla.

### Gate 2 — Memory Pattern Signals PDF copy reviewed
The PDF report's new "Memory Pattern Signals" section copy **MUST** be reviewed by the named neuropsych co-author (per Tolla's nomination) before Plan 2 ships. Sign-off recorded in:
- The merge commit message (e.g., `Reviewed-by: <Name>, <Title>, on 2026-MM-DD`)
- A revision in `docs/clinical/recognition-foil-rationale.md` §"Pattern thresholds" recording the reviewer name and date

Plan 2 PR cannot merge without both signatures present.

---

## Build / Test Commands

Same as Plan 1.

---

## Task 1 — Implement `RecognitionForm.formA` JSON loader

**Files:**
- Modify: `VoiceMiniCog/Models/RecognitionForm.swift`

- [ ] **Step 1: Replace the stub `formA` static**

```swift
extension RecognitionForm {
    /// Loaded once from Resources/RecognitionForms.json.
    /// Crash on load failure is intentional: missing the JSON in the bundle
    /// is a build-pipeline error, not a runtime condition we should attempt
    /// to recover from.
    static let formA: RecognitionForm = {
        guard let url = Bundle.main.url(forResource: "RecognitionForms",
                                        withExtension: "json") else {
            fatalError("RecognitionForms.json not found in app bundle. " +
                       "Verify Resources/RecognitionForms.json is registered " +
                       "in the VoiceMiniCog target's resources build phase.")
        }
        do {
            let data = try Data(contentsOf: url)
            let allForms = try JSONDecoder().decode([String: RecognitionForm].self,
                                                    from: data)
            guard let formA = allForms["A"] else {
                fatalError("RecognitionForms.json missing key 'A'.")
            }
            assert(formA.stimuli.count == RecognitionForm.stimulusCount)
            return formA
        } catch {
            fatalError("Failed to decode RecognitionForms.json: \(error)")
        }
    }()
}
```

- [ ] **Step 2: Update the test placeholder fingerprint**

In `VoiceMiniCogTests/RecognitionFormConstraintsTests.swift`, lift the `XCTSkip` from `test_formA_matchesLockedFingerprint` and finalize the fingerprint:

```swift
// Run a one-shot helper to compute the SHA-256 of the canonical-JSON bytes:
let url = Bundle.main.url(forResource: "RecognitionForms", withExtension: "json")!
let data = try Data(contentsOf: url)
let computed = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
print(computed)   // copy this hex into formAFingerprint and lock
```

Then update the constant:
```swift
private static let formAFingerprint: String = "<computed-hex-from-above>"
```

- [ ] **Step 3: Run constraints tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionFormConstraintsTests -quiet 2>&1 | tail -120
```

Expected: 7 tests pass (the previously skipped fingerprint test now passes).

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Models/RecognitionForm.swift \
        VoiceMiniCogTests/RecognitionFormConstraintsTests.swift
git commit -m "feat(recognition): wire RecognitionForm.formA JSON loader + lock fingerprint"
```

---

## Task 2 — Implement `RecognitionResult` computed properties

**Files:**
- Modify: `VoiceMiniCog/Models/RecognitionResult.swift`

- [ ] **Step 1: Replace the stub computed properties**

Computed properties consult `RecognitionForm.formA.stimuli[response.stimulusIndex].kind` to classify each response:

```swift
extension RecognitionResult {
    private func stimulusKind(at index: Int) -> RecognitionStimulusKind {
        RecognitionForm.formA.stimuli[index].kind
    }

    var hits: Int {
        responses.filter {
            $0.responseStatus == .yes && stimulusKind(at: $0.stimulusIndex) == .target
        }.count
    }

    var misses: Int {
        responses.filter {
            $0.responseStatus == .no && stimulusKind(at: $0.stimulusIndex) == .target
        }.count
    }

    var correctRejections: Int {
        responses.filter {
            $0.responseStatus == .no && stimulusKind(at: $0.stimulusIndex) != .target
        }.count
    }

    var falseAlarms: Int { semanticFalseAlarms + unrelatedFalseAlarms }

    var semanticFalseAlarms: Int {
        responses.filter {
            $0.responseStatus == .yes && stimulusKind(at: $0.stimulusIndex) == .semanticFoil
        }.count
    }

    var unrelatedFalseAlarms: Int {
        responses.filter {
            $0.responseStatus == .yes && stimulusKind(at: $0.stimulusIndex) == .unrelatedFoil
        }.count
    }

    var notDeliveredCount: Int {
        responses.filter { $0.responseStatus == .notDelivered }.count
    }

    var timedOutCount: Int {
        responses.filter { $0.responseStatus == .timedOut }.count
    }

    /// Signal-detection d′ over delivered stimuli only.
    /// Hit rate = hits / 5 targets. False-alarm rate = falseAlarms / 10 foils.
    /// Apply Hautus (1995) loglinear adjustment for boundary cases (rate = 0 or 1):
    ///   rate' = (count + 0.5) / (max + 1)
    var dPrime: Double {
        let h = (Double(hits) + 0.5) / (5.0 + 1.0)
        let f = (Double(falseAlarms) + 0.5) / (10.0 + 1.0)
        return inverseStandardNormalCDF(h) - inverseStandardNormalCDF(f)
    }

    var dataQualityWarning: DataQualityWarning? {
        guard notDeliveredCount >= RecognitionDataQualityRules.notDeliveredReadminThreshold
        else { return nil }
        return .recommendReadminister(
            reason: "Tavus delivery failure on \(notDeliveredCount) of " +
                    "\(RecognitionForm.stimulusCount) stimuli",
            threshold: "≥\(RecognitionDataQualityRules.notDeliveredReadminThreshold)/" +
                       "\(RecognitionForm.stimulusCount) not delivered"
        )
    }
}

/// Inverse standard normal CDF (probit).
/// Implementation: Beasley-Springer-Moro algorithm.
/// Used for d′ computation only — accuracy adequate for clinical 0.1 < p < 0.9.
private func inverseStandardNormalCDF(_ p: Double) -> Double {
    // Acklam (2003) approximation — sufficient for d′ in clinical range.
    let a: [Double] = [-3.969683028665376e+01,  2.209460984245205e+02,
                       -2.759285104469687e+02,  1.383577518672690e+02,
                       -3.066479806614716e+01,  2.506628277459239e+00]
    let b: [Double] = [-5.447609879822406e+01,  1.615858368580409e+02,
                       -1.556989798598866e+02,  6.680131188771972e+01,
                       -1.328068155288572e+01]
    let c: [Double] = [-7.784894002430293e-03, -3.223964580411365e-01,
                       -2.400758277161838e+00, -2.549732539343734e+00,
                        4.374664141464968e+00,  2.938163982698783e+00]
    let d: [Double] = [ 7.784695709041462e-03,  3.224671290700398e-01,
                        2.445134137142996e+00,  3.754408661907416e+00]

    let pLow  = 0.02425
    let pHigh = 1 - pLow

    if p < pLow {
        let q = (-2 * log(p)).squareRoot()
        return (((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) /
               ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1)
    } else if p <= pHigh {
        let q = p - 0.5
        let r = q * q
        return (((((a[0]*r + a[1])*r + a[2])*r + a[3])*r + a[4])*r + a[5]) * q /
               (((((b[0]*r + b[1])*r + b[2])*r + b[3])*r + b[4])*r + 1)
    } else {
        let q = (-2 * log(1 - p)).squareRoot()
        return -(((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) /
                ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Models/RecognitionResult.swift
git commit -m "feat(recognition): RecognitionResult computed properties + d′ via probit

Hits/misses/sFA/uFA/correctRejections counted by consulting
RecognitionForm.formA[response.stimulusIndex].kind. d′ uses Hautus loglinear
boundary correction + Acklam probit approximation. dataQualityWarning fires
at notDeliveredCount >= notDeliveredReadminThreshold."
```

---

## Task 3 — Add `RecognitionScorerTests` (TDD)

**Files:**
- Create: `VoiceMiniCogTests/RecognitionScorerTests.swift`

- [ ] **Step 1: Write boundary tests**

```swift
import XCTest
@testable import VoiceMiniCog

final class RecognitionScorerTests: XCTestCase {

    private func response(_ idx: Int, _ status: ResponseStatus) -> StimulusResponse {
        StimulusResponse(
            stimulusIndex: idx,
            stimulusOnsetTimestamp: Date(timeIntervalSince1970: Double(idx)),
            responseStatus: status,
            reactionTimeMs: status == .yes || status == .no ? 1500 : nil
        )
    }

    private func result(responses: [StimulusResponse],
                        captionAccommodationActive: Bool = false) -> RecognitionResult {
        RecognitionResult(
            formID: "A",
            responses: responses,
            captionAccommodationActive: captionAccommodationActive
        )
    }

    /// All 5 targets correctly identified, all 10 foils correctly rejected.
    func test_perfectPerformance_yields_max_dPrime_and_no_warning() {
        // Form A presentationOrder gives target indices 0–4 in stimuli array;
        // identify which admit positions correspond to targets.
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            let stim = form.stimulus(at: i)
            let correctAnswer: ResponseStatus = (stim.kind == .target) ? .yes : .no
            responses.append(response(form.presentationOrder[i], correctAnswer))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.hits, 5)
        XCTAssertEqual(r.misses, 0)
        XCTAssertEqual(r.semanticFalseAlarms, 0)
        XCTAssertEqual(r.unrelatedFalseAlarms, 0)
        XCTAssertEqual(r.correctRejections, 10)
        XCTAssertGreaterThan(r.dPrime, 2.5)   // floor for "max performance" with loglinear
        XCTAssertNil(r.dataQualityWarning)
    }

    /// 0 hits (all targets called "no"), 0 false alarms — chance-level recognition.
    func test_zeroHits_zero_FA_yields_negative_dPrime() {
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            responses.append(response(form.presentationOrder[i], .no))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.hits, 0)
        XCTAssertEqual(r.misses, 5)
        XCTAssertEqual(r.semanticFalseAlarms, 0)
        XCTAssertEqual(r.unrelatedFalseAlarms, 0)
        XCTAssertEqual(r.correctRejections, 10)
        // d′ should be negative (worse than chance)
        XCTAssertLessThan(r.dPrime, 0)
    }

    /// Indiscriminate "yes" responding — all 15 stimuli "yes".
    func test_allYes_response_bias_yields_zero_dPrime() {
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            responses.append(response(form.presentationOrder[i], .yes))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.hits, 5)
        XCTAssertEqual(r.semanticFalseAlarms, 5)
        XCTAssertEqual(r.unrelatedFalseAlarms, 5)
        XCTAssertEqual(r.falseAlarms, 10)
        // Hit rate = 5/5 → 1.0 (boundary), FA rate = 10/10 → 1.0 (boundary)
        // After loglinear correction both ≈ 0.917, d′ ≈ 0
        XCTAssertEqual(r.dPrime, 0, accuracy: 0.001)
    }

    /// Notdelivered = 1 → no warning (below threshold).
    func test_oneNotDelivered_belowThreshold_no_warning() {
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            let status: ResponseStatus = (i == 0) ? .notDelivered : .no
            responses.append(response(form.presentationOrder[i], status))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.notDeliveredCount, 1)
        XCTAssertNil(r.dataQualityWarning)
    }

    /// Notdelivered = 2 → warning fires.
    func test_twoNotDelivered_atThreshold_warning_fires() {
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            let status: ResponseStatus = (i < 2) ? .notDelivered : .no
            responses.append(response(form.presentationOrder[i], status))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.notDeliveredCount, 2)
        guard case .recommendReadminister = r.dataQualityWarning else {
            return XCTFail("Expected .recommendReadminister, got \(String(describing: r.dataQualityWarning))")
        }
    }

    /// Caption accommodation flag round-trips through Codable.
    func test_captionAccommodationActive_codable_roundtrips() throws {
        let r = result(responses: [], captionAccommodationActive: true)
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(RecognitionResult.self, from: data)
        XCTAssertTrue(decoded.captionAccommodationActive)
    }

    /// timedOut count is computed correctly.
    func test_timedOutCount() {
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        for i in 0..<RecognitionForm.stimulusCount {
            let status: ResponseStatus = (i < 3) ? .timedOut : .no
            responses.append(response(form.presentationOrder[i], status))
        }
        let r = result(responses: responses)
        XCTAssertEqual(r.timedOutCount, 3)
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionScorerTests -quiet 2>&1 | tail -120
```

Expected: 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCogTests/RecognitionScorerTests.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(recognition): RecognitionScorerTests — 7 cases covering boundaries

Perfect performance, zero hits, indiscriminate yes, notDelivered threshold
boundaries, caption-accommodation Codable round-trip, timedOut counting."
```

---

## Task 4 — Implement `EncodingRetrievalIndex.derive()` + tests

**Files:**
- Modify: `VoiceMiniCog/Models/EncodingRetrievalIndex.swift`
- Create: `VoiceMiniCogTests/EncodingRetrievalIndexTests.swift`

- [ ] **Step 1: Replace the `derive` stub with the threshold logic**

```swift
extension EncodingRetrievalIndex {
    static func derive(from result: RecognitionResult,
                       freeRecall: Int,
                       firstTrialRegistration: Int) -> EncodingRetrievalIndex {

        let delivered = result.responses.count - result.notDeliveredCount

        let signal: MemoryPatternSignal
        if delivered < Thresholds.minDeliveredForInterpretation {
            signal = .insufficientData
        } else if freeRecall >= Thresholds.freeRecallPreservedFloor {
            signal = .normalPattern
        } else if result.dPrime >= Thresholds.dPrimePreservedFloor {
            signal = .retrievalDifficulty
        } else if result.dPrime < Thresholds.dPrimeImpairedCeiling {
            // Conservative: report as encodingDifficulty by default. The split
            // to consolidationDifficulty would require longer-delay paradigms
            // we don't run; consolidationDifficulty case is reserved for future
            // protocol additions. See doc comment on the enum case.
            signal = .encodingDifficulty
        } else {
            signal = .indeterminate
        }

        return EncodingRetrievalIndex(
            thresholdProvenance: Thresholds.currentProvenance,
            signal: signal,
            registrationScore: firstTrialRegistration,
            delayedRecallScore: freeRecall,
            recognitionHits: result.hits,
            recognitionFalseAlarms: result.falseAlarms
        )
    }
}
```

- [ ] **Step 2: Write the tests**

```swift
import XCTest
@testable import VoiceMiniCog

final class EncodingRetrievalIndexTests: XCTestCase {

    private func recognitionResult(notDelivered: Int = 0,
                                   hits: Int,
                                   falseAlarms: Int) -> RecognitionResult {
        // Construct responses that yield the requested counts.
        // Helper: build minimal-correct fakes for derive() boundary testing.
        let form = RecognitionForm.formA
        var responses: [StimulusResponse] = []
        var hitsAssigned = 0
        var faAssigned = 0
        var notDeliveredAssigned = 0

        for i in 0..<RecognitionForm.stimulusCount {
            let stim = form.stimulus(at: i)
            let stimulusArrayIndex = form.presentationOrder[i]

            if notDeliveredAssigned < notDelivered {
                responses.append(StimulusResponse(
                    stimulusIndex: stimulusArrayIndex,
                    stimulusOnsetTimestamp: Date(),
                    responseStatus: .notDelivered,
                    reactionTimeMs: nil
                ))
                notDeliveredAssigned += 1
            } else if stim.kind == .target && hitsAssigned < hits {
                responses.append(StimulusResponse(
                    stimulusIndex: stimulusArrayIndex,
                    stimulusOnsetTimestamp: Date(),
                    responseStatus: .yes,
                    reactionTimeMs: 1500
                ))
                hitsAssigned += 1
            } else if stim.kind != .target && faAssigned < falseAlarms {
                responses.append(StimulusResponse(
                    stimulusIndex: stimulusArrayIndex,
                    stimulusOnsetTimestamp: Date(),
                    responseStatus: .yes,
                    reactionTimeMs: 1500
                ))
                faAssigned += 1
            } else {
                let isTarget = (stim.kind == .target)
                responses.append(StimulusResponse(
                    stimulusIndex: stimulusArrayIndex,
                    stimulusOnsetTimestamp: Date(),
                    responseStatus: isTarget ? .no : .no,
                    reactionTimeMs: 1500
                ))
            }
        }

        return RecognitionResult(formID: "A",
                                 responses: responses,
                                 captionAccommodationActive: false)
    }

    func test_normalPattern_when_freeRecall_above_floor() {
        // freeRecall = 4 ≥ Thresholds.freeRecallPreservedFloor (3) → .normalPattern
        let r = recognitionResult(hits: 5, falseAlarms: 0)
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 4,
            firstTrialRegistration: 5
        )
        XCTAssertEqual(idx.signal, .normalPattern)
        XCTAssertEqual(idx.thresholdProvenance,
                       EncodingRetrievalIndex.Thresholds.currentProvenance)
    }

    func test_retrievalDifficulty_when_lowRecall_preservedRecognition() {
        // freeRecall = 1 (below floor), d′ ≥ 1.5 → .retrievalDifficulty
        let r = recognitionResult(hits: 5, falseAlarms: 0)   // d′ ~ 4.5 (loglinear)
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 1,
            firstTrialRegistration: 5
        )
        XCTAssertEqual(idx.signal, .retrievalDifficulty)
    }

    func test_encodingDifficulty_when_lowRecall_impairedRecognition() {
        // freeRecall = 1, d′ < 0.5 → .encodingDifficulty
        let r = recognitionResult(hits: 1, falseAlarms: 5)   // d′ ~ -0.something
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 1,
            firstTrialRegistration: 3
        )
        XCTAssertEqual(idx.signal, .encodingDifficulty)
    }

    func test_indeterminate_borderline_dPrime() {
        // freeRecall = 1, 0.5 ≤ d′ < 1.5 → .indeterminate
        let r = recognitionResult(hits: 4, falseAlarms: 4)   // d′ in middle band
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 1,
            firstTrialRegistration: 3
        )
        XCTAssertEqual(idx.signal, .indeterminate)
    }

    func test_insufficientData_when_too_many_notDelivered() {
        // notDelivered = 3 → delivered = 12 < minDeliveredForInterpretation (13)
        let r = recognitionResult(notDelivered: 3, hits: 4, falseAlarms: 0)
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 4,
            firstTrialRegistration: 5
        )
        XCTAssertEqual(idx.signal, .insufficientData)
    }

    func test_provenance_string_present() {
        let r = recognitionResult(hits: 5, falseAlarms: 0)
        let idx = EncodingRetrievalIndex.derive(
            from: r,
            freeRecall: 4,
            firstTrialRegistration: 5
        )
        XCTAssertFalse(idx.thresholdProvenance.isEmpty)
        XCTAssertTrue(idx.thresholdProvenance.contains("Provisional v1.0"))
    }
}
```

- [ ] **Step 3: Run tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/EncodingRetrievalIndexTests -quiet 2>&1 | tail -120
```

Expected: 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Models/EncodingRetrievalIndex.swift \
        VoiceMiniCogTests/EncodingRetrievalIndexTests.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(recognition): EncodingRetrievalIndex.derive() + 6-pattern test suite

Implements derivation per spec §B.4:
  delivered<13 → insufficientData
  freeRecall≥3 → normalPattern
  freeRecall<3 ∧ d′≥1.5 → retrievalDifficulty
  freeRecall<3 ∧ d′<0.5 → encodingDifficulty
  otherwise → indeterminate
thresholdProvenance string verbatim from Thresholds.currentProvenance."
```

---

## Task 5 — Add `replicaStoppedSpeaking` notification publication in `DailyCallManager`

**Files:**
- Modify: `VoiceMiniCog/Services/DailyCallManager.swift`
- Modify: `VoiceMiniCog/Views/TavusHelpers.swift` (notification name)

- [ ] **Step 1: Add the notification name**

In `Views/TavusHelpers.swift`:
```swift
extension Notification.Name {
    /// Posted when Tavus reports the replica has finished speaking the most
    /// recent echo or LLM-generated utterance. Anchored to the
    /// `conversation.replica.stopped_speaking` event from
    /// `appMessageAsJson` (Daily SDK delegate).
    /// Consumer: RecognitionPhaseView (Plan 2).
    static let replicaStoppedSpeaking = Notification.Name("replicaStoppedSpeaking")
}
```

- [ ] **Step 2: Publish from `callClient(_:appMessageAsJson:from:)`**

In `DailyCallManager.swift`, find the existing `appMessageAsJson` delegate method that already handles other Tavus events. Add a branch:

```swift
if let messageType = json["message_type"] as? String,
   messageType == "conversation",
   let event = json["event_type"] as? String,
   event == "conversation.replica.stopped_speaking" {
    NotificationCenter.default.post(
        name: .replicaStoppedSpeaking,
        object: nil,
        userInfo: ["receivedAt": Date()]
    )
}
```

(Adjust the JSON-shape match to whatever pattern the existing code uses for sibling Tavus events — `conversation.replica.started_speaking` is already handled, follow the same shape.)

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Services/DailyCallManager.swift VoiceMiniCog/Views/TavusHelpers.swift
git commit -m "feat(daily): publish replicaStoppedSpeaking notification

Anchors RecognitionPhaseView's response window to actual avatar speech end,
not echo dispatch — eliminates Tavus first-token jitter from reaction-time
data."
```

---

## Task 6 — Add Recognition copy to `LeftPaneSpeechCopy`

**Files:**
- Modify: `VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift`

- [ ] **Step 1: Add the new constants**

```swift
extension LeftPaneSpeechCopy {

    /// Recognition module — patient-facing intro.
    static let recognitionIntro: String = """
    Earlier I said five words. Now I'll say some words one at a time. \
    Tell me yes if it's one of those original five words, or no if it isn't.
    """

    /// Recognition module — per-stimulus prompt asked of the patient
    /// in the avatar zone alongside the spoken stimulus. Shown silently
    /// in the right-pane label, NOT spoken.
    static let recognitionStimulusPromptLabel: String =
        "Was this one of the original five words?"

    /// Recognition module — closing line after all 15 stimuli delivered.
    static let recognitionClosing: String =
        "That's the last set. Thank you — we're all done."
}
```

- [ ] **Step 2: Verify contamination guard still passes**

The recognition copy contains stimulus-related text. Run:
```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionContaminationGuardTests -quiet 2>&1 | tail -120
```

Verify: no stimulus words (`dog`, `rain`, `butter`, `love`, `door`, `horse`, `snow`, `cheese`, `joy`, `window`, `truck`, `paper`, `garden`, `ladder`, `bicycle`) appear in the new copy. If any do, rephrase the copy.

The copy strings above contain none of the 15 stimuli — verified by inspection. Test should pass.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift
git commit -m "feat(copy): recognition intro/stimulus-prompt/closing strings

Verified clean of all 15 stimulus words (RecognitionContaminationGuardTests
passes)."
```

---

## Task 7 — Add Recognition persona overlay + voice profile lock to `QMCIAvatarContext`

**Files:**
- Modify: `VoiceMiniCog/Services/QMCIAvatarContext.swift`

- [ ] **Step 1: Add the locked voice profile constant (Hard Gate 1)**

Insert at the top of the file:

```swift
extension QMCIAvatarContext {
    /// Tavus voice profile ID for the MercyCognitive single-voice-profile invariant.
    /// Same profile drives Word Registration and Word Recognition — timbre/prosody
    /// match across encoding ↔ recognition is clinically required to avoid
    /// differential-priming artifacts.
    static let mercyCognitiveVoiceProfileID: String = "<INSERT BEFORE PR OPENS>"
}
```

The PR cannot open until the placeholder is replaced with the actual ID.

- [ ] **Step 2: Add the recognition persona overlay**

```swift
extension QMCIAvatarContext {
    static let recognitionContext: String = """
    You are presenting one word at a time for a yes/no recognition task. Echo \
    only the scripted single words and the scripted intro/outro. Do not paraphrase. \
    Do not acknowledge correctness. Examiner-never-corrects rule active. Voice \
    profile must match the registration phase exactly — single Tavus voice \
    profile across encoding and recognition.
    """
}
```

- [ ] **Step 3: Wire the context into the phase context dispatcher**

Find the existing dispatcher (probably `func contextString(for phase: AssessmentPhaseType)` or similar). Add:
```swift
case .recognition: return Self.recognitionContext
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Services/QMCIAvatarContext.swift
git commit -m "feat(avatar): recognition persona overlay + voice profile lock

Hard gate: mercyCognitiveVoiceProfileID must be set to the real Tavus voice
ID before this PR opens. No TODO placeholder permitted in an open PR."
```

---

## Task 8 — Add caption-assist accommodation toggle (clinician-side, default off)

**Files:**
- Modify: `VoiceMiniCog/Models/AssessmentSession.swift` (or wherever per-session settings live)
- Modify: any clinician-side intake/setup screen view

- [ ] **Step 1: Add the per-session field**

```swift
/// Caption-assist accommodation for the Recognition trial. Default off (audio-only).
/// Clinician-side toggle on the intake/setup screen. Recorded on the session,
/// surfaced in the PDF report and research export when active.
var captionAccommodationActive: Bool = false
```

This field is propagated to `RecognitionResult.captionAccommodationActive` when the recognition module finishes (Task 9 sets this).

- [ ] **Step 2: Add the toggle UI on the clinician-side intake screen**

Find the clinician-facing intake/setup screen (likely in `MAHandoffView.swift` or `Views/HomeView.swift` clinician path). Add a `Toggle("Caption-assist for Recognition", isOn: $session.captionAccommodationActive)`. Ensure it is NEVER visible to the patient.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Models/AssessmentSession.swift VoiceMiniCog/Views/MAHandoffView.swift
git commit -m "feat(recognition): caption-assist accommodation toggle (clinician-side)

Default off (audio-only). Toggle visible only on clinician intake/setup
screen — never patient-facing. State recorded on session and propagated to
RecognitionResult.captionAccommodationActive."
```

---

## Task 9 — Add `RecognitionPhaseView` (Tavus delivery loop)

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/RecognitionPhaseView.swift`

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

struct RecognitionPhaseView: View {
    @Bindable var session: AssessmentSession
    let onComplete: (RecognitionResult) -> Void

    @State private var currentAdmitIndex: Int = 0
    @State private var responseEnabled: Bool = false
    @State private var responseDeadline: Date? = nil
    @State private var stimulusOnsetTimestamp: Date? = nil
    @State private var deliveryTimer: Timer?
    @State private var responseWindowTimer: Timer?
    @State private var responses: [StimulusResponse] = []
    @State private var introSpoken: Bool = false

    private let form = RecognitionForm.formA

    private let responseWindowSec: TimeInterval = 6
    private let deliveryTimeoutSec: TimeInterval = 10

    var body: some View {
        VStack(spacing: 32) {
            AvatarZoneView()   // existing avatar surface

            Text(LeftPaneSpeechCopy.recognitionStimulusPromptLabel)
                .font(.system(size: 17))
                .foregroundColor(.secondary)

            if session.captionAccommodationActive,
               currentAdmitIndex < RecognitionForm.stimulusCount {
                Text(form.stimulus(at: currentAdmitIndex).word)
                    .font(.system(size: 22, weight: .medium))
                    .padding(.vertical, 8)
            }

            HStack(spacing: 32) {
                Button("Yes") { recordResponse(.yes) }
                    .buttonStyle(LargeYNButtonStyle(color: .green))
                    .disabled(!responseEnabled)

                Button("No") { recordResponse(.no) }
                    .buttonStyle(LargeYNButtonStyle(color: .red))
                    .disabled(!responseEnabled)
            }
        }
        .onAppear {
            speakIntro()
        }
        .onReceive(NotificationCenter.default.publisher(for: .replicaStoppedSpeaking)) { _ in
            handleReplicaStoppedSpeaking()
        }
    }

    private func speakIntro() {
        guard !introSpoken else { return }
        introSpoken = true
        avatarSpeak(LeftPaneSpeechCopy.recognitionIntro)
        // The next replicaStoppedSpeaking event after intro will trigger the
        // first stimulus delivery via handleReplicaStoppedSpeaking().
    }

    private func deliverNextStimulus() {
        guard currentAdmitIndex < RecognitionForm.stimulusCount else {
            finalize()
            return
        }
        let stim = form.stimulus(at: currentAdmitIndex)
        avatarSpeak(stim.word)

        deliveryTimer?.invalidate()
        deliveryTimer = Timer.scheduledTimer(withTimeInterval: deliveryTimeoutSec,
                                              repeats: false) { _ in
            handleDeliveryTimeout()
        }
    }

    private func handleReplicaStoppedSpeaking() {
        deliveryTimer?.invalidate()
        deliveryTimer = nil

        if !introSpoken { return }   // ignore pre-intro events
        if currentAdmitIndex >= RecognitionForm.stimulusCount { return }

        let now = Date()
        stimulusOnsetTimestamp = now   // anchor reaction time to this moment
        responseEnabled = true

        responseWindowTimer?.invalidate()
        responseWindowTimer = Timer.scheduledTimer(withTimeInterval: responseWindowSec,
                                                    repeats: false) { _ in
            handleResponseWindowTimeout()
        }
    }

    private func recordResponse(_ status: ResponseStatus) {
        responseWindowTimer?.invalidate()
        responseEnabled = false

        let stim = form.stimulus(at: currentAdmitIndex)
        let reactionTime: Double? = stimulusOnsetTimestamp.map {
            Date().timeIntervalSince($0) * 1000
        }

        responses.append(StimulusResponse(
            stimulusIndex: form.presentationOrder[currentAdmitIndex],
            stimulusOnsetTimestamp: stimulusOnsetTimestamp ?? Date(),
            responseStatus: status,
            reactionTimeMs: reactionTime
        ))

        currentAdmitIndex += 1
        deliverNextStimulus()
    }

    private func handleResponseWindowTimeout() {
        responseEnabled = false

        responses.append(StimulusResponse(
            stimulusIndex: form.presentationOrder[currentAdmitIndex],
            stimulusOnsetTimestamp: stimulusOnsetTimestamp ?? Date(),
            responseStatus: .timedOut,
            reactionTimeMs: nil
        ))

        currentAdmitIndex += 1
        deliverNextStimulus()
    }

    private func handleDeliveryTimeout() {
        // No replicaStoppedSpeaking event within deliveryTimeoutSec.
        // Avatar failed to deliver. Mark .notDelivered, no retry, advance.
        avatarInterrupt()   // clear any stuck echo state

        responses.append(StimulusResponse(
            stimulusIndex: form.presentationOrder[currentAdmitIndex],
            stimulusOnsetTimestamp: Date(),
            responseStatus: .notDelivered,
            reactionTimeMs: nil
        ))

        currentAdmitIndex += 1
        deliverNextStimulus()
    }

    private func finalize() {
        avatarSpeak(LeftPaneSpeechCopy.recognitionClosing)

        let result = RecognitionResult(
            formID: form.formID,
            responses: responses,
            captionAccommodationActive: session.captionAccommodationActive
        )
        onComplete(result)
    }
}

private struct LargeYNButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold))
            .frame(minWidth: 180, minHeight: 88)
            .padding()
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
```

- [ ] **Step 2: Register in pbxproj**

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/Phases/RecognitionPhaseView.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(recognition): RecognitionPhaseView with Tavus delivery loop

Per-stimulus loop anchored to replicaStoppedSpeaking notification. 6s
response window, 10s delivery timeout. Tavus failure → .notDelivered, no
retry. Y/N buttons ≥88pt for older-adult target use. Caption-assist
accommodation visible only when session toggle is on."
```

---

## Task 10 — Insert `.recognition` into `phaseSequence` and wire routing

**Files:**
- Modify: `VoiceMiniCog/Models/AvatarLayoutManager.swift` (phaseSequence)
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift` (routing)
- Modify: `VoiceMiniCogTests/BatteryEnumSyncTests.swift` (sequence test)

- [ ] **Step 1: Update `phaseSequence`**

```swift
extension AssessmentFlowType {
    var phaseSequence: [AssessmentPhaseID] {
        switch self {
        case .quick, .extended:
            return [.welcome, .orientation, .wordRegistration, .clockDrawing,
                    .wordRecall, .recognition, .completion]   // 5 cognitive
        case .caregiver:
            return [.welcome, .completion]
        }
    }
}
```

- [ ] **Step 2: Update routing in `AvatarAssessmentCanvas`**

Replace the `EmptyView()` placeholder for `.recognition` with the real phase view:

```swift
case .recognition:
    RecognitionPhaseView(session: session) { result in
        // Persist result + advance phase
        session.recognitionResult = result
        layoutManager.advance()
    }
```

- [ ] **Step 3: Update `BatteryEnumSyncTests`**

```swift
func testQuickFlowSequenceMatchesCanonicalOrder() {
    let expected: [AssessmentPhaseID] = [
        .welcome, .orientation, .wordRegistration, .clockDrawing,
        .wordRecall, .recognition, .completion   // 5 cognitive in Plan 2
    ]
    XCTAssertEqual(AssessmentFlowType.quick.phaseSequence, expected)
    XCTAssertEqual(AssessmentFlowType.extended.phaseSequence, expected)
}
```

- [ ] **Step 4: Run sync tests**

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Models/AvatarLayoutManager.swift \
        VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift \
        VoiceMiniCogTests/BatteryEnumSyncTests.swift
git commit -m "feat(battery): insert .recognition into quick/extended phaseSequence

5-cognitive-module sequence: orient → reg → clock → recall → recognize.
TMT-B inserted between recall and recognize in Plan 3."
```

---

## Task 11 — Update `ProgressTrackView` for 5-cell layout

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift`

- [ ] **Step 1: Verify the chevron auto-derives from phaseSequence**

The Plan 1 implementation already filters `phaseSequence` for cognitive cells. Adding `.recognition` to `phaseSequence` should automatically produce a 5-cell chevron with the "Recognize" short name (already in the `shortName` map). No code change should be needed.

- [ ] **Step 2: Smoke-test in simulator**

Run a session and verify the chevron shows 5 cells: Orient → Words → Clock → Recall → Recognize.

- [ ] **Step 3: Commit (if changes made; otherwise skip)**

---

## Task 12 — Update `QMCIScoringEngine` to integrate Recognition + EncodingRetrievalIndex

**Files:**
- Modify: `VoiceMiniCog/Services/QMCIScoringEngine.swift`

- [ ] **Step 1: Add Recognition + EncodingRetrievalIndex computation**

In the existing `func calculate(for session: AssessmentSession)` (or similar entry point), add:

```swift
// Recognition module result is already populated on session.recognitionResult
// by RecognitionPhaseView.onComplete handler.
let recognitionResult = session.recognitionResult

// Derive Encoding/Retrieval Index from delayed recall + recognition.
let freeRecall = session.qmciState.delayedRecallScore
let firstTrialReg = session.qmciState.registrationResult.firstTrialScore

if let r = recognitionResult {
    session.encodingRetrievalIndex = EncodingRetrievalIndex.derive(
        from: r,
        freeRecall: freeRecall,
        firstTrialRegistration: firstTrialReg
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/Services/QMCIScoringEngine.swift
git commit -m "feat(scoring): integrate Recognition + derive EncodingRetrievalIndex"
```

---

## Task 13 — Update `PartialScoreReport` schema

**Files:**
- Modify: `VoiceMiniCog/Services/PartialScoreReport.swift`

- [ ] **Step 1: Add new top-level keys**

Add to the Codable struct:
```swift
let recognitionResult: RecognitionResult?
let encodingRetrievalIndex: EncodingRetrievalIndex?
```

Add corresponding `CodingKeys` entries and encode/decode logic. PHQ-2 keys remain (written only when `FeatureFlags.phq2Enabled`).

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/Services/PartialScoreReport.swift
git commit -m "feat(report): add recognitionResult + encodingRetrievalIndex to schema"
```

---

## Task 14 — Update `PDFReportGenerator` (Recognition section + Memory Pattern Signals)

**Files:**
- Modify: `VoiceMiniCog/Services/PDFReportGenerator.swift`

- [ ] **Step 1: Add Recognition section**

After the Delayed Recall section, add:
```swift
// Recognition Trial section
if let r = result.recognitionResult {
    addSection(title: "Word Recognition Trial")
    addLine("Hits: \(r.hits) / 5")
    addLine("Misses: \(r.misses) / 5")
    addLine("Semantic false alarms: \(r.semanticFalseAlarms) / 5")
    addLine("Unrelated false alarms: \(r.unrelatedFalseAlarms) / 5")
    addLine(String(format: "d′: %.2f", r.dPrime))

    if r.captionAccommodationActive {
        addLine("Administered with caption-assist accommodation.")
    }

    if let warning = r.dataQualityWarning {
        addRecommendedAction(warning)
    }
}
```

- [ ] **Step 2: Add Memory Pattern Signals block**

```swift
if let idx = result.encodingRetrievalIndex {
    addSection(title: "Memory Pattern Signals")
    addLine("Pattern: \(displayName(for: idx.signal))")

    // Provenance disclosure rendered VERBATIM.
    addLine("")
    addLine(idx.thresholdProvenance)
    addLine("")

    // Conservative-supportive-context boilerplate.
    addLine("Pattern signals are conservative supportive context, not a " +
            "diagnosis. Interpretation requires clinical correlation with " +
            "informant history, depression screening, and other testing.")
}

private func displayName(for signal: MemoryPatternSignal) -> String {
    switch signal {
    case .normalPattern: return "Normal pattern"
    case .retrievalDifficulty: return "Suggests retrieval difficulty"
    case .encodingDifficulty: return "Suggests encoding difficulty"
    case .consolidationDifficulty: return "Suggests consolidation difficulty"
    case .indeterminate: return "Indeterminate"
    case .insufficientData: return "Insufficient data"
    }
}

private func addRecommendedAction(_ warning: DataQualityWarning) {
    switch warning {
    case let .recommendReadminister(reason, threshold):
        addBoldLine("Recommended Action")
        addLine("Re-administer recognition trial in a separate session.")
        addLine("Reason: \(reason)")
        addLine("Threshold: \(threshold)")
    }
}
```

**HARD GATE 2:** All copy in this Task — section title, displayName strings, conservative-supportive-context boilerplate, recommended-action wording — **MUST** be reviewed by the named neuropsych co-author before this PR ships. Sign-off recorded in commit message and `recognition-foil-rationale.md` §"Pattern thresholds" revision.

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Services/PDFReportGenerator.swift
git commit -m "feat(report): Recognition section + Memory Pattern Signals block

Renders thresholdProvenance VERBATIM. Conservative-supportive-context
boilerplate per spec §B.4. Recommended Action surfaces dataQualityWarning.

Reviewed-by: <NEUROPSYCH-CO-AUTHOR-NAME>, <TITLE>, on 2026-MM-DD"
```

---

## Task 15 — Activate pre-merge hooks for Recognition-touching files

**Files:**
- Modify: `.github/workflows/<existing-test-workflow>.yml`

- [ ] **Step 1: Add hook condition**

Update the existing test workflow so PRs touching:
- `VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift`
- `VoiceMiniCog/Resources/RecognitionForms.json`
- `VoiceMiniCog/Models/RecognitionForm.swift`

block on `RecognitionContaminationGuardTests` passing. Use a `paths` filter or a separate job that runs the targeted test:

```yaml
contamination-guard:
  if: |
    contains(github.event.pull_request.changed_files, 'VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift') ||
    contains(github.event.pull_request.changed_files, 'VoiceMiniCog/Resources/RecognitionForms.json') ||
    contains(github.event.pull_request.changed_files, 'VoiceMiniCog/Models/RecognitionForm.swift')
  runs-on: macos-latest
  steps:
    - uses: actions/checkout@v4
    - run: |
        cd VoiceMiniCog
        xcodebuild test-without-building \
          -project VoiceMiniCog.xcodeproj \
          -scheme VoiceMiniCog \
          -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
          -only-testing:VoiceMiniCogTests/RecognitionContaminationGuardTests
```

(Adjust to match the existing workflow's structure and runner config.)

- [ ] **Step 2: Mark `RecognitionContaminationGuardTests` as RELEASE BLOCKER**

Add a class doc-comment:
```swift
/// RELEASE BLOCKER — clinical-validity contamination guard.
/// Failure indicates a recognition-trial stimulus has leaked outside its
/// whitelisted scope.
```

(Already present from Plan 1 Task 21 — verify.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/
git commit -m "ci: pre-merge hook activates RecognitionContaminationGuardTests

PRs touching LeftPaneSpeechCopy.swift, RecognitionForms.json, or
RecognitionForm.swift now block on the contamination guard."
```

---

## Task 16 — Update CLAUDE.md (Recognition deployed)

**Files:**
- Modify: `VoiceMiniCog/CLAUDE.md`

- [ ] **Step 1: Remove forward-reference disclaimer**

In the "Recognition Trial Architecture" section, delete the forward-reference sentence (*"Forward reference — implemented in Plan 2/3..."*). Update content to reflect the deployed state:
- Tavus voice profile ID committed at `QMCIAvatarContext.mercyCognitiveVoiceProfileID`
- `replicaStoppedSpeaking` notification published from `DailyCallManager`
- `RecognitionContaminationGuardTests` now active in pre-merge hooks

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/CLAUDE.md
git commit -m "docs(claude): Recognition Trial Architecture section now deployed"
```

---

## Plan 2 Acceptance

- [ ] **Step 1: Full app build + test suite green**

```bash
xcodebuild test -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -150
```

Expected: all Plan 1 tests + new Plan 2 tests pass:
- BatteryEnumSyncTests (sequence updated)
- RecognitionFormConstraintsTests (fingerprint locked)
- RecognitionContaminationGuardTests (active scope, no violations)
- RecognitionScorerTests (7 cases)
- EncodingRetrievalIndexTests (6 cases)
- AssessmentPersistenceMigrationTests

- [ ] **Step 2: Manual smoke test**

Run a session through Welcome → … → Recognition → Completion. Verify:
- Avatar speaks intro then 15 stimuli with consistent voice profile.
- Y/N buttons appear after `replicaStoppedSpeaking` for each stimulus.
- 6s response window enforces.
- PDF report renders Recognition section + Memory Pattern Signals block with verbatim provenance string.

- [ ] **Step 3: Verify Hard Gates before opening PR**

- ☐ `mercyCognitiveVoiceProfileID` is a non-nil real value (no `<INSERT BEFORE PR OPENS>` placeholder).
- ☐ Memory Pattern Signals copy reviewed by named neuropsych co-author.
- ☐ Reviewer sign-off in commit message: `Reviewed-by: <Name>, <Title>, on <date>`.
- ☐ `docs/clinical/recognition-foil-rationale.md` §"Pattern thresholds" updated with reviewer name + date.

- [ ] **Step 4: Open PR**

PR title: `Plan 2 — Recognition module + contamination guard activation`

PR body must include both Hard Gate confirmations + reference [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md).

---

## Plan 2 Self-Review (run before PR opens)

1. **Spec coverage:** Every step in spec §F.2 (18 sub-tasks) maps to a Task here. Hard gates 1 and 2 are documented in Plan 2 preamble + acceptance.
2. **Placeholder scan:** No `TODO` / `TBD` in shipped code paths. The `<INSERT BEFORE PR OPENS>` placeholder for `mercyCognitiveVoiceProfileID` is the explicit Hard Gate 1 — must be replaced before PR open.
3. **Type consistency:** `RecognitionStimulusKind` (referenced in Tasks 2, 3, 4), `MemoryPatternSignal` cases (Task 4 + Task 14 displayName), `DataQualityWarning` (Tasks 2, 3, 14), `RecognitionDataQualityRules.notDeliveredReadminThreshold` (Tasks 2, 3) — names match across referencing tasks.
4. **Cross-plan handoff:** Plan 3 inherits a 5-module sequence; needs to insert `.tmtB` between `.wordRecall` and `.recognition`. `RecognitionContaminationGuardTests` whitelist scope already includes `LeftPaneSpeechCopy.swift` recognition strings (Task 6).

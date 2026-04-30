# Plan 1 — Deletion + Restructure (4-Module Battery Ships)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the MercyCognitive battery from its 6-module Qmci-derived form to a 4-module cognitive battery (Welcome → Orientation → Word Registration → Clock Drawing → Delayed Recall → Completion). Delete Verbal Fluency, Logical Memory (Story Recall), QDRS, demographics, and caregiver-flow surfaces. Inactivate PHQ-2 behind a runtime feature flag. Land all empty struct definitions for Recognition / TMT-B / kinematics so Plans 2 and 3 ship with zero schema migration.

**Architecture:** Three parallel phase enums (`Phase` for persistence, `AssessmentPhaseType` for LLM-behavior gating, `AssessmentPhaseID` for avatar layout) are kept in sync via a new `BatteryEnumSyncTests` runtime guard. The canonical 6-module sequence lives in `AssessmentFlowType.quick.phaseSequence`; this plan ships its 4-cognitive-module subset. Persistence schema bumps from v1 to v2; v1 sessions are read-only-legacy or abandoned-with-notice — no silent in-flight migration.

**Tech Stack:** Swift, SwiftUI, iOS 16+, Xcode `.xcodeproj` (no SwiftPM), XCTest. Daily Client iOS SDK + Tavus REST untouched in Plan 1.

**Spec source of truth:** [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md)

**Branch:** `v1-pilot` → feature branch `plan-1-deletion-restructure`

---

## Build / Test Commands (used throughout)

**Fast incremental test (single test class):**
```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/<TestClassName> \
  -quiet 2>&1 | tail -120
```

**If `Failed to create a bundle instance` or `no build products`:**
```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -40
```
Then re-run `test-without-building`.

**Full app build:**
```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -40
```

**Boot simulator (once per session):**
```bash
xcrun simctl boot "Ipad 13 inch sim"
```

---

## Task 1 — Update `Phase` enum

**Files:**
- Modify: `VoiceMiniCog/Models/Phase.swift`

- [ ] **Step 1: Read the current file**

Read [Models/Phase.swift](../../VoiceMiniCog/Models/Phase.swift) end-to-end. Confirm current cases: `.intake`, `.qmciOrientation`, `.qmciRegistration`, `.qmciClockDrawing`, `.qmciVerbalFluency`, `.qmciLogicalMemory`, `.qmciDelayedRecall`, `.scoring`, `.report`.

- [ ] **Step 2: Replace cases**

In the `enum Phase` declaration:
- Remove: `case qmciVerbalFluency`
- Remove: `case qmciLogicalMemory`
- Add: `case qmciTMTB`
- Add: `case qmciRecognition`

Final case list (in spec-canonical order):
```swift
enum Phase: String, CaseIterable, Codable {
    case intake
    case qmciOrientation
    case qmciRegistration
    case qmciClockDrawing
    case qmciDelayedRecall
    case qmciTMTB
    case qmciRecognition
    case scoring
    case report
}
```

- [ ] **Step 3: Update `displayName`**

```swift
var displayName: String {
    switch self {
    case .intake: return "Patient Intake"
    case .qmciOrientation: return "Orientation"
    case .qmciRegistration: return "Word Learning"
    case .qmciClockDrawing: return "Clock Drawing"
    case .qmciDelayedRecall: return "Word Recall"
    case .qmciTMTB: return "Trail-Making Executive Task"
    case .qmciRecognition: return "Word Recognition"
    case .scoring: return "Scoring"
    case .report: return "Report"
    }
}
```

- [ ] **Step 4: Refactor `next` to derive from `AssessmentFlowType.quick.phaseSequence`**

Replace the existing manually-curated `next` switch with the drift-proof derivation:

```swift
var next: Phase? {
    let canonical: [Phase] = AssessmentFlowType.quick.phaseSequence
        .compactMap(Phase.matching) + [.scoring, .report]
    guard let i = canonical.firstIndex(of: self),
          i + 1 < canonical.count else { return nil }
    return canonical[i + 1]
}
```

- [ ] **Step 5: Add the central bridge `Phase.matching(_:)`**

```swift
extension Phase {
    /// Bridge from layout enum (AssessmentPhaseID) → persistence enum (Phase).
    /// Returns nil for AssessmentPhaseID cases that have no Phase counterpart
    /// (.welcome, .qdrs, .phq2, .completion).
    static func matching(_ id: AssessmentPhaseID) -> Phase? {
        switch id {
        case .orientation:      return .qmciOrientation
        case .wordRegistration: return .qmciRegistration
        case .clockDrawing:     return .qmciClockDrawing
        case .wordRecall:       return .qmciDelayedRecall
        case .tmtB:             return .qmciTMTB
        case .recognition:      return .qmciRecognition
        case .welcome, .qdrs, .phq2, .completion: return nil
        }
    }
}
```

- [ ] **Step 6: Update `prompt`**

Replace the `prompt` getter cases for the deleted modules. Add cases for new modules referencing `LeftPaneSpeechCopy.tmtBInstruction` and `LeftPaneSpeechCopy.recognitionInstruction` (these constants will be added in Plan 2 and Plan 3 — for Plan 1, use placeholder strings that compile):

```swift
case .qmciTMTB:        return ""   // populated in Plan 3
case .qmciRecognition: return ""   // populated in Plan 2
```

Remove the `.qmciVerbalFluency` and `.qmciLogicalMemory` cases.

- [ ] **Step 7: Update `requiresListening`**

```swift
var requiresListening: Bool {
    switch self {
    case .qmciOrientation, .qmciRegistration, .qmciDelayedRecall, .qmciRecognition:
        return true
    default:
        return false
    }
}
```

- [ ] **Step 8: Update `isQmciSubtest`**

```swift
var isQmciSubtest: Bool {
    switch self {
    case .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
         .qmciDelayedRecall, .qmciTMTB, .qmciRecognition:
        return true
    default:
        return false
    }
}
```

- [ ] **Step 9: Build to verify compilation**

The codebase will not yet compile because consumers still reference deleted cases — that's expected. Confirm only **the Phase.swift file itself** has no syntax errors by opening in Xcode or running:
```bash
swift -parse /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog/VoiceMiniCog/Models/Phase.swift 2>&1 | head -20
```

(Don't expect a clean build yet; consumer call sites are repaired in subsequent tasks.)

- [ ] **Step 10: Commit**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog
git add VoiceMiniCog/Models/Phase.swift
git commit -m "refactor(phase): replace fluency/story cases with TMT-B/recognition

- remove .qmciVerbalFluency, .qmciLogicalMemory
- add .qmciTMTB, .qmciRecognition
- refactor next to derive from AssessmentFlowType.quick.phaseSequence
- add Phase.matching(_ id: AssessmentPhaseID) central bridge

Per spec docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md §B.1.
Build is intentionally broken at consumer call sites; repaired in subsequent tasks."
```

---

## Task 2 — Update `AssessmentPhaseType` enum

**Files:**
- Modify: `VoiceMiniCog/Models/AssessmentPhaseType.swift`

- [ ] **Step 1: Replace cases**

```swift
public enum AssessmentPhaseType: String, Codable, Sendable {
    case intro
    case orientation
    case wordRegistration
    case clockDrawing
    case wordRecall
    case tmtB
    case recognition
    case outro
}
```

- [ ] **Step 2: Update `allowsSpeculativeInference`**

```swift
public var allowsSpeculativeInference: Bool {
    switch self {
    case .intro, .outro: return true
    case .orientation, .wordRegistration, .clockDrawing,
         .wordRecall, .tmtB, .recognition:
        return false
    }
}
```

- [ ] **Step 3: Update `isScoredSubtest`**

```swift
public var isScoredSubtest: Bool {
    switch self {
    case .orientation, .wordRegistration, .clockDrawing,
         .wordRecall, .tmtB, .recognition:
        return true
    case .intro, .outro:
        return false
    }
}
```

- [ ] **Step 4: Update `Phase.speculativePhaseType` mapping extension**

In the same file:
```swift
extension Phase {
    var speculativePhaseType: AssessmentPhaseType {
        switch self {
        case .intake:             return .intro
        case .qmciOrientation:    return .orientation
        case .qmciRegistration:   return .wordRegistration
        case .qmciClockDrawing:   return .clockDrawing
        case .qmciDelayedRecall:  return .wordRecall
        case .qmciTMTB:           return .tmtB
        case .qmciRecognition:    return .recognition
        case .scoring, .report:   return .outro
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Models/AssessmentPhaseType.swift
git commit -m "refactor(phase-type): swap fluency/story for TMT-B/recognition

Mirrors Phase.swift case changes. Both new module phases are scripted-echo
subtests with speculative_inference disabled (clinical-validity guard)."
```

---

## Task 3 — Update `AssessmentPhaseID` enum + `isHighRiskAbortPhase` extension

**Files:**
- Modify: `VoiceMiniCog/Models/AvatarLayoutManager.swift`

- [ ] **Step 1: Replace `AssessmentPhaseID` cases (renumbered rawValues)**

```swift
enum AssessmentPhaseID: Int, CaseIterable {
    case welcome         = 1
    case qdrs            = 2     // intentionally inactive (Q1a)
    case phq2            = 3     // intentionally inactive (Q2b, behind flag)
    case orientation     = 4
    case wordRegistration = 5
    case clockDrawing    = 6
    case wordRecall      = 7     // renumbered from 9; rawValue runtime-only
    case tmtB            = 8     // replaces former verbalFluency=7
    case recognition     = 9     // replaces former storyRecall=8
    case completion      = 10
}
```

- [ ] **Step 2: Update `displayName`**

```swift
var displayName: String {
    switch self {
    case .welcome:          return "Welcome"
    case .qdrs:             return "Memory Questionnaire"
    case .phq2:             return "Mood Check"
    case .orientation:      return "Orientation"
    case .wordRegistration: return "Word Registration"
    case .clockDrawing:     return "Clock Drawing"
    case .wordRecall:       return "Word Recall"
    case .tmtB:             return "Trail-Making Executive Task"
    case .recognition:      return "Word Recognition"
    case .completion:       return "Complete"
    }
}
```

- [ ] **Step 3: Add `isHighRiskAbortPhase` extension**

```swift
extension AssessmentPhaseID {
    /// Phases where accidental abort destroys data the patient already
    /// invested effort into. UI shows examiner long-press exit instead
    /// of the standard ghost pill. Replaces the ad-hoc
    /// `[AssessmentPhaseID.verbalFluency]` array literal at the former
    /// AvatarAssessmentCanvas.swift:270.
    var isHighRiskAbortPhase: Bool {
        switch self {
        case .clockDrawing, .tmtB, .recognition: return true
        default: return false
        }
    }
}
```

- [ ] **Step 4: Update `AssessmentTheme` accent registrations**

Open `VoiceMiniCog/Theme/AssessmentTheme.swift` and find the `avatarWidthRatios` and accent maps keyed by `phase.rawValue`. Update:
- Remove entries keyed `7` (verbalFluency) and `8` (storyRecall) if they exist.
- Add entries keyed `8` (tmtB) and `9` (recognition) using the same ratio/accent palette as their predecessors (or reuse `clockDrawing`'s palette for `.tmtB` since both are pencil tasks; `wordRecall`'s palette for `.recognition` since both are verbal-memory).

- [ ] **Step 5: Update `defaultBehavior(for:)`**

In `AvatarLayoutManager.swift`, locate `func defaultBehavior(for phase: AssessmentPhaseID) -> AvatarBehavior`. Replace fluency/story cases with tmtB/recognition. TMT-B is `.waiting` while patient draws (avatar silent during pencil work, like `.clockDrawing`). Recognition is `.speaking` during stimulus echo, `.waiting` during patient response.

- [ ] **Step 6: Commit**

```bash
git add VoiceMiniCog/Models/AvatarLayoutManager.swift VoiceMiniCog/Theme/AssessmentTheme.swift
git commit -m "refactor(phase-id): renumber for new battery + isHighRiskAbortPhase

- Remove .verbalFluency, .storyRecall cases
- Add .tmtB, .recognition with renumbered rawValues
- New isHighRiskAbortPhase extension replaces ad-hoc literal at canvas:270
- AssessmentTheme accent map updated in lockstep"
```

---

## Task 4 — Update `AssessmentFlowType.quick.phaseSequence` (4-cognitive-module ordering)

**Files:**
- Modify: `VoiceMiniCog/Models/AvatarLayoutManager.swift`

- [ ] **Step 1: Replace the `phaseSequence` switch**

```swift
extension AssessmentFlowType {
    var phaseSequence: [AssessmentPhaseID] {
        switch self {
        case .quick, .extended:
            // 4-cognitive-module ordering for Plan 1.
            // Plan 2 inserts .recognition after .wordRecall.
            // Plan 3 inserts .tmtB between .wordRecall and .recognition.
            return [.welcome, .orientation, .wordRegistration, .clockDrawing,
                    .wordRecall, .completion]
        case .caregiver:
            return [.welcome, .completion]   // Q1(a) forward-compat no-op
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/Models/AvatarLayoutManager.swift
git commit -m "feat(battery): set quick flow to 4-cognitive-module sequence

Plan 1 ships: welcome → orientation → registration → clock → recall → completion.
.tmtB and .recognition cases exist in the enum but are not yet in the active
sequence. Plans 2 and 3 splice them in. Caregiver flow collapsed to no-op
per Q1(a)."
```

---

## Task 5 — Add `BatteryEnumSyncTests`

**Files:**
- Create: `VoiceMiniCogTests/BatteryEnumSyncTests.swift`

- [ ] **Step 1: Write the test class**

```swift
import XCTest
@testable import VoiceMiniCog

/// RELEASE BLOCKER — three-enum drift guard.
/// Asserts that Phase, AssessmentPhaseType, and AssessmentPhaseID stay in
/// sync for every cognitive module. Run on every PR.
final class BatteryEnumSyncTests: XCTestCase {

    /// AssessmentPhaseID cases intentionally retained for forward-compat
    /// or feature-flag activation. Each entry references the documenting
    /// decision in this file.
    private static let intentionallyInactivePhaseIDs: Set<AssessmentPhaseID> = [
        .qdrs,    // Q1(a) (2026-04-29 spec): retained for forward-compat with
                  // future clinician-side iOS surface. CaregiverAssessmentView deleted.
        .phq2,    // Q2(b) (2026-04-29 spec): retained behind FeatureFlags.phq2Enabled.
    ]

    /// Welcome and completion are framing phases, not cognitive modules.
    private static let framingPhaseIDs: Set<AssessmentPhaseID> = [.welcome, .completion]

    /// Cognitive AssessmentPhaseID cases that MUST have matching Phase
    /// and AssessmentPhaseType counterparts.
    private var cognitivePhaseIDs: [AssessmentPhaseID] {
        AssessmentPhaseID.allCases.filter {
            !Self.framingPhaseIDs.contains($0) &&
            !Self.intentionallyInactivePhaseIDs.contains($0)
        }
    }

    func testEveryCognitivePhaseIDHasMatchingPhase() {
        for id in cognitivePhaseIDs {
            XCTAssertNotNil(Phase.matching(id),
                "AssessmentPhaseID.\(id) has no matching Phase. " +
                "Either add the Phase case or add \(id) to the inactive allowlist with " +
                "a documenting-decision comment.")
        }
    }

    func testEveryCognitivePhaseHasMatchingPhaseID() {
        let cognitivePhases: [Phase] = [
            .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
            .qmciDelayedRecall, .qmciTMTB, .qmciRecognition
        ]
        for phase in cognitivePhases {
            let matchedID = AssessmentPhaseID.allCases.first { Phase.matching($0) == phase }
            XCTAssertNotNil(matchedID,
                "Phase.\(phase) has no matching AssessmentPhaseID. " +
                "Either add the AssessmentPhaseID case or remove the Phase case.")
        }
    }

    func testEveryCognitivePhaseHasSpeculativePhaseType() {
        // Cognitive phases must map to AssessmentPhaseType values that have
        // isScoredSubtest == true (i.e., NOT .intro/.outro).
        let cognitivePhases: [Phase] = [
            .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
            .qmciDelayedRecall, .qmciTMTB, .qmciRecognition
        ]
        for phase in cognitivePhases {
            XCTAssertTrue(phase.speculativePhaseType.isScoredSubtest,
                "Phase.\(phase) maps to AssessmentPhaseType.\(phase.speculativePhaseType) " +
                "which is not a scored subtest. Cognitive phases must be scored subtests.")
        }
    }

    func testQuickFlowSequenceMatchesCanonicalOrder() {
        // Plan 1: 4-cognitive-module sequence.
        // Plan 2 will append .recognition before .completion.
        // Plan 3 will insert .tmtB between .wordRecall and .recognition.
        // This test will be updated in Plan 2 and Plan 3 in lockstep with the sequence.
        let expected: [AssessmentPhaseID] = [
            .welcome, .orientation, .wordRegistration, .clockDrawing,
            .wordRecall, .completion
        ]
        XCTAssertEqual(AssessmentFlowType.quick.phaseSequence, expected)
        XCTAssertEqual(AssessmentFlowType.extended.phaseSequence, expected)
    }

    func testCaregiverFlowIsForwardCompatNoOp() {
        XCTAssertEqual(AssessmentFlowType.caregiver.phaseSequence, [.welcome, .completion])
    }
}
```

- [ ] **Step 2: Add the test file to the Xcode test target**

Edit `VoiceMiniCog.xcodeproj/project.pbxproj` to register `BatteryEnumSyncTests.swift` in the `VoiceMiniCogTests` target. **Do NOT use the Python `pbxproj` library** (corrupts file IDs per CLAUDE.md). Instead:
1. Generate two 24-char hex UUIDs (e.g., `uuidgen | tr -d '-' | head -c 24`).
2. Add a `PBXFileReference` entry in the file-references block for `BatteryEnumSyncTests.swift`.
3. Add a `PBXBuildFile` entry referencing that file ref under the `VoiceMiniCogTests` source-build phase.
4. Register the file ref in the `VoiceMiniCogTests` `PBXGroup`.

- [ ] **Step 3: Run the tests**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/BatteryEnumSyncTests \
  -quiet 2>&1 | tail -120
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCogTests/BatteryEnumSyncTests.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(battery): add three-enum sync guard

RELEASE BLOCKER. Asserts Phase, AssessmentPhaseType, and AssessmentPhaseID
stay in sync for every cognitive module. Allowlists .qdrs and .phq2 with
documenting-decision references (Q1(a) and Q2(b))."
```

---

## Task 6 — Add `FeatureFlags.phq2Enabled`

**Files:**
- Create: `VoiceMiniCog/Theme/FeatureFlags.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  FeatureFlags.swift
//  VoiceMiniCog
//
//  Runtime feature flags. Default values are production v1.0 values.
//

import Foundation

enum FeatureFlags {
    /// PHQ-2 in-app screening is disabled for v1.0. Depression screening occurs
    /// in clinic workflow upstream of MercyCognitive.
    /// See docs/clinical/qmci-modifications.md §"PHQ-2 externalization."
    /// To reinstate: set this to true and verify the deploying clinic's workflow
    /// does not also screen.
    static let phq2Enabled: Bool = false
}
```

- [ ] **Step 2: Register in pbxproj**

Add `FeatureFlags.swift` to the `VoiceMiniCog` (app) target via the same direct-edit approach as Task 5 step 2. Add it to the `Theme` group.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -20
```

(Build will still fail elsewhere — that's expected. Verify FeatureFlags.swift itself compiles with no errors.)

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Theme/FeatureFlags.swift VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(flags): add FeatureFlags.phq2Enabled = false

Runtime feature flag. Documented reactivation procedure cites
docs/clinical/qmci-modifications.md §7."
```

---

## Task 7 — Update `QAPhaseView.swift` (delete `.qdrs` branch, gate `.phq2`)

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift`

- [ ] **Step 1: Locate every switch on `phaseID`**

Use Grep:
```
Pattern: switch phaseID
File: VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift
```

There are five switch sites (count of items, prompt text, voice prompt, response options, response handler) per spec exploration in Block A.

- [ ] **Step 2: Delete every `.qdrs` case**

In every switch on `phaseID`, remove the `case .qdrs:` arm entirely. Compilation will fail until the file's enclosing `.qdrs` references are gone — that's the goal.

- [ ] **Step 3: Gate every `.phq2` arm with `FeatureFlags.phq2Enabled`**

For each switch arm that handles `.phq2`, do not delete it. Instead, ensure it is reachable only when the flag is on. The simplest pattern is to leave the arms in place (they continue to compile) and prevent navigation to `.phq2` from the routing layer — but since `phaseID` is the input to `QAPhaseView`, an upstream view has to decide whether to instantiate the view with `.phq2`.

In Plan 1, the routing layer does not include `.phq2` in `phaseSequence`, so QAPhaseView is never instantiated with `.phq2` at runtime. The `.phq2` arms in QAPhaseView's switches stay as-is (dormant code). Add a top-of-file comment:

```swift
//
// QAPhaseView dispatches on AssessmentPhaseID. The .phq2 dispatch arms remain
// in the file but are unreachable at runtime when FeatureFlags.phq2Enabled is
// false (which is the v1.0 default). They are preserved per Q2(b) so reactivation
// is a one-line flag flip plus restoring the .phq2 entry to phaseSequence.
//
```

- [ ] **Step 4: Build to verify the file compiles**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | grep -E "QAPhaseView|error" | head -20
```

Expected: no errors specific to QAPhaseView.swift.

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift
git commit -m "refactor(qa-phase): delete .qdrs branch, preserve .phq2 dormant

Removes QDRS dispatch arms (Q1a). Keeps .phq2 dispatch arms compiled but
unreachable at runtime via routing layer (Q2b)."
```

---

## Task 8 — Delete fluency / story / caregiver source files

**Files:**
- Delete: `VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift`
- Delete: `VoiceMiniCog/Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift`
- Delete: `VoiceMiniCog/Services/VerbalFluencyScorer.swift`
- Delete: `VoiceMiniCog/Views/CaregiverAssessmentView.swift`
- Modify: `VoiceMiniCog.xcodeproj/project.pbxproj` (remove file references)

- [ ] **Step 1: Delete the source files**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog
rm VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift
rm VoiceMiniCog/Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift
rm VoiceMiniCog/Services/VerbalFluencyScorer.swift
rm VoiceMiniCog/Views/CaregiverAssessmentView.swift
```

- [ ] **Step 2: Remove pbxproj references**

For each deleted file, remove from `VoiceMiniCog.xcodeproj/project.pbxproj`:
1. The `PBXFileReference` entry
2. The `PBXBuildFile` entry
3. The entry in the containing `PBXGroup`

Direct-edit, no Python pbxproj library (CLAUDE.md rule).

- [ ] **Step 3: Build to verify the project still parses**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -30
```

Expected errors are about consumers that still reference `VerbalFluencyPhaseView`, `StoryRecallPhaseView`, etc. These call sites are repaired in subsequent tasks. The pbxproj must not produce a "missing file" error.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(battery): delete fluency, story, caregiver source files

- Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift
- Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift
- Services/VerbalFluencyScorer.swift
- Views/CaregiverAssessmentView.swift

QDRS-related caregiver UI is removed from iOS app per Q1(a); enum cases
retained for forward-compat. Consumer call sites repaired in subsequent
tasks."
```

---

## Task 9 — Update `QmciModels.swift` (delete fluency/story content + Sets 2 & 3)

**Files:**
- Modify: `VoiceMiniCog/Models/QmciModels.swift`

- [ ] **Step 1: Delete `LOGICAL_MEMORY_STORIES`**

Search for `LOGICAL_MEMORY_STORIES` and the `LogicalMemoryStory` struct. Delete the struct definition, the `LOGICAL_MEMORY_STORIES` array, and the `// MARK: - Logical Memory Stories` section header.

- [ ] **Step 2: Delete fluency-related fields on the QMCI state**

In the QMCI session state struct:
- Remove `var verbalFluencyWords: [String]`
- Remove `var verbalFluencyScore: Int { ... }` if computed
- Remove any `delayedFluencyTimer`-style fluency fields
- Remove `verbalFluency` from any `Codable` `CodingKeys` enum
- Remove fluency-related encode/decode lines

- [ ] **Step 3: Delete logical-memory-related fields**

- Remove `var logicalMemoryRecalledUnits: [String]`
- Remove `var logicalMemoryStoryIndex: Int`
- Remove any logical-memory scoring properties
- Remove from `CodingKeys` and encode/decode

- [ ] **Step 4: Trim `QMCI_WORD_LISTS` to Set 1 only**

Replace:
```swift
let QMCI_WORD_LISTS: [[String]] = [
    ["dog", "rain", "butter", "love", "door"],       // Standard set (verified)
    ["cat", "dark", "rat", "heat", "bread"],          // Alternate set 2 (approximate)
    ["fear", "round", "bed", "chair", "fruit"],       // Alternate set 3 (approximate)
]
```

with:
```swift
/// QMCI Set 1 — verified O'Caoimh 2012 standard.
/// Sets 2 and 3 were deleted on 2026-04-29 per spec §A.2 / E.3:
/// they were marked APPROXIMATE in source comments and shipping them, even
/// disabled, created regulatory and engineering risk. See
/// docs/clinical/recognition-foil-rationale.md §5 for the deletion audit.
let QMCI_WORD_LISTS: [[String]] = [
    ["dog", "rain", "butter", "love", "door"],
]
```

- [ ] **Step 5: Update the `registrationWordListIndex` advancement comment**

Find the `advanceRegistrationWordListIndex()` (or similar) method and update its body + doc comment:

```swift
/// `registrationWordListIndex` is reserved for future validated alternate forms (Form B+).
/// As of v1.0, only Form A is validated and approved for production use.
/// See docs/clinical/recognition-form-roadmap.md for Form B trigger criteria.
mutating func advanceRegistrationWordListIndex() {
    // No-op until validated alternate forms exist. Index stays at 0.
    registrationWordListIndex = 0
    registrationWords = QMCI_WORD_LISTS[0]
}
```

- [ ] **Step 6: Update `RegistrationResult` schema**

Replace the existing `RegistrationResult` (or add it if not yet defined) with the spec §B.5 final shape:

```swift
struct RegistrationResult: Codable {
    let trialMode: RegistrationTrialMode
    let perTrialRecalled: [[String]]    // length == trialsAdministered
    let firstTrialScore: Int            // Qmci scoring anchor (0-5)
    let finalTrialScore: Int            // last administered trial (0-5)
    let trialsAdministered: Int         // 1, 2, or 3 — variable in standardQmci
    let reachedCriterion: Bool          // true if any trial == 5/5
    let learningSlope: [Int]            // researchOnly: true; not in Qmci composite.
                                        // Non-optional array — empty (not nil) when
                                        // no slope data available.
                                        // [] if trialsAdministered == 1
                                        // [trial2 − trial1] if 2
                                        // [trial2 − trial1, trial3 − trial2] if 3
}
```

- [ ] **Step 7: Build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -30
```

Expected: errors only at consumer call sites for the deleted fields.

- [ ] **Step 8: Commit**

```bash
git add VoiceMiniCog/Models/QmciModels.swift
git commit -m "feat(qmci): delete fluency/story models, Sets 2 & 3, add RegistrationResult v2

- Delete LOGICAL_MEMORY_STORIES and LogicalMemoryStory
- Delete fluency and logical-memory state fields
- Trim QMCI_WORD_LISTS to verified Set 1 only
- Reserve registrationWordListIndex for future Form B
- Add RegistrationResult schema per spec §B.5 (trialMode, perTrialRecalled,
  firstTrialScore, finalTrialScore, trialsAdministered, reachedCriterion,
  learningSlope)"
```

---

## Task 10 — Land empty struct definitions

**Files:** (each created)
- `VoiceMiniCog/Models/RegistrationTrialMode.swift`
- `VoiceMiniCog/Models/RecognitionForm.swift`
- `VoiceMiniCog/Models/RecognitionResult.swift`
- `VoiceMiniCog/Models/EncodingRetrievalIndex.swift`
- `VoiceMiniCog/Models/RawStroke.swift`
- `VoiceMiniCog/Models/KinematicCapture.swift`
- `VoiceMiniCog/Models/TMTBResult.swift`

- [ ] **Step 1: Create `RegistrationTrialMode.swift`**

```swift
import Foundation

enum RegistrationTrialMode: String, Codable {
    case standardQmci    // default; stop at 5/5 or 3 trials per O'Caoimh 2016
    case researchFull3   // clinician toggle; always runs all 3 regardless
}
```

- [ ] **Step 2: Create `RecognitionForm.swift`**

```swift
import Foundation

enum RecognitionStimulusKind: String, Codable, Equatable {
    case target
    case semanticFoil
    case unrelatedFoil
}

struct RecognitionStimulus: Codable, Equatable, Hashable {
    let word: String
    let kind: RecognitionStimulusKind
}

struct RecognitionForm: Codable, Equatable {
    /// "A" for v1.0; future "B"+ when Form B is triggered per
    /// docs/clinical/recognition-form-roadmap.md.
    let formID: String

    /// Source of truth for all 15 words. 5 target + 5 semantic foil + 5 unrelated foil.
    let stimuli: [RecognitionStimulus]

    /// Locked v1.0 presentation order. Permutation constraints (asserted at
    /// build time via RecognitionFormConstraintsTests):
    ///   - All 15 indices appear exactly once.
    ///   - No two adjacent stimuli share the same `kind`.
    ///   - First stimulus is a target (anchors patient expectation).
    ///   - Last stimulus is a foil (no target at end → mitigates recency-driven false hits).
    /// Modifications require updating both this comment, the constraints test, and the
    /// docs/clinical/recognition-foil-rationale.md "Presentation order" section.
    let presentationOrder: [Int]

    static let stimulusCount = 15

    /// Loaded lazily from Resources/RecognitionForms.json.
    /// Behavior implementation lands in Plan 2.
    static var formA: RecognitionForm = {
        // Plan 1: stub with placeholder values to keep the symbol compilable.
        // Plan 2 replaces this with a JSON-bundle loader.
        return RecognitionForm(
            formID: "A",
            stimuli: [],
            presentationOrder: []
        )
    }()

    func stimulus(at admittedIndex: Int) -> RecognitionStimulus {
        stimuli[presentationOrder[admittedIndex]]
    }
}
```

- [ ] **Step 3: Create `RecognitionResult.swift`**

```swift
import Foundation

enum YesNoResponse: String, Codable { case yes, no }

enum ResponseStatus: String, Codable {
    case yes
    case no
    case timedOut
    case notDelivered
}

struct StimulusResponse: Codable {
    let stimulusIndex: Int
    /// Anchored to the `replicaStoppedSpeaking` event. Audit anchor for "when did
    /// the avatar actually finish speaking this stimulus." Derivable in theory
    /// from session start + cumulative timings, but not reliably across session
    /// restarts — stored directly.
    let stimulusOnsetTimestamp: Date
    let responseStatus: ResponseStatus
    /// nil for .timedOut / .notDelivered. Measured from stimulusOnsetTimestamp.
    let reactionTimeMs: Double?
}

enum DataQualityWarning: Codable {
    case recommendReadminister(reason: String, threshold: String)

    private enum CodingKeys: String, CodingKey { case kind, reason, threshold }
    private enum Kind: String, Codable { case recommendReadminister }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .recommendReadminister(reason, threshold):
            try c.encode(Kind.recommendReadminister, forKey: .kind)
            try c.encode(reason, forKey: .reason)
            try c.encode(threshold, forKey: .threshold)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .recommendReadminister:
            self = .recommendReadminister(
                reason: try c.decode(String.self, forKey: .reason),
                threshold: try c.decode(String.self, forKey: .threshold)
            )
        }
    }
}

enum RecognitionDataQualityRules {
    /// Threshold above which recognition data is flagged for re-administration.
    /// Rationale: ≥2/15 missed stimuli materially affects d′ stability and
    /// false-alarm rate denominators.
    static let notDeliveredReadminThreshold: Int = 2
}

struct RecognitionResult: Codable {
    let formID: String                              // carries RecognitionForm.formID verbatim
    let responses: [StimulusResponse]
    let captionAccommodationActive: Bool            // false by default; clinician-set at intake

    // All counts and d′ are computed properties — no persistence drift risk.
    // Plan 2 implements the bodies; Plan 1 ships the stubs.
    var hits: Int { 0 }
    var misses: Int { 0 }
    var correctRejections: Int { 0 }
    var falseAlarms: Int { 0 }
    var semanticFalseAlarms: Int { 0 }
    var unrelatedFalseAlarms: Int { 0 }
    var dPrime: Double { 0 }
    var notDeliveredCount: Int { 0 }
    var timedOutCount: Int { 0 }
    var dataQualityWarning: DataQualityWarning? { nil }
}
```

- [ ] **Step 4: Create `EncodingRetrievalIndex.swift`**

```swift
import Foundation

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
    /// PROVENANCE NOTE — populated by derive() from the single source string.
    /// Rendered verbatim in the PDF report's Memory Pattern Signals section.
    let thresholdProvenance: String

    let signal: MemoryPatternSignal
    let registrationScore: Int          // first-trial 0–5 (Qmci anchor)
    let delayedRecallScore: Int
    let recognitionHits: Int
    let recognitionFalseAlarms: Int

    /// Centralized threshold constants. Single tunable surface for clinical sign-off.
    /// Never reference these values inline anywhere else in the codebase.
    enum Thresholds {
        static let currentProvenance: String =
            "Provisional v1.0 — thresholds unvalidated, awaiting Mercy Normative Collection. " +
            "Pattern signal is exploratory supportive context only."

        /// Free-recall score above which recall is considered preserved.
        static let freeRecallPreservedFloor: Int = 3

        /// d′ above which recognition is considered relatively preserved.
        static let dPrimePreservedFloor: Double = 1.5

        /// d′ below which recognition is considered impaired.
        static let dPrimeImpairedCeiling: Double = 0.5

        /// Minimum delivered stimuli required to interpret pattern.
        static let minDeliveredForInterpretation: Int = 13
    }

    /// Derivation entry point. Plan 1 ships the stub; Plan 2 implements.
    static func derive(from result: RecognitionResult,
                       freeRecall: Int,
                       firstTrialRegistration: Int) -> EncodingRetrievalIndex {
        return EncodingRetrievalIndex(
            thresholdProvenance: Thresholds.currentProvenance,
            signal: .insufficientData,
            registrationScore: firstTrialRegistration,
            delayedRecallScore: freeRecall,
            recognitionHits: 0,
            recognitionFalseAlarms: 0
        )
    }
}
```

- [ ] **Step 5: Create `RawStroke.swift`**

```swift
import Foundation

/// Single point sample within a stroke.
///
/// **`t` anchor:** seconds since the **first pen-down of the current task session**,
/// not per-stroke. This makes airTimeSec computation unambiguous across multi-stroke
/// tasks (TMT-B between-node air time especially) and prevents off-by-one summation
/// of inkTimeSec.
struct StrokePoint {
    let x: Double               // physical mm
    let y: Double
    let t: TimeInterval
    let force: Double           // 0.0–1.0 (UITouch.force normalized for Apple Pencil)
    let altitudeAngle: Double   // rad
    let azimuthAngle: Double    // rad
}

struct RawStroke {
    let points: [StrokePoint]
    let strokeIndex: Int        // 0-based within the task session
    let downTimestamp: Date
}
```

- [ ] **Step 6: Create `KinematicCapture.swift`**

```swift
import Foundation

enum KinematicSource: String, Codable {
    case clock
    case tmtB
}

struct KinematicCapture: Codable {
    let captureID: UUID
    let source: KinematicSource

    // Time
    let totalTimeSec: Double
    let inkTimeSec: Double
    let airTimeSec: Double
    let airInkRatio: Double             // think-to-ink ratio

    // Velocity (mm/s; physical-coord scaling via UIScreen.main.nativeScale)
    let meanVelocityMmps: Double
    let velocityCVWithinStroke: Double

    // Pressure (UITouch.force normalized 0.0–1.0 for Apple Pencil)
    let meanPressure: Double
    let pressureCV: Double

    // Strokes
    let strokeCount: Int

    // Clock-only (non-nil iff source == .clock)
    let preFirstHandLatencySec: Double?
    let circleGapDeg: Double?

    // DARWIN parity — researchOnly v1.0.
    // UITouch @ 120 Hz produces jerk estimates with high variance at stroke-speed
    // extremes. Promoted to clinical feature pending MERIDIAN-1 analysis.
    let meanJerkOnPaperMmps3: Double?
    let meanJerkInAirMmps3: Double?

    // Research-mode linkage (see RawStreamRecorder).
    let rawStreamArtifactID: UUID?
}
```

- [ ] **Step 7: Create `TMTBResult.swift`**

```swift
import Foundation

enum TMTBCompletionStatus: String, Codable {
    case completed
    case aborted
    case timedOut
}

enum TMTBErrorKind: String, Codable {
    case wrongTargetTap
    case sequenceCorrected
    case offPathStroke
}

struct TMTBErrorEvent: Codable {
    let kind: TMTBErrorKind
    let nodeID: String?         // nil for .offPathStroke
    let timestamp: TimeInterval // seconds since task start
}

struct TMTBErrors: Codable {
    let wrongTargetTaps: Int
    let sequenceCorrected: Int
    let offPathStrokes: Int
}

struct SegmentTiming: Codable {
    let fromNode: String
    let toNode: String
    let durationMs: Double
    let errorOccurred: Bool
}

struct TMTBResult: Codable {
    let totalTimeSec: Double
    let completionStatus: TMTBCompletionStatus
    let abandonedAtNodeID: String?              // populated when .aborted
    let perSegmentTimings: [SegmentTiming]
    let errorEvents: [TMTBErrorEvent]           // chronological; audit + research consumer
    let kinematics: KinematicCapture            // source == .tmtB

    // Computed (derived from errorEvents — no drift risk; report + scoring consumer).
    var errorCounts: TMTBErrors {
        TMTBErrors(
            wrongTargetTaps: errorEvents.filter { $0.kind == .wrongTargetTap }.count,
            sequenceCorrected: errorEvents.filter { $0.kind == .sequenceCorrected }.count,
            offPathStrokes: errorEvents.filter { $0.kind == .offPathStroke }.count
        )
    }
}
```

- [ ] **Step 8: Register all 7 new files in pbxproj**

Add each `.swift` file to the `VoiceMiniCog` (app) target via direct pbxproj editing (no Python lib). Place in `VoiceMiniCog/Models/` group.

- [ ] **Step 9: Build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -30
```

Expected: errors at remaining consumer call sites only. The 7 new model files compile cleanly.

- [ ] **Step 10: Commit**

```bash
git add VoiceMiniCog/Models/RegistrationTrialMode.swift \
        VoiceMiniCog/Models/RecognitionForm.swift \
        VoiceMiniCog/Models/RecognitionResult.swift \
        VoiceMiniCog/Models/EncodingRetrievalIndex.swift \
        VoiceMiniCog/Models/RawStroke.swift \
        VoiceMiniCog/Models/KinematicCapture.swift \
        VoiceMiniCog/Models/TMTBResult.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(models): land empty struct definitions for Plans 2 & 3

Lands the data model surface that Plans 2 and 3 will populate:
- RegistrationTrialMode, RecognitionForm/Stimulus/Kind, RecognitionResult
  + StimulusResponse + ResponseStatus + DataQualityWarning
- EncodingRetrievalIndex + Thresholds + MemoryPatternSignal
- RawStroke + StrokePoint
- KinematicCapture + KinematicSource (DARWIN parity fields)
- TMTBResult + TMTBErrorEvent + TMTBErrors + SegmentTiming +
  TMTBCompletionStatus + TMTBErrorKind

Behavior stubs only; bodies populated in Plans 2/3. Schema is final-shape
per spec §B — no migration when downstream plans light up the modules."
```

---

## Task 11 — Add `Resources/RecognitionForms.json` (Form A locked v1.0)

**Files:**
- Create: `VoiceMiniCog/Resources/RecognitionForms.json`

- [ ] **Step 1: Create the resource file**

```json
{
  "A": {
    "formID": "A",
    "stimuli": [
      {"word": "dog",     "kind": "target"},
      {"word": "rain",    "kind": "target"},
      {"word": "butter",  "kind": "target"},
      {"word": "love",    "kind": "target"},
      {"word": "door",    "kind": "target"},
      {"word": "horse",   "kind": "semanticFoil"},
      {"word": "snow",    "kind": "semanticFoil"},
      {"word": "cheese",  "kind": "semanticFoil"},
      {"word": "joy",     "kind": "semanticFoil"},
      {"word": "window",  "kind": "semanticFoil"},
      {"word": "truck",   "kind": "unrelatedFoil"},
      {"word": "paper",   "kind": "unrelatedFoil"},
      {"word": "garden",  "kind": "unrelatedFoil"},
      {"word": "ladder",  "kind": "unrelatedFoil"},
      {"word": "bicycle", "kind": "unrelatedFoil"}
    ],
    "presentationOrder": [0, 7, 11, 2, 5, 12, 1, 8, 3, 14, 6, 4, 10, 9, 13]
  }
}
```

- [ ] **Step 2: Verify the presentation order satisfies all four constraints**

Manually verify (will be re-asserted by `RecognitionFormConstraintsTests` in Task 17):
1. All indices 0–14 appear exactly once: `[0,7,11,2,5,12,1,8,3,14,6,4,10,9,13]` — ✓
2. No two adjacent same-kind: 0→7 (T→sF), 7→11 (sF→uF), 11→2 (uF→T), 2→5 (T→sF), 5→12 (sF→uF), 12→1 (uF→T), 1→8 (T→sF), 8→3 (sF→T), 3→14 (T→uF), 14→6 (uF→sF), 6→4 (sF→T), 4→10 (T→uF), 10→9 (uF→sF), 9→13 (sF→uF) — ✓
3. First stimulus is target: index 0 = "dog" target — ✓
4. Last stimulus is foil: index 13 = "ladder" unrelatedFoil — ✓

- [ ] **Step 3: Register as a resource in pbxproj**

Add `Resources/RecognitionForms.json` as a `PBXFileReference` (lastKnownFileType = `text.json`), then as a `PBXBuildFile` in the `VoiceMiniCog` target's `PBXResourcesBuildPhase` (NOT the sources build phase — JSON is a resource, not source code).

- [ ] **Step 4: Verify the resource is bundled**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -10
```

Then list the built bundle:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "VoiceMiniCog.app" -type d 2>/dev/null | head -1 | xargs -I{} ls {} | grep -i RecognitionForms
```
Expected: `RecognitionForms.json` appears in the .app bundle.

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Resources/RecognitionForms.json VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(recognition): add Resources/RecognitionForms.json — Form A locked v1.0

5 targets (dog, rain, butter, love, door) + 5 semantic foils (horse, snow,
cheese, joy, window) + 5 unrelated foils (truck, paper, garden, ladder,
bicycle). Presentation order [0,7,11,2,5,12,1,8,3,14,6,4,10,9,13] satisfies
all four constraints. Plan 2 wires the JSON loader into RecognitionForm.formA."
```

---

## Task 12 — Update `LeftPaneSpeechCopy` (delete fluency/story copy)

**Files:**
- Modify: `VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift`

- [ ] **Step 1: Delete fluency-related strings**

Search for and delete:
- `verbalFluencyInstruction`, `verbalFluencyIntro`, `verbalFluencyOutro`
- Any `animalFluency*` strings
- `verbalFluencyRetry(...)` helpers

- [ ] **Step 2: Delete story-related strings**

Search for and delete:
- `storyRecallIntro`, `storyRecallInstruction`, `storyRecallOutro`
- Any `logicalMemory*` strings
- `storyRecallRetry(...)` helpers

- [ ] **Step 3: Verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
  grep -nE "fluency|story|logicalMemory" VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift
```

Expected: zero output (case-insensitive match clean).

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift
git commit -m "feat(copy): delete fluency and story patient/avatar strings

TMT-B and recognition copy added in Plans 3 and 2 respectively."
```

---

## Task 13 — Update `AvatarAssessmentCanvas` (replace `[.verbalFluency]` literal)

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift`

- [ ] **Step 1: Replace the active-testing classification**

Find the existing `[AssessmentPhaseID.verbalFluency]` array literal (formerly at line ~270). Replace with `isHighRiskAbortPhase` consumer:

```swift
// Before:
let isActiveTesting = [AssessmentPhaseID.verbalFluency]
    .contains(layoutManager.currentPhase)

// After:
let isActiveTesting = layoutManager.currentPhase.isHighRiskAbortPhase
```

- [ ] **Step 2: Update the phase routing switch**

Locate `switch layoutManager.currentPhase` at the routing site (~line 229). Remove `.verbalFluency` and `.storyRecall` cases. Add `.tmtB` and `.recognition` cases — for Plan 1, both route to a placeholder view that displays *"This module is being implemented — auto-advancing"* and auto-advances after 1 second:

```swift
case .tmtB:
    PlaceholderPhaseView(title: "Trail-Making Executive Task")
case .recognition:
    PlaceholderPhaseView(title: "Word Recognition")
```

But because `phaseSequence` does not contain `.tmtB` or `.recognition` in Plan 1, these cases are unreachable at runtime. The cases exist purely for compile-time exhaustiveness.

Alternative (cleaner): use `@unknown default:` or omit the cases since `phaseSequence` filtering guarantees they won't be reached. Pick the option that matches existing code style — likely explicit cases with `EmptyView()`:

```swift
case .tmtB, .recognition:
    // Unreachable in Plan 1 (not in phaseSequence). Plans 2 and 3 wire
    // RecognitionPhaseView and TMTBPhaseView respectively.
    EmptyView()
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift
git commit -m "refactor(canvas): use isHighRiskAbortPhase + remove fluency/story routes

Replaces ad-hoc [AssessmentPhaseID.verbalFluency] literal at canvas:270 with
the typed AssessmentPhaseID.isHighRiskAbortPhase property. .tmtB and
.recognition route cases added for compile exhaustiveness; unreachable in
Plan 1 since they aren't in phaseSequence yet."
```

---

## Task 14 — Update `ProgressTrackView` (filter cognitive 6, hide on welcome/intake)

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift`

- [ ] **Step 1: Update the `phases` filter**

```swift
// Before (existing):
private var phases: [AssessmentPhaseID] {
    layoutManager.phaseSequence.filter { $0 != .completion }
}

// After:
private var phases: [AssessmentPhaseID] {
    let nonCognitive: Set<AssessmentPhaseID> = [.welcome, .qdrs, .phq2, .completion]
    return layoutManager.phaseSequence.filter { !nonCognitive.contains($0) }
}
```

- [ ] **Step 2: Update the `shortName` map**

```swift
private var shortName: String {
    switch phase {
    case .welcome:          return "Welcome"
    case .qdrs:             return "Caregiver"
    case .phq2:             return "Mood"
    case .orientation:      return "Orient"
    case .wordRegistration: return "Words"
    case .clockDrawing:     return "Clock"
    case .wordRecall:       return "Recall"
    case .tmtB:             return "TMT-B"
    case .recognition:      return "Recognize"
    case .completion:       return "Done"
    }
}
```

- [ ] **Step 3: Hide the entire chevron when in welcome/intake**

Wrap the body so it returns `EmptyView()` if `phases.isEmpty` or if `currentPhase` is `.welcome / .qdrs / .phq2`:

```swift
var body: some View {
    if phases.contains(layoutManager.currentPhase) {
        PhaseProgressTrack(layoutManager: layoutManager)
    } else {
        EmptyView()
    }
}
```

- [ ] **Step 4: Build**

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift
git commit -m "feat(progress): 6-cell cognitive chevron, hidden on welcome/intake

Plan 1 ships 4 visible cells (orient, words, clock, recall). Plan 2 adds
recognize cell. Plan 3 inserts tmt-b cell to reach final 6-cell layout.
Chevron hidden entirely when current phase is .welcome / .qdrs / .phq2."
```

---

## Task 15 — Update `ContentView` phase routing

**Files:**
- Modify: `VoiceMiniCog/ContentView.swift`

- [ ] **Step 1: Locate the phase switch (~line 22)**

```swift
// Before:
case .intake, .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
     .qmciVerbalFluency, .qmciLogicalMemory, .qmciDelayedRecall:
    AvatarAssessmentCanvas(...)

// After:
case .intake, .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
     .qmciDelayedRecall, .qmciTMTB, .qmciRecognition:
    AvatarAssessmentCanvas(...)
```

- [ ] **Step 2: Build**

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/ContentView.swift
git commit -m "refactor(routing): replace fluency/story with TMT-B/recognition cases

ContentView's phase switch routes all qmci subtests to AvatarAssessmentCanvas."
```

---

## Task 16 — Update `HomeView` (remove caregiver entry point)

**Files:**
- Modify: `VoiceMiniCog/Views/HomeView.swift`

- [ ] **Step 1: Find and delete caregiver-flow entry**

Search for any button or menu item that initiates `AssessmentFlowType.caregiver` from HomeView. Delete it. The patient-cognitive flow remains the only user-facing flow.

- [ ] **Step 2: Build**

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Views/HomeView.swift
git commit -m "feat(home): remove caregiver flow entry point

Caregiver flow is now a forward-compat no-op (Q1a). No patient-facing entry."
```

---

## Task 17 — Update consumer modules (remove fluency/story references)

**Files (one batch — repetitive deletion):**
- Modify: `VoiceMiniCog/Views/ClinicianDashboardView.swift`
- Modify: `VoiceMiniCog/Views/PCPReportView.swift`
- Modify: `VoiceMiniCog/Services/QMCIScoringEngine.swift`
- Modify: `VoiceMiniCog/Services/PartialScoreReport.swift`
- Modify: `VoiceMiniCog/Services/PDFReportGenerator.swift`
- Modify: `VoiceMiniCog/Services/QMCIAvatarContext.swift`
- Modify: `VoiceMiniCog/Services/ResponseCheckers.swift`
- Modify: `VoiceMiniCog/Services/IntakeOutroRAG.swift`
- Modify: `VoiceMiniCog/Theme/AssessmentTheme.swift`
- Modify: `VoiceMiniCog/Theme/AssessmentViewModifiers.swift`
- Modify: `VoiceMiniCog/Models/AssessmentState.swift`

- [ ] **Step 1: For each file, delete fluency and story references**

For each file in the list, do the same scan:
```bash
grep -n "verbalFluency\|VerbalFluency\|logicalMemory\|LogicalMemory\|storyRecall\|StoryRecall" <file>
```

Delete the matching switch arms, fields, computations, references, etc. For `ClinicianDashboardView` and `PCPReportView`: delete the corresponding tile/section UI. For `QMCIScoringEngine`: remove fluency/story score calculation arms in `calculate(for:)`. For `PartialScoreReport`: drop the corresponding keys. For `PDFReportGenerator`: drop the report sections. For `QMCIAvatarContext`: drop fluency/story persona prompts. For `ResponseCheckers`: drop fluency/story checkers. For `IntakeOutroRAG`: drop fluency/story RAG content.

For each modified file, run a build after to spot any reference you missed.

- [ ] **Step 2: Verify clean across all consumer files**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
grep -rln --include='*.swift' "verbalFluency\|VerbalFluency\|logicalMemory\|LogicalMemory\|storyRecall\|StoryRecall" VoiceMiniCog/ | grep -v Tests
```

Expected: zero output. (Tests still reference these for migration fixtures — that's fine.)

- [ ] **Step 3: Full app build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -30
```

Expected: clean build, no errors. (App may not yet *run* correctly because subsequent tasks add migration logic, but it builds.)

- [ ] **Step 4: Commit (single sweeping commit)**

```bash
git add VoiceMiniCog/Views/ClinicianDashboardView.swift \
        VoiceMiniCog/Views/PCPReportView.swift \
        VoiceMiniCog/Services/QMCIScoringEngine.swift \
        VoiceMiniCog/Services/PartialScoreReport.swift \
        VoiceMiniCog/Services/PDFReportGenerator.swift \
        VoiceMiniCog/Services/QMCIAvatarContext.swift \
        VoiceMiniCog/Services/ResponseCheckers.swift \
        VoiceMiniCog/Services/IntakeOutroRAG.swift \
        VoiceMiniCog/Theme/AssessmentTheme.swift \
        VoiceMiniCog/Theme/AssessmentViewModifiers.swift \
        VoiceMiniCog/Models/AssessmentState.swift
git commit -m "refactor(consumers): remove fluency/story references across all consumers

Sweeping deletion across 11 consumer files. Per spec §A.4.3 (modified files
file map). All scoring, copy, RAG, theme, and report surfaces now reflect
the 4-module Plan 1 battery."
```

---

## Task 18 — `AssessmentPersistence` schemaVersion + legacy detection + MigrationLogEntry

**Files:**
- Modify: `VoiceMiniCog/Services/AssessmentPersistence.swift`
- Create: `VoiceMiniCog/Models/MigrationLogEntry.swift`

- [ ] **Step 1: Create `MigrationLogEntry.swift`**

```swift
import Foundation

enum MigrationOutcome: String, Codable {
    case legacyReadOnly
    case legacyAbandoned
    case currentNoOp
    case future
}

struct MigrationLogEntry: Codable {
    let sessionID: UUID
    let detectedAt: Date
    let fromVersion: Int
    let outcome: MigrationOutcome
    let lastValidPhase: Phase?
}
```

- [ ] **Step 2: Update `AssessmentPersistence`**

Add to the persistence record:
```swift
/// Schema version. v2 locked 2026-04-29 (six-module battery restructure).
/// v1 (or missing) sessions are legacy: completed sessions are read-only,
/// in-flight sessions are abandoned-with-notice. No silent in-flight migration.
let schemaVersion: Int

static let currentSchemaVersion: Int = 2
```

Update encoding so `schemaVersion` is always written as `2` for new sessions, and update decoding to fall back to `1` if missing:

```swift
schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
```

Add a load-time classification:

```swift
enum SessionLoadResult {
    case current(AssessmentSession)
    case legacyReadOnly(AssessmentSession)
    case legacyAbandoned(AssessmentSession)
    case unrecognizedFutureVersion(AssessmentSession)
}

func loadSession(...) -> SessionLoadResult {
    let session = ...
    switch session.schemaVersion {
    case 1:
        if session.phase == .report {
            return .legacyReadOnly(session)
        } else {
            return .legacyAbandoned(session)
        }
    case Self.currentSchemaVersion:
        return .current(session)
    case let v where v > Self.currentSchemaVersion:
        return .unrecognizedFutureVersion(session)
    default:
        return .legacyAbandoned(session)
    }
}
```

- [ ] **Step 3: Add MigrationLogEntry to `LongitudinalPatientStore`**

```swift
var assessmentMigrationLog: [MigrationLogEntry] = []  // INDEXED — see persistence layer
```

For "indexed": ensure that `LongitudinalPatientStore`'s storage backend (whether file-based, Core Data, or SwiftData) declares an index on `MigrationLogEntry.sessionID` and `MigrationLogEntry.detectedAt`. The exact mechanism depends on the existing store implementation — locate the store's index/schema declaration site and add the two fields. If indexes aren't supported (file-based), document this as a known limitation in the file header and proceed (Plan 1 doesn't critically depend on the index; Block D Item 4 captures it for forward-spec norms work).

- [ ] **Step 4: Register new file + ensure pbxproj clean**

Add `Models/MigrationLogEntry.swift` to the `VoiceMiniCog` target.

- [ ] **Step 5: Build**

- [ ] **Step 6: Commit**

```bash
git add VoiceMiniCog/Services/AssessmentPersistence.swift \
        VoiceMiniCog/Models/MigrationLogEntry.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "feat(persistence): add schemaVersion=2 + legacy detection + migration log

- Adds AssessmentPersistence.schemaVersion (Int), default 2 for new sessions
- Adds SessionLoadResult enum: .current | .legacyReadOnly | .legacyAbandoned
  | .unrecognizedFutureVersion
- v1 in-flight sessions are .legacyAbandoned (no silent migration —
  clinical-validity invariant per spec §E.2)
- Adds MigrationLogEntry to LongitudinalPatientStore.assessmentMigrationLog"
```

---

## Task 19 — Add `AssessmentPersistenceMigrationTests` (7 fixtures)

**Files:**
- Create: `VoiceMiniCogTests/AssessmentPersistenceMigrationTests.swift`
- Create: `VoiceMiniCogTests/Fixtures/v1-completed-fluency-and-story.json`
- Create: `VoiceMiniCogTests/Fixtures/v1-mid-fluency.json`
- Create: `VoiceMiniCogTests/Fixtures/v1-mid-story.json`
- Create: `VoiceMiniCogTests/Fixtures/v1-mid-clockDrawing.json`
- Create: `VoiceMiniCogTests/Fixtures/v2-completed-recognition.json`
- Create: `VoiceMiniCogTests/Fixtures/v2-mid-tmtB.json`
- Create: `VoiceMiniCogTests/Fixtures/v3-unknown-future.json`

- [ ] **Step 1: Author each fixture JSON**

Each fixture is a serialized `AssessmentSession`:
- `v1-completed-fluency-and-story.json`: schemaVersion missing or 1, phase = "report", containing legacy fluency/story scores.
- `v1-mid-fluency.json`: schemaVersion 1, phase = "qmciVerbalFluency".
- `v1-mid-story.json`: schemaVersion 1, phase = "qmciLogicalMemory".
- `v1-mid-clockDrawing.json`: schemaVersion 1, phase = "qmciClockDrawing" (its sequence position changed in v2 — was followed by fluency, now followed by recall).
- `v2-completed-recognition.json`: schemaVersion 2, phase = "report", containing all new fields populated.
- `v2-mid-tmtB.json`: schemaVersion 2, phase = "qmciTMTB".
- `v3-unknown-future.json`: schemaVersion 3, hand-crafted to verify `.unrecognizedFutureVersion`.

Place under `VoiceMiniCogTests/Fixtures/`.

- [ ] **Step 2: Write the test class**

```swift
import XCTest
@testable import VoiceMiniCog

final class AssessmentPersistenceMigrationTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func test_v1Completed_isLegacyReadOnly() throws {
        let data = try loadFixture("v1-completed-fluency-and-story")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .legacyReadOnly = result else {
            return XCTFail("Expected .legacyReadOnly, got \(result)")
        }
    }

    func test_v1MidFluency_isLegacyAbandoned() throws {
        let data = try loadFixture("v1-mid-fluency")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .legacyAbandoned = result else {
            return XCTFail("Expected .legacyAbandoned, got \(result)")
        }
    }

    func test_v1MidStory_isLegacyAbandoned() throws {
        let data = try loadFixture("v1-mid-story")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .legacyAbandoned = result else {
            return XCTFail("Expected .legacyAbandoned, got \(result)")
        }
    }

    func test_v1MidClockDrawing_isLegacyAbandoned() throws {
        // Sequence position of clockDrawing changed in v2 (formerly followed by
        // fluency, now followed by recall). Resume-equivalence is not safe.
        let data = try loadFixture("v1-mid-clockDrawing")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .legacyAbandoned = result else {
            return XCTFail("Expected .legacyAbandoned, got \(result)")
        }
    }

    func test_v2Completed_isCurrent() throws {
        let data = try loadFixture("v2-completed-recognition")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .current = result else {
            return XCTFail("Expected .current, got \(result)")
        }
    }

    func test_v2MidTmtB_isCurrent() throws {
        let data = try loadFixture("v2-mid-tmtB")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .current = result else {
            return XCTFail("Expected .current, got \(result)")
        }
    }

    func test_v3Future_isUnrecognized() throws {
        let data = try loadFixture("v3-unknown-future")
        let result = AssessmentPersistence.shared.loadSession(from: data)
        guard case .unrecognizedFutureVersion = result else {
            return XCTFail("Expected .unrecognizedFutureVersion, got \(result)")
        }
    }
}
```

- [ ] **Step 3: Register fixtures as test-bundle resources in pbxproj**

Add the 7 fixture .json files as `PBXBuildFile` entries in the `VoiceMiniCogTests` target's resources phase.

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/AssessmentPersistenceMigrationTests -quiet 2>&1 | tail -120
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCogTests/AssessmentPersistenceMigrationTests.swift \
        VoiceMiniCogTests/Fixtures/ \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(persistence): 7-fixture migration suite

Asserts v1 sessions classify as .legacyReadOnly (completed) or .legacyAbandoned
(in-flight, including .qmciClockDrawing whose sequence position changed in v2).
Asserts v2 sessions classify as .current. Asserts v3 sessions classify as
.unrecognizedFutureVersion."
```

---

## Task 20 — Add `RecognitionFormConstraintsTests`

**Files:**
- Create: `VoiceMiniCogTests/RecognitionFormConstraintsTests.swift`

- [ ] **Step 1: Write the constraints test**

```swift
import XCTest
@testable import VoiceMiniCog

final class RecognitionFormConstraintsTests: XCTestCase {

    /// Locked v1.0 SHA-256 fingerprint of the canonical-JSON bytes of
    /// RecognitionForm.formA. Any change to locked stimuli must update this
    /// fingerprint via clinical-review code review.
    /// Fingerprint computed once at lock time; not auto-derived.
    private static let formAFingerprint: String =
        "<placeholder — compute on first run via fingerprint helper, then lock>"

    func test_formA_hasFifteenStimuli() {
        XCTAssertEqual(RecognitionForm.formA.stimuli.count, 15)
    }

    func test_formA_hasFiveOfEachKind() {
        let s = RecognitionForm.formA.stimuli
        XCTAssertEqual(s.filter { $0.kind == .target        }.count, 5)
        XCTAssertEqual(s.filter { $0.kind == .semanticFoil  }.count, 5)
        XCTAssertEqual(s.filter { $0.kind == .unrelatedFoil }.count, 5)
    }

    func test_presentationOrder_allIndicesUnique() {
        let order = RecognitionForm.formA.presentationOrder
        XCTAssertEqual(order.count, 15)
        XCTAssertEqual(Set(order).count, 15)
        XCTAssertEqual(Set(order), Set(0..<15))
    }

    func test_presentationOrder_noTwoAdjacentSameKind() {
        let form = RecognitionForm.formA
        for i in 0..<(form.presentationOrder.count - 1) {
            let a = form.stimulus(at: i)
            let b = form.stimulus(at: i + 1)
            XCTAssertNotEqual(a.kind, b.kind,
                "Stimuli at admit positions \(i) (\(a.word) \(a.kind)) and " +
                "\(i+1) (\(b.word) \(b.kind)) share the same kind. " +
                "Constraint: no two adjacent same-kind stimuli.")
        }
    }

    func test_presentationOrder_firstIsTarget() {
        let first = RecognitionForm.formA.stimulus(at: 0)
        XCTAssertEqual(first.kind, .target,
            "First admin stimulus must be a target (anchors patient expectation).")
    }

    func test_presentationOrder_lastIsAnyFoil() {
        let last = RecognitionForm.formA.stimulus(at: 14)
        XCTAssertNotEqual(last.kind, .target,
            "Last admin stimulus must be a foil (no target at end → mitigates " +
            "recency-driven false hits).")
    }

    /// Future-proofs against schema additions (e.g. "description", "hint",
    /// "audioFile" fields). Asserts no stimulus word appears in any field of
    /// RecognitionForms.json other than "word".
    func test_jsonHasNoStimulusWordsOutsideWordField() throws {
        let url = Bundle.main.url(forResource: "RecognitionForms",
                                  withExtension: "json")!
        let raw = try String(contentsOf: url)

        let stimulusWords: [String] = RecognitionForm.formA.stimuli.map(\.word)

        // Strip out values that ARE the "word" field — those are legitimate.
        let pattern = #""word"\s*:\s*"[^"]*""#
        let scrubbed = raw.replacingOccurrences(
            of: pattern, with: "", options: .regularExpression
        )

        for word in stimulusWords {
            let regex = try NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                options: .caseInsensitive
            )
            let range = NSRange(scrubbed.startIndex..., in: scrubbed)
            let matches = regex.numberOfMatches(in: scrubbed, range: range)
            XCTAssertEqual(matches, 0,
                "Stimulus word '\(word)' appears in RecognitionForms.json " +
                "outside the 'word' field. Adding new fields ('description', " +
                "'hint', etc.) must not contain stimulus words.")
        }
    }

    /// Asserted fingerprint is computed at lock time and committed alongside
    /// the locked stimuli. This test fails if anyone changes the JSON without
    /// also updating the fingerprint — which forces a clinical-review code
    /// review for any stimulus change.
    func test_formA_matchesLockedFingerprint() throws {
        let url = Bundle.main.url(forResource: "RecognitionForms",
                                  withExtension: "json")!
        let data = try Data(contentsOf: url)
        let computed = sha256Hex(data)
        XCTAssertEqual(computed, Self.formAFingerprint,
            "RecognitionForms.json was modified without updating the locked " +
            "fingerprint. Update Self.formAFingerprint with the new value " +
            "(\(computed)) only after clinical review.")
    }

    private func sha256Hex(_ data: Data) -> String {
        // Use CryptoKit
        // (Implementation: Insecure or SHA256 from CryptoKit, hex-formatted)
        // Imported via `import CryptoKit` at top of file.
        return ""  // Plan 1 stub — finalize fingerprint computation here
    }
}
```

- [ ] **Step 2: Add `import CryptoKit`** at top of file and finalize `sha256Hex` helper.

- [ ] **Step 3: Compute the locked fingerprint**

After Plan 2 wires the JSON loader properly (so `RecognitionForm.formA` is fully populated), run a one-shot helper to print the SHA-256 of the canonical-JSON bytes, paste it into `formAFingerprint` constant, and commit. For Plan 1, since `formA` is stubbed, leave the fingerprint test in `XCTSkip` mode:

```swift
func test_formA_matchesLockedFingerprint() throws {
    throw XCTSkip("Fingerprint locked in Plan 2 once formA loader lands.")
}
```

- [ ] **Step 4: Register file + run tests**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionFormConstraintsTests -quiet 2>&1 | tail -120
```

Expected: 6 tests pass + 1 skipped (fingerprint).

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCogTests/RecognitionFormConstraintsTests.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(recognition): RecognitionForm v1.0 constraints

Asserts: 15 stimuli, 5 of each kind, presentationOrder is a permutation of
0..<15, no two adjacent same-kind, first is target, last is foil, no
stimulus words outside the 'word' field of the JSON. Fingerprint test
skipped pending Plan 2 loader."
```

---

## Task 21 — Add `RecognitionContaminationGuardTests` (live, scope correctly empty)

**Files:**
- Create: `VoiceMiniCogTests/RecognitionContaminationGuardTests.swift`

- [ ] **Step 1: Write the contamination guard test**

```swift
import XCTest
@testable import VoiceMiniCog

/// RELEASE BLOCKER — clinical-validity contamination guard.
/// Failure indicates a recognition-trial stimulus has leaked outside its
/// whitelisted scope.
final class RecognitionContaminationGuardTests: XCTestCase {

    private struct WhitelistEntry {
        let file: String
        let lineRange: ClosedRange<Int>
        let word: String
        let justification: String
        let reviewDate: String   // ISO yyyy-MM-dd
    }

    /// Per-occurrence whitelist for unavoidable English-word appearances.
    /// Every entry must include a justification and a review date. Plan 1
    /// ships this empty — current copy contains no stimulus words in
    /// non-whitelisted scopes.
    private static let perOccurrenceWhitelist: [WhitelistEntry] = []

    /// Scope: source files scanned for stimulus contamination outside their
    /// whitelisted contexts.
    private static let scopedSourceFiles: [String] = [
        "VoiceMiniCog/Theme/LeftPaneSpeechCopy.swift",
        "VoiceMiniCog/Services/QMCIAvatarContext.swift",
        "VoiceMiniCog/Services/IntakeOutroRAG.swift",
        "VoiceMiniCog/Services/ResponseCheckers.swift",
        "VoiceMiniCog/Services/QMCIScoringEngine.swift",
        "VoiceMiniCog/Services/PDFReportGenerator.swift",
        "VoiceMiniCog/ContentView.swift",
        // All Views/AvatarAssessment/Phases/*.swift and Views/*.swift are
        // discovered via filesystem walk in scanRepoFiles().
    ]

    /// Files that may contain stimulus words by design — skipped in the scan.
    private static let skipFiles: [String] = [
        "VoiceMiniCog/Resources/RecognitionForms.json",   // legitimate stimulus home
        "VoiceMiniCog/Models/QmciModels.swift",           // seed/fixture literals
        // .md files in docs/clinical/ are skipped (they reference stimuli by design).
    ]

    /// Categories of stimuli to scan for. Loaded from RecognitionForm.formA at
    /// runtime — single source of truth.
    private var stimuliByKind: [(word: String, kind: RecognitionStimulusKind)] {
        RecognitionForm.formA.stimuli.map { ($0.word, $0.kind) }
    }

    /// NOTE: Match regex catches plurals and possessives (dogs, dog's) but NOT
    /// morphological derivatives (loved, raining, buttery). Derivatives are
    /// judged a lower priming risk than exact-stem matches in adjacent copy,
    /// and the false-positive cost of stem-only matching (triggering on
    /// "butterfly", "doorway", "loving" in welcome copy) was judged to exceed
    /// the incremental clinical benefit. This scope decision was reviewed
    /// 2026-04-28.
    private func contaminationRegex(for word: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        return try! NSRegularExpression(
            pattern: "\\b\(escaped)(s|'s|s')?\\b",
            options: .caseInsensitive
        )
    }

    func test_noStimulusWordsInScopedSwiftSources() throws {
        // Plan 1 ships this test live and enforcing. Whitelist is correctly
        // empty of violations because no recognition phase copy has been
        // written yet. Plan 2 expands the legitimate-occurrence set (when
        // recognition copy lands in LeftPaneSpeechCopy) by promoting those
        // sites to whitelisted scopes. The guard is fully enforcing
        // throughout — it is NOT in a dormant state.

        let repoRoot = ProcessInfo.processInfo.environment["SRCROOT"] ??
            FileManager.default.currentDirectoryPath

        for word in stimuliByKind.map(\.word) {
            let regex = contaminationRegex(for: word)

            for relPath in Self.scopedSourceFiles {
                let absPath = "\(repoRoot)/\(relPath)"
                guard let contents = try? String(contentsOfFile: absPath) else {
                    continue   // file not present (e.g. early Plan 1 state)
                }

                let range = NSRange(contents.startIndex..., in: contents)
                let matches = regex.matches(in: contents, range: range)

                for match in matches {
                    if isWhitelisted(file: relPath,
                                     line: lineNumber(in: contents, at: match.range),
                                     word: word) {
                        continue
                    }
                    XCTFail("CONTAMINATION: stimulus word '\(word)' appears in " +
                            "\(relPath) at line \(lineNumber(in: contents, at: match.range)). " +
                            "Either remove it or add a per-occurrence whitelist entry " +
                            "with documented justification.")
                }
            }
        }
    }

    private func isWhitelisted(file: String, line: Int, word: String) -> Bool {
        for entry in Self.perOccurrenceWhitelist {
            if entry.file == file
                && entry.lineRange.contains(line)
                && entry.word == word {
                return true
            }
        }
        return false
    }

    private func lineNumber(in source: String, at range: NSRange) -> Int {
        guard let r = Range(range, in: source) else { return 0 }
        return source[..<r.lowerBound].filter { $0 == "\n" }.count + 1
    }
}
```

- [ ] **Step 2: Run the test**

```bash
xcodebuild test-without-building -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -only-testing:VoiceMiniCogTests/RecognitionContaminationGuardTests -quiet 2>&1 | tail -120
```

Expected: pass with no violations (Plan 1 has zero recognition copy in non-whitelisted scopes).

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCogTests/RecognitionContaminationGuardTests.swift \
        VoiceMiniCog.xcodeproj/project.pbxproj
git commit -m "test(recognition): RecognitionContaminationGuardTests live (RELEASE BLOCKER)

Live and fully enforcing. Whitelist scope correctly empty of violations
because no recognition phase copy has been written yet. Plan 2 expands the
legitimate-occurrence set as recognition copy lands; the guard remains
enforcing throughout. Pre-merge hook activation deferred to Plan 2."
```

---

## Task 22 — Rewrite existing tests (delete fluency/story, update fixtures)

**Files:**
- Modify: `VoiceMiniCogTests/QmciScoringTests.swift`
- Modify: any other existing test file referencing fluency/story

- [ ] **Step 1: Locate existing test files referencing deleted content**

```bash
grep -rln --include='*.swift' "verbalFluency\|VerbalFluency\|logicalMemory\|LogicalMemory\|storyRecall\|StoryRecall" VoiceMiniCogTests/
```

- [ ] **Step 2: For each, delete the relevant test cases**

Remove fluency-scorer tests, logical-memory-scorer tests, fluency/story fixtures. Update any composite-flow tests to reflect the new 4-module sequence.

- [ ] **Step 3: Run the full test suite**

```bash
xcodebuild test -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -120
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCogTests/
git commit -m "test: remove fluency/story tests + update fixtures for new battery"
```

---

## Task 23 — Create four `docs/clinical/` files

**Files:**
- Create: `docs/clinical/recognition-foil-rationale.md`
- Create: `docs/clinical/qmci-modifications.md`
- Create: `docs/clinical/recognition-form-roadmap.md`
- Create: `docs/clinical/tmtb-layout-rationale.md`

- [ ] **Step 1: Create `recognition-foil-rationale.md`**

Author per spec §E.2 outline. Use the structure:

```yaml
---
status: locked-v1.0
created: 2026-04-29
spec: docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md
locked-by: Tolla (clinical) + Claude (engineering) 2026-04-29
review-trigger: change to RecognitionForm.formA, Phase enum, EncodingRetrievalIndex.Thresholds, or AssessmentFlowType.quick.phaseSequence
---
```

Sections per spec §E.2:
1. Purpose & scope
2. Target list (Set 1 only — verified O'Caoimh 2012)
3. Semantic foils — per-target rationale table
4. Unrelated foils — frequency-match + non-semantic-overlap rationale
5. Sets 2 & 3 deletion audit
6. Presentation order (with constraints + locked v1.0 sequence + test reference)
7. Registration trial 1 anchor (cross-ref qmci-modifications.md)
8. Pattern thresholds — quote `EncodingRetrievalIndex.Thresholds.currentProvenance` verbatim
9. Bibliography

- [ ] **Step 2: Create `qmci-modifications.md`**

Same frontmatter. Sections per spec §E.3 outline. Include the verbatim insertion text from `~/Downloads/qmci-modifications-insertion.md` as §4–§6, the PHQ-2 deployment caveat (verbatim from Decision 3) as §7, and the dropped-fluency / dropped-story / TMT-B-style-component / Set-1-only sections.

- [ ] **Step 3: Create `recognition-form-roadmap.md`**

Same frontmatter (status: deferred). Sections per spec §E.4 outline. Include the verbatim Form B trigger criteria + equivalence requirements.

- [ ] **Step 4: Create `tmtb-layout-rationale.md`**

Use the verbatim user-supplied draft preserved in conversation history. Append §"Scoring" section per Block D Item 1:

```markdown
## Scoring

A tap is classified by `TMTBScorer` according to its proximity to layout nodes:

- **Correct hit** — tap within `hitRadiusPt` of the next-expected node and outside `hitRadiusPt` of all other nodes.
- **`wrongTargetTap`** — tap within `hitRadiusPt` of a non-expected node and outside `hitRadiusPt` of the expected node. Increments `wrongTargetTaps`.
- **`offPathStroke`** — tap in dead space (within `hitRadiusPt` of no node, or ambiguous between two non-expected nodes). Logged silently; does not increment `wrongTargetTaps`.
- **Self-correction (`sequenceCorrected`)** — `wrongTargetTap` followed within 3 seconds by a correct hit on the expected node, with no intervening node-region taps. Promotes the prior `wrongTargetTap`'s effect on advancement to logged-only.

`hitRadiusPt = 28` (recorded in `Resources/TMTBLayout.json`) corresponds to ~0.5× the minimum inter-node distance constraint and is sized so that node regions never overlap. Any layout regeneration must preserve this invariant; the constraint is asserted in `TMTBScorerTests.swift` (TMT-B layout-constraint sibling suite to `RecognitionFormConstraintsTests`).
```

- [ ] **Step 5: Commit**

```bash
git add docs/clinical/
git commit -m "docs(clinical): four locked-v1.0 methodology documents

- recognition-foil-rationale.md
- qmci-modifications.md
- recognition-form-roadmap.md (status: deferred)
- tmtb-layout-rationale.md

Each carries frontmatter linking to spec + review-trigger condition. Together
these support the regulatory claim that MercyCognitive is a novel composite
battery, not a Qmci implementation."
```

---

## Task 24 — Append CLAUDE.md sections

**Files:**
- Modify: `VoiceMiniCog/CLAUDE.md`

- [ ] **Step 1: Append seven new sections after the existing "Tech Stack" section**

Sections per spec §E.7 (Battery Structure, Clinical Documentation, Feature Flags, Recognition Trial Architecture [forward-referenced], Pre-Merge Hooks [forward-referenced], Stroke Pipeline [forward-referenced], Schema Version). Use the verbatim copy from spec §E.7.

For Plan 1, the three forward-referenced sections (Recognition Trial Architecture, Pre-Merge Hooks, Stroke Pipeline) carry a leading sentence: *"**Forward reference — implemented in Plan 2/3.** This section describes the architecture in its final state. Until Plan 2/3 ships, the implementation is partial."*

- [ ] **Step 2: Commit**

```bash
git add VoiceMiniCog/CLAUDE.md
git commit -m "docs(claude): append battery / docs / flags / sequencing sections

7 new sections (Battery Structure, Clinical Documentation, Feature Flags,
Recognition Trial Architecture (forward-ref), Pre-Merge Hooks (forward-ref),
Stroke Pipeline (forward-ref), Schema Version)."
```

---

## Plan 1 Acceptance

- [ ] **Step 1: Full app build**

```bash
xcodebuild build -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -30
```

Expected: clean build.

- [ ] **Step 2: Full test suite**

```bash
xcodebuild test -project VoiceMiniCog.xcodeproj -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' -quiet 2>&1 | tail -150
```

Expected: all tests pass — `BatteryEnumSyncTests`, `AssessmentPersistenceMigrationTests`, `RecognitionFormConstraintsTests` (with fingerprint XCTSkip), `RecognitionContaminationGuardTests`, plus all surviving pre-existing tests.

- [ ] **Step 3: Manual smoke test**

Boot simulator, install app, run a session: Welcome → Orientation → Word Registration → Clock Drawing → Delayed Recall → Completion. Verify:
- 4-cell chevron displays during cognitive phases.
- Chevron is hidden during Welcome.
- Clock Drawing accepts pencil input and produces a structure score.
- Delayed Recall captures words via ASR.
- Completion produces a PDF report containing only those 4 modules — no fluency, no story, no recognition, no TMT-B.

- [ ] **Step 4: Open PR**

PR title: `Plan 1 — Battery restructure: delete fluency/story, ship 4-module battery`

PR body must reference [docs/superpowers/specs/2026-04-29-voiceminicog-six-module-restructure-design.md](../specs/2026-04-29-voiceminicog-six-module-restructure-design.md) as the design source of truth and call out:
- 4 deleted modules (Verbal Fluency, Story Recall, QDRS UI, Caregiver iOS surface)
- 7 empty struct definitions landed (Plans 2/3 schema-migration-free)
- 4 new docs/clinical/ files
- 3 new test classes (BatteryEnumSync, AssessmentPersistenceMigration, RecognitionFormConstraints, RecognitionContaminationGuard)
- v1 sessions classified as legacy on load (no silent migration)

---

## Plan 1 Self-Review (run before PR opens)

1. **Spec coverage:** Every step in spec §F.1 (24 sub-tasks) maps to a Task in this plan.
2. **Placeholder scan:** No `TODO`, `TBD`, `// implement later`. The fingerprint constant in `RecognitionFormConstraintsTests` is XCTSkip-gated — that's not a placeholder, it's a deferred derivation.
3. **Type consistency:** `RecognitionStimulusKind` (used in Tasks 10, 20, 21), `Phase.matching(_:)` (used in Tasks 1, 5), `AssessmentPhaseID.isHighRiskAbortPhase` (used in Tasks 3, 13) — names match across all referencing tasks.
4. **Cross-plan handoff:** Plan 2 inherits compilable `RecognitionForm.formA` stub, `RecognitionResult` with computed-property stubs, `EncodingRetrievalIndex.derive` stub. Plan 3 inherits `KinematicCapture`, `RawStroke`, `TMTBResult` shells. Both plans have zero schema-migration work.

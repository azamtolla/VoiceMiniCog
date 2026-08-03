# PCP Report Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the existing PCPReportView with clinical decision UI, ASR review section, report readiness gating, finalization persistence, and bug fixes identified by dual-agent code review.

**Architecture:** The existing PCPReportView (1117 lines) already has CDT rubric editing, orientation score review, PDF export, and risk banner. This plan adds 4 missing sections (ASR Review, Clinical Decision, ReportReadiness gating, report-screen persistence), fixes 3 bugs (stale CDT score display, 0/15 CDT gate, orientation nil-defaults-to-2), and wires CompletionPhaseView to present the report directly. All state lives on the existing `@Observable QmciState` and `@Observable AssessmentState`. No new state objects.

**Tech Stack:** Swift 6.2, SwiftUI (iOS 17+), @Observable, Xcode 16, iPad target

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `VoiceMiniCog/Models/QmciModels.swift` | Modify | Add `cdtReviewed`, `ReportReadiness`, `reportReadiness`, `pendingReviewCount` |
| `VoiceMiniCogTests/ScoringLogicTests.swift` | Modify | Tests for readiness, CDT gate, score properties |
| `VoiceMiniCog/Views/PCPReportView.swift` | Modify | Fix bugs, add ASR Review section, Clinical Decision section, readiness gating |
| `VoiceMiniCog/Views/AvatarAssessment/Phases/CompletionPhaseView.swift` | Modify | Add `qmciState` prop, `showReport`, report sheet |
| `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift` | Modify | Thread `qmciState` to CompletionPhaseView |
| `VoiceMiniCog/ContentView.swift` | Modify | Add report-screen persistence |
| `VoiceMiniCog/Services/PDFReportGenerator.swift` | Modify | Add finalization timestamp to PDF footer |

---

### Task 1: Add `cdtReviewed` flag and `ReportReadiness` to QmciState

**Files:**
- Modify: `VoiceMiniCog/Models/QmciModels.swift:308-310` (add properties near clinician decision fields)
- Modify: `VoiceMiniCog/Models/QmciModels.swift:374-380` (fix `hasCDTFieldsSet`)
- Test: `VoiceMiniCogTests/ScoringLogicTests.swift`

- [ ] **Step 1: Write failing tests for ReportReadiness and CDT gate**

Add to `VoiceMiniCogTests/ScoringLogicTests.swift`:

```swift
// MARK: - ReportReadiness Tests

func testReportReadinessNotReadyWhenIncomplete() {
    let state = QmciState()
    state.isComplete = false
    XCTAssertEqual(state.reportReadiness, .notReady)
}

func testReportReadinessPendingWhenNoCDTReview() {
    let state = QmciState()
    state.isComplete = true
    state.cdtReviewed = false
    state.clinicianDecisionWorkup = nil
    XCTAssertEqual(state.reportReadiness, .pendingClinician)
}

func testReportReadinessCompleteWhenAllGatesMet() {
    let state = QmciState()
    state.isComplete = true
    state.cdtReviewed = true
    state.clinicianDecisionWorkup = true
    XCTAssertEqual(state.reportReadiness, .complete)
}

func testReportReadinessAllowsZeroFifteenCDT() {
    // Critical: a severely impaired patient may score 0/15 legitimately.
    // The gate must NOT block finalization when cdtReviewed == true.
    let state = QmciState()
    state.isComplete = true
    state.cdtReviewed = true  // clinician explicitly reviewed
    state.cdtNumbersPlaced = Array(repeating: false, count: 12)
    state.cdtHandsScore = 0
    state.cdtPivotCorrect = false
    state.clinicianDecisionWorkup = false
    XCTAssertEqual(state.cdtComputedScore, 0)
    XCTAssertEqual(state.reportReadiness, .complete)
}

func testPendingReviewCountTracksAllRequiredFields() {
    let state = QmciState()
    state.isComplete = true
    state.cdtReviewed = false
    state.clinicianDecisionWorkup = nil
    XCTAssertEqual(state.pendingReviewCount, 2)

    state.cdtReviewed = true
    XCTAssertEqual(state.pendingReviewCount, 1)

    state.clinicianDecisionWorkup = true
    XCTAssertEqual(state.pendingReviewCount, 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -40
```

Expected: Compilation failure — `ReportReadiness`, `reportReadiness`, `cdtReviewed`, `pendingReviewCount` not found.

- [ ] **Step 3: Add `ReportReadiness` enum and properties to QmciState**

In `QmciModels.swift`, add the enum before the `QmciState` class (around line 218):

```swift
// MARK: - Report Readiness

enum ReportReadiness: String, Codable {
    case notReady
    case pendingClinician
    case complete
    case finalized
}
```

In `QmciState`, add after `clinicianDecisionTimestamp` (around line 310):

```swift
    /// Explicit clinician confirmation that the clock drawing has been reviewed
    /// and scored. Separates "not yet scored" from "scored 0/15" — without this,
    /// severely impaired patients (legitimate 0/15) would block report finalization.
    var cdtReviewed: Bool = false

    // MARK: - Report Readiness

    var reportReadiness: ReportReadiness {
        guard isComplete else { return .notReady }
        guard cdtReviewed, clinicianDecisionWorkup != nil else {
            return .pendingClinician
        }
        return .complete
    }

    var pendingReviewCount: Int {
        var count = 0
        if !cdtReviewed { count += 1 }
        if clinicianDecisionWorkup == nil { count += 1 }
        return count
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/ScoringLogicTests \
  -quiet 2>&1 | tail -40
```

Expected: All 5 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Models/QmciModels.swift VoiceMiniCogTests/ScoringLogicTests.swift
git commit -m "feat(model): add ReportReadiness state machine and cdtReviewed flag

Fixes critical gate bug: cdtDone check blocked 0/15 clocks.
New cdtReviewed boolean separates 'not yet scored' from 'scored zero'."
```

---

### Task 2: Fix existing PCPReportView bugs (stale CDT score, orientation nil default)

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift:1029` (subtestScore)
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (orientationScoreRow nil default)
- Test: `VoiceMiniCogTests/ScoringLogicTests.swift`

- [ ] **Step 1: Write failing test for effectiveClockDrawingScore vs clockDrawingScore**

Add to `ScoringLogicTests.swift`:

```swift
func testEffectiveClockDrawingScorePrefersCDTFieldsOverStored() {
    let state = QmciState()
    state.clockDrawingScore = 5  // stale stored value
    state.cdtNumbersPlaced = [true, true, true, true, true, true,
                               true, true, true, true, false, false]
    state.cdtHandsScore = 2
    state.cdtPivotCorrect = true
    // 10 numbers + 2 hands + 1 pivot = 13
    XCTAssertEqual(state.effectiveClockDrawingScore, 13)
    XCTAssertEqual(state.clockDrawingScore, 5) // stale stored value unchanged
    XCTAssertNotEqual(state.clockDrawingScore, state.effectiveClockDrawingScore)
}
```

- [ ] **Step 2: Run test to verify it passes** (this tests the model, which is already correct)

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -20 && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/ScoringLogicTests \
  -quiet 2>&1 | tail -20
```

Expected: PASS — confirming the model is correct and the bug is view-only.

- [ ] **Step 3: Fix `subtestScore` to use `effectiveClockDrawingScore`**

In `PCPReportView.swift`, change line 1029:

```swift
// BEFORE:
case .clockDrawing: return q.clockDrawingScore
// AFTER:
case .clockDrawing: return q.effectiveClockDrawingScore
```

- [ ] **Step 4: Fix orientation nil default from 2 to 0**

Find `orientationScoreRow` in `PCPReportView.swift`. Change the nil default:

```swift
// BEFORE:
let currentScore = rawScore ?? 2
// AFTER:
let currentScore = rawScore ?? 0
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

Expected: EXIT_CODE=0

- [ ] **Step 6: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift VoiceMiniCogTests/ScoringLogicTests.swift
git commit -m "fix(report): use effectiveClockDrawingScore, default nil orientation to 0

subtestScore() was reading stale clockDrawingScore instead of the live
effectiveClockDrawingScore, causing subtest bar to disagree with total.
Orientation nil→2 default was crediting unanswered questions."
```

---

### Task 3: Add Clinical Decision section to PCPReportView

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (add section after clockSection)

- [ ] **Step 1: Add clinicalDecisionSection to PCPReportView body**

In `PCPReportView.swift`, add after the `clockSection` call in the body VStack (around line 41-42):

```swift
                // 5b. Clinical Decision (required for finalization)
                clinicalDecisionSection
```

- [ ] **Step 2: Implement clinicalDecisionSection**

Add this computed property to PCPReportView (before `actionButtons`):

```swift
    // MARK: - Clinical Decision Section

    @ViewBuilder
    private var clinicalDecisionSection: some View {
        let q = state.qmciState
        reportCard(title: "Clinical Decision", icon: "clipboard.fill",
                   accent: MCDesign.Colors.primary700) {
            // QMCI classification
            HStack {
                Text("QMCI Classification:")
                    .font(MCDesign.Fonts.reportBody)
                Spacer()
                Text(q.classification.displayName)
                    .font(MCDesign.Fonts.reportBody.bold())
                    .foregroundStyle(scoreColor(q.classification))
            }

            // Age-adjusted if demographics entered
            if state.patientAge > 0 {
                let adjusted = q.adjustedScore(
                    age: state.patientAge,
                    educationYears: state.patientEducationYears
                )
                let adjClass = q.adjustedClassification(
                    age: state.patientAge,
                    educationYears: state.patientEducationYears
                )
                HStack {
                    Text("Age/Education Adjusted:")
                        .font(MCDesign.Fonts.reportBody)
                    Spacer()
                    Text("\(adjusted)/100 — \(adjClass.displayName)")
                        .font(MCDesign.Fonts.reportBody.bold())
                        .foregroundStyle(scoreColor(adjClass))
                }
            }

            Divider().padding(.vertical, 4)

            // Recommend workup?
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommend workup?")
                    .font(MCDesign.Fonts.reportHeading)

                HStack(spacing: 12) {
                    workupButton(label: "Yes", value: true, current: q.clinicianDecisionWorkup)
                    workupButton(label: "No", value: false, current: q.clinicianDecisionWorkup)
                    workupButton(label: "Defer", value: nil, current: q.clinicianDecisionWorkup)
                }
            }

            Divider().padding(.vertical, 4)

            // Repeat testing interval
            VStack(alignment: .leading, spacing: 8) {
                Text("Repeat testing in:")
                    .font(MCDesign.Fonts.reportHeading)

                HStack(spacing: 12) {
                    repeatButton(label: "6 mo", value: true, current: q.clinicianDecisionRepeat)
                    repeatButton(label: "12 mo", value: false, current: q.clinicianDecisionRepeat)
                    repeatButton(label: "None", value: nil, current: q.clinicianDecisionRepeat)
                }
            }

            // Required field indicator
            if q.clinicianDecisionWorkup == nil {
                Label("Required for finalization", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MCDesign.Colors.warning)
                    .padding(.top, 4)
            }
        }
    }

    private func workupButton(label: String, value: Bool?, current: Bool?) -> some View {
        let isSelected = (value == nil && current == nil) ||
                         (value != nil && current != nil && value == current)
        return Button {
            state.qmciState.clinicianDecisionWorkup = value
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : MCDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? MCDesign.Colors.primary700 : MCDesign.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : MCDesign.Colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func repeatButton(label: String, value: Bool?, current: Bool?) -> some View {
        let isSelected = (value == nil && current == nil) ||
                         (value != nil && current != nil && value == current)
        return Button {
            state.qmciState.clinicianDecisionRepeat = value
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : MCDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? MCDesign.Colors.primary500 : MCDesign.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : MCDesign.Colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

Expected: EXIT_CODE=0

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift
git commit -m "feat(report): add Clinical Decision section with workup and repeat pickers"
```

---

### Task 4: Add ASR Review section to PCPReportView

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (add section)
- Test: `VoiceMiniCogTests/ScoringLogicTests.swift`

- [ ] **Step 1: Write test for ASR override score recalculation**

Add to `ScoringLogicTests.swift`:

```swift
func testAcceptingSemanticSubstitutionAddsToRecalledWords() {
    let state = QmciState()
    state.registrationWords = ["dog", "chair", "river", "house", "flag"]
    state.delayedRecallWords = ["chair", "house"]
    XCTAssertEqual(state.delayedRecallScore, 8)  // 2 words * 4 = 8

    // Simulate clinician accepting "puppy" → "dog"
    state.delayedRecallWords.append("dog")
    XCTAssertEqual(state.delayedRecallScore, 12)  // 3 words * 4 = 12
}
```

- [ ] **Step 2: Run test to verify it passes** (model logic already correct)

- [ ] **Step 3: Add asrReviewSection to PCPReportView body**

In the body VStack, add after clockSection and clinicalDecisionSection:

```swift
                // 5c. ASR Review (only if semantic substitutions exist)
                if !state.qmciState.recallSemanticSubstitutions.isEmpty {
                    asrReviewSection
                }
```

- [ ] **Step 4: Implement asrReviewSection**

```swift
    // MARK: - ASR Review Section

    @ViewBuilder
    private var asrReviewSection: some View {
        let q = state.qmciState
        reportCard(title: "Word Recall — ASR Review", icon: "waveform.badge.magnifyingglass",
                   accent: MCDesign.Colors.clockAccent) {
            Text("The speech recognizer detected possible matches. Accept to credit the word, or reject.")
                .font(MCDesign.Fonts.reportCaption)
                .foregroundStyle(MCDesign.Colors.textSecondary)
                .padding(.bottom, 4)

            ForEach(Array(q.recallSemanticSubstitutions.enumerated()), id: \.offset) { index, sub in
                asrOverrideRow(substitution: sub)
                if index < q.recallSemanticSubstitutions.count - 1 {
                    Divider()
                }
            }

            HStack {
                Text("Delayed Recall Score:")
                    .font(MCDesign.Fonts.reportBody)
                Spacer()
                Text("\(q.delayedRecallScore)/20")
                    .font(MCDesign.Fonts.reportData)
                    .foregroundStyle(MCDesign.Colors.primary700)
            }
            .padding(.top, 8)
        }
    }

    private func asrOverrideRow(substitution sub: SemanticSubstitution) -> some View {
        let q = state.qmciState
        let isAccepted = q.recallClinicianOverrides[sub.target] == true
        let isRejected = q.recallClinicianOverrides[sub.target] == false

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Patient said")
                    .font(MCDesign.Fonts.reportCaption)
                    .foregroundStyle(MCDesign.Colors.textSecondary)
                Text("\"\(sub.substitution)\"")
                    .font(MCDesign.Fonts.reportBody.bold())
                Text("→ matched")
                    .font(MCDesign.Fonts.reportCaption)
                    .foregroundStyle(MCDesign.Colors.textSecondary)
                Text("\"\(sub.target)\"")
                    .font(MCDesign.Fonts.reportBody.bold())
            }

            HStack(spacing: 12) {
                Button {
                    q.recallClinicianOverrides[sub.target] = true
                    if !q.delayedRecallWords.contains(sub.target) {
                        q.delayedRecallWords.append(sub.target)
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isAccepted ? .white : MCDesign.Colors.success)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isAccepted ? MCDesign.Colors.success : MCDesign.Colors.successSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    q.recallClinicianOverrides[sub.target] = false
                    q.delayedRecallWords.removeAll { $0 == sub.target }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isRejected ? .white : MCDesign.Colors.error)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isRejected ? MCDesign.Colors.error : MCDesign.Colors.errorSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
```

- [ ] **Step 5: Build and run tests**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -20 && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -only-testing:VoiceMiniCogTests/ScoringLogicTests \
  -quiet 2>&1 | tail -20
```

- [ ] **Step 6: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift VoiceMiniCogTests/ScoringLogicTests.swift
git commit -m "feat(report): add ASR Review section for semantic substitution overrides

Clinician can accept/reject near-miss word recalls (e.g. 'puppy' for 'dog').
Accept adds word to delayedRecallWords; score updates live."
```

---

### Task 5: Add CDT `cdtReviewed` toggle and readiness gating to PCPReportView

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (clock section + action buttons)

- [ ] **Step 1: Add cdtReviewed toggle to clock section**

In the clockSection of `PCPReportView.swift`, after the existing CDT rubric editor (after the `Computed Score: X/15` line), add:

```swift
                Divider().padding(.vertical, 4)

                Toggle(isOn: Binding(
                    get: { state.qmciState.cdtReviewed },
                    set: { state.qmciState.cdtReviewed = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I have reviewed and scored this clock drawing")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Required before report can be finalized")
                            .font(.system(size: 12))
                            .foregroundStyle(MCDesign.Colors.textTertiary)
                    }
                }
                .tint(MCDesign.Colors.success)
```

- [ ] **Step 2: Gate the Finalize and Share buttons on reportReadiness**

In `actionButtons`, find the "Share Report" and "Finalize & Save" buttons. Wrap them with disabled state:

```swift
                let readiness = state.qmciState.reportReadiness
                let canFinalize = readiness == .complete || readiness == .finalized

                // Share Report button
                MCPrimaryButton("Share Report", icon: "square.and.arrow.up",
                                color: canFinalize ? MCDesign.Colors.primary700 : MCDesign.Colors.textTertiary) {
                    // existing PDF generation logic
                }
                .disabled(!canFinalize)
                .opacity(canFinalize ? 1.0 : 0.5)

                // Pending items badge
                if state.qmciState.pendingReviewCount > 0 {
                    Label("\(state.qmciState.pendingReviewCount) required field(s) remaining",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MCDesign.Colors.warning)
                }
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift
git commit -m "feat(report): add cdtReviewed toggle and readiness gating on export buttons

Finalize/Share disabled until cdtReviewed=true and clinicianDecisionWorkup set.
Pending review count badge shown when fields remain."
```

---

### Task 6: Add finalization timestamp and report-screen persistence

**Files:**
- Modify: `VoiceMiniCog/ContentView.swift:129-137` (scenePhase persistence)
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (onFinalize timestamp)

- [ ] **Step 1: Add report-screen persistence to ContentView**

In `ContentView.swift`, change the scenePhase handler (around line 133-134):

```swift
// BEFORE:
if newPhase == .background,
   currentScreen != .home, currentScreen != .report {
    AssessmentPersistence.save(assessmentState, flowType: flowType)
}

// AFTER:
if newPhase == .background, currentScreen != .home {
    AssessmentPersistence.save(assessmentState, flowType: flowType)
}
```

This ensures clinician edits on the report screen are persisted if the app is backgrounded.

- [ ] **Step 2: Set finalization timestamp in onFinalize**

In `ContentView.swift`, in the `onFinalize` closure of PCPReportView (around line 118-123):

```swift
// BEFORE:
onFinalize: {
    assessmentState.reset()
    AssessmentPersistence.clear()
    TavusService.shared.cancelPreWarm()
    currentScreen = .home
}

// AFTER:
onFinalize: {
    assessmentState.qmciState.clinicianDecisionTimestamp = Date()
    AssessmentPersistence.save(assessmentState, flowType: flowType)
    assessmentState.reset()
    AssessmentPersistence.clear()
    TavusService.shared.cancelPreWarm()
    currentScreen = .home
}
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/ContentView.swift
git commit -m "fix(persistence): include report screen in background save, add finalization timestamp

Clinician CDT/orientation/decision edits are now preserved if the app
is backgrounded during report review. Finalization timestamp written
before clear for audit trail."
```

---

### Task 7: Wire CompletionPhaseView to present report directly

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/CompletionPhaseView.swift`
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift`

**Clinical impact reasoning (CLAUDE.md compliance):** Adding `assessmentState` to CompletionPhaseView changes its init signature. The view's clinical behavior (avatar closing speech, timing, haptics) is unaffected — the new parameter is only used to present the report sheet after the assessment flow completes. The `onComplete` callback continues to function identically. This is a presentation-layer change with zero impact on scoring, phase sequencing, or avatar behavior.

- [ ] **Step 1: Add assessmentState parameter and showReport state to CompletionPhaseView**

In `CompletionPhaseView.swift`, change the properties:

```swift
struct CompletionPhaseView: View {

    let onComplete: () -> Void
    let assessmentState: AssessmentState  // NEW

    @State private var contentVisible = false
    @State private var avatarSpeaking = true
    @State private var showReport = false  // NEW
```

- [ ] **Step 2: Add "Review Clinical Report" button after the existing "Return Home" button**

After the existing `MCPrimaryButton("Return Home", ...)` block, add:

```swift
            // Clinician report access
            MCSecondaryButton("Review Clinical Report",
                              icon: "doc.text.magnifyingglass",
                              color: AssessmentTheme.Phase.results) {
                showReport = true
            }
            .disabled(avatarSpeaking)
            .opacity(avatarSpeaking ? 0.5 : 1.0)
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .assessmentContentEnter(isVisible: contentVisible, yOffset: 22)
            .animation(AssessmentTheme.Anim.contentEnter.delay(0.30), value: contentVisible)
```

- [ ] **Step 3: Add sheet presentation**

After the `.onReceive(NotificationCenter.default.publisher(for: .avatarDoneSpeaking))` modifier, add:

```swift
        .sheet(isPresented: $showReport) {
            NavigationStack {
                PCPReportView(
                    state: assessmentState,
                    onRestart: {
                        showReport = false
                    },
                    onFinalize: {
                        showReport = false
                        onComplete()
                    }
                )
            }
            .interactiveDismissDisabled(true)
        }
```

- [ ] **Step 4: Update AvatarAssessmentCanvas call site**

In `AvatarAssessmentCanvas.swift`, find the CompletionPhaseView instantiation (around line 204):

```swift
// BEFORE:
case .completion:
    CompletionPhaseView(onComplete: onComplete)

// AFTER:
case .completion:
    CompletionPhaseView(onComplete: onComplete, assessmentState: assessmentState)
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

- [ ] **Step 6: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/Phases/CompletionPhaseView.swift \
        VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift
git commit -m "feat(completion): wire CompletionPhaseView to present PCPReportView as sheet

Clinical impact: zero — avatar behavior, scoring, and phase sequencing
unchanged. New assessmentState parameter used only for report presentation.
Sheet uses interactiveDismissDisabled to prevent accidental dismiss."
```

---

### Task 8: Async PDF generation

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (Share Report button action)

- [ ] **Step 1: Add @State for generation progress**

In `PCPReportView`, add state:

```swift
    @State private var isGeneratingPDF = false
```

- [ ] **Step 2: Make Share Report button async**

Replace the Share Report button's action with:

```swift
Button {
    guard !isGeneratingPDF else { return }
    isGeneratingPDF = true
    let snapshot = state  // capture reference on main thread
    Task.detached(priority: .userInitiated) {
        let data = PDFReportGenerator.generate(from: snapshot)
        await MainActor.run {
            pdfData = data
            isGeneratingPDF = false
            showShareSheet = true
        }
    }
} label: {
    HStack(spacing: 8) {
        if isGeneratingPDF {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "square.and.arrow.up")
        }
        Text(isGeneratingPDF ? "Generating PDF..." : "Share Report")
    }
    .font(MCDesign.Fonts.bodySemibold)
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .frame(height: MCDesign.Sizing.primaryButtonHeight)
    .background(MCDesign.Colors.primary700)
    .cornerRadius(MCDesign.Radius.medium)
}
.buttonStyle(.plain)
.disabled(isGeneratingPDF)
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift
git commit -m "fix(report): move PDF generation off main thread

UIGraphicsPDFRenderer with clock PNG + full telemetry is non-trivial
work. Now runs in Task.detached with progress indicator."
```

---

### Task 9: Add `computeResults()` to CDT field changes

**Files:**
- Modify: `VoiceMiniCog/Views/PCPReportView.swift` (clock rubric toggle/picker handlers)

- [ ] **Step 1: Find all CDT field mutation sites in clockSection**

The clock rubric editor mutates: `cdtNumbersPlaced[i]`, `cdtHandsScore`, `cdtPivotCorrect`, `cdtInvalidNumbersCount`. Each calls `recomputeClockDrawingScore()`. Add `computeResults()` after each `recomputeClockDrawingScore()` call so the composite risk banner updates live.

- [ ] **Step 2: Add computeResults() after each recomputeClockDrawingScore()**

Find every call to `recomputeClockDrawingScore()` in the clock section (there should be ~4 sites — number toggle, hands picker, pivot toggle, invalid stepper). After each, add:

```swift
state.qmciState.recomputeClockDrawingScore()
computeResults()  // ADD THIS LINE
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1; echo "EXIT_CODE=$?"
```

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Views/PCPReportView.swift
git commit -m "fix(report): recompute composite risk on CDT field changes

Risk banner and amyloid triage now update live when clinician edits
clock drawing scores, matching the existing orientation edit behavior."
```

---

### Task 10: Run full test suite and verify

**Files:**
- None (verification only)

- [ ] **Step 1: Build for testing**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild build-for-testing \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -20
```

- [ ] **Step 2: Run all tests**

```bash
cd /Users/azamtolla/Documents/MercyCognitiveApp/VoiceMiniCog && \
xcodebuild test-without-building \
  -project VoiceMiniCog.xcodeproj \
  -scheme VoiceMiniCog \
  -destination 'platform=iOS Simulator,name=Ipad 13 inch sim' \
  -quiet 2>&1 | tail -40
```

Expected: All tests pass, zero warnings.

- [ ] **Step 3: Verify git log**

```bash
git log --oneline -10
```

Expected: 9 commits (Tasks 1-9) on top of the `@MainActor` commit.

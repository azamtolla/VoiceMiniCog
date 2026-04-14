# TESTING_NOTES.md — v1-pilot Improvements Verification

Physical iPad testing guide for all 5 improvements in PR "Improvements: test config, SwiftLint, expanded tests, orientation ASR suggestions, accessibility audit".

---

## Improvement 1: Fix Test Target Configuration

**File:** `project.pbxproj`

1. Open the project in Xcode.
2. Select the `VoiceMiniCogTests` target → Build Phases → Compile Sources.
3. **Verify:** No app source files (e.g., `ContentView.swift`, `QmciModels.swift`) appear in the test target's compile sources — only test files should be listed.
4. Repeat for `VoiceMiniCogUITests` target.
5. Run `xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPad 13 inch sim' build`
6. **Verify:** Build succeeds with zero errors.

---

## Improvement 2: SwiftLint Configuration

**Files:** `.swiftlint.yml`, `.github/workflows/build.yml`

1. Open `.swiftlint.yml` and review the configured rules.
2. **Verify:** Rules are appropriate for the codebase (force_cast, force_unwrapping, line_length, etc.).
3. Check `.github/workflows/build.yml` for the SwiftLint CI step.
4. **Verify:** SwiftLint runs as part of the CI pipeline on every PR.
5. Optionally run `swiftlint lint` locally and verify it produces reasonable output without excessive false positives.

---

## Improvement 3: Expanded Unit Test Coverage

**File:** `VoiceMiniCogTests/ExpandedCoverageTests.swift`

1. Open the new test file — it contains 51 test functions across 7 test classes.
2. Run tests: `xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPad 13 inch sim' test`
3. **Verify the following test classes pass:**
   - `QMCIScoringEngineTests` — Full scoring pipeline, subtest scores, adjustment groups, weakest/strongest subtests
   - `LeftPaneSpeechCopyTests` — SSML generation for word registration (trial 1/2, break tags, edge cases)
   - `WordRecallScorerPluralTests` — Plural normalization (regular, irregular, ies/shes/ches/xes/zes, double-ss)
   - `ScoreWordRecallIntrusionTests` — Intrusion tracking, repetition counting, stopword filtering
   - `CountryOrientationFalsePositiveTests` — "because"/"focus"/"bus" should NOT match "us"; "usa"/"united states" SHOULD
   - `LogicalMemoryEdgeCaseTests` — Case-insensitive matching, duplicate units, partial words
   - `VerbalFluencyEdgeCaseTests` — Hyphenated animals, mixed punctuation, single-letter tokens

---

## Improvement 4: Orientation ASR Advisory Suggestions

**Files:** `QmciModels.swift`, `QAPhaseView.swift`, `PCPReportView.swift`

### Model Changes
1. **Code review:** Open `QmciModels.swift` and verify the new `orientationSuggestedCorrect: [Bool?]` field exists.
2. **Verify:** The field is included in CodingKeys, encode(), decode() (with backward-compat default), and reset().

### Runtime Behavior
1. Start an assessment and reach the orientation phase.
2. Answer each question verbally (year, month, day of week, date, country).
3. **Verify:** The actual score still defaults to **2 (full credit)** when the patient speaks — the ASR suggestion does NOT change the actual score.
4. If the patient is silent (timeout), **verify** the score is left as nil (clinician must review).

### PCP Report — ASR Advisory Flags
1. Complete the assessment and open the PCP report.
2. Navigate to the "ORIENTATION RESPONSES" section.
3. **Verify for each question:**
   - The patient's captured response text appears (e.g., `Patient said: "twenty twenty six"`).
   - A green checkmark icon + "ASR suggests correct" appears when the ASR thinks the answer is correct.
   - An orange warning icon + "ASR suggests incorrect — please verify" appears when the ASR thinks the answer is wrong.
   - If no ASR data was captured (simulator, auth denied), no flag appears.
4. **Verify:** The clinician can still adjust the score using the segmented picker (0/1/2) regardless of the ASR suggestion.

### Edge Cases
1. Run in the simulator without speech authorization.
2. **Verify:** Orientation still works normally — no crashes, no suggestions shown (nil), scores default to 2 when patient "responds" (via mock/fixture).

---

## Improvement 5: Accessibility Audit

**Files:** Multiple phase view files + `AvatarAssessmentCanvas.swift`

### VoiceOver Navigation
1. Enable VoiceOver on the iPad (Settings → Accessibility → VoiceOver).
2. Start an assessment and navigate through each phase using VoiceOver gestures.
3. **Verify per phase:**

   **Orientation (QAPhaseView):**
   - Question counter reads "Question 1 of 5" (not raw "1 of 5").
   - Question text is announced as a header (swipe up/down to navigate headers).
   - Listening indicator announces "Listening for your answer" when active.
   - Orientation dots announce group progress ("Orientation progress: question X of 5"), individual dots are hidden.

   **Word Registration (WordRegistrationPhaseView):**
   - Ear icon is hidden from VoiceOver (decorative).
   - "Listen" heading is announced as a header.
   - Waveform announces "Avatar is speaking words" or "Waiting" based on state.
   - Progress circles announce "X of 5 words recalled" as a group, individual circles are hidden.

   **Clock Drawing (ClockDrawingPhaseView):**
   - Instruction text is announced as a header.
   - Dashed circle guide is hidden from VoiceOver (decorative).
   - Drawing canvas announces "Clock drawing canvas. X strokes drawn." with hint about the task.

   **Story Recall (StoryRecallPhaseView):**
   - Phase icons (book/mic) are hidden from VoiceOver (decorative).
   - Phase titles are announced as headers.
   - Scoring unit chips have minimum 44pt hit target height.

   **Completion (CompletionPhaseView):**
   - Checkmark icon group is hidden from VoiceOver (decorative).
   - "Assessment Complete" is announced as a header.

   **Canvas Controls (AvatarAssessmentCanvas):**
   - "End Session" button has explicit label and hint.
   - Long-press exit has label and hint explaining the 2-second hold requirement.

### Hit Target Verification
1. With VoiceOver off, verify the following elements are easy to tap:
   - Story recall scoring unit chips — should have at least 44pt height (increased from ~32pt).
   - Answer buttons in QDRS/PHQ-2 — already use `AssessmentTheme.Sizing.buttonMinHeight`.
   - End Session button — should be easily tappable.

### Contrast Ratios
1. The app uses the `AssessmentTheme` design system with established contrast ratios.
2. **Verify:** Text is readable in all phases under normal lighting conditions.
3. The ASR advisory flags use green (#34C759) and orange (#FF9500) on white backgrounds — both meet WCAG AA for large text.

---

## General Build Verification

After all improvements, run the full build:
```
xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPad 13 inch sim' build
```

**Verify:** Zero build errors, zero warnings related to these changes.

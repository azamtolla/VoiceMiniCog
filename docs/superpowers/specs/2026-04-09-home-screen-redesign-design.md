# Home Screen Redesign — Three-Card Assessment Launcher

**Date:** 2026-04-09
**Status:** Draft — pending user approval

## Summary

Replace the current single-path HomeView (respondent type picker + Start button) with a three-card launcher. Each card navigates to a distinct assessment flow, all driven by a single shared `AvatarAssessmentCanvas(flowType:)`. QDRS moves exclusively into the caregiver flow. The Home Screen adopts HA-inspired card styling with staggered entrance animations.

## Goals

1. Three clear entry points: Quick Assessment, Family/Caregiver Questionnaire, Extended Assessment
2. QDRS exists only in the caregiver flow — Quick and Extended have zero informant questions
3. One shared canvas, no duplication — `AssessmentFlowType` controls phase sequencing
4. Polished, calm animations appropriate for elderly patients in clinical settings
5. Extended Assessment preserves its own route for future divergence

## Non-Goals

- Changing any assessment phase views (QAPhaseView, WordRegistrationPhaseView, etc.)
- Modifying TavusService, TavusCVIView, or the WebView pre-warm infrastructure
- Redesigning the avatar zone or split-screen layout
- Adding new clinical content or changing scoring logic

---

## Phase Sequences by Flow Type

```
AssessmentFlowType.quick:
  welcome → orientation → wordRegistration → clockDrawing →
  verbalFluency → storyRecall → wordRecall

AssessmentFlowType.caregiver:
  welcome → qdrs → completion

AssessmentFlowType.extended:
  welcome → orientation → wordRegistration → clockDrawing →
  verbalFluency → storyRecall → wordRecall
```

**NOTE:** `.extended` is intentionally mapped to the same sequence as `.quick` for now. It MUST remain a separate enum case and navigation target. The purpose of this separation is future divergence — the Extended flow will eventually include additional subtests or a different protocol. Do not collapse `.extended` into `.quick` or abstract them into a single case.

**Caregiver `.completion` phase:** A new `AssessmentPhaseID.completion` case that shows a "Questionnaire Complete" screen with a thank-you message and a button to return home. This provides clean flow termination rather than ending abruptly after the last QDRS question.

**Caregiver respondent type:** Set automatically to `.informant` when `flowType == .caregiver`. No respondent picker is shown.

---

## File Responsibilities

### HomeView.swift — UI and card animations only

**Rewrite.** Replaces the current respondent type picker + Start button layout.

**Contains:**
- "Brain Health Screen" heading with brain icon
- Three `AssessmentCard` instances in a horizontal row
- Staggered entrance animation on appear
- Resume banner (shown only when `AssessmentPersistence.hasInProgressAssessment()`)
- Callback: `onSelectFlow: (AssessmentFlowType) -> Void`

**Does not contain:** Assessment logic, state management, respondent type selection.

**Card definitions:**

| Position | Title | SF Symbol | Accent Color |
|---|---|---|---|
| Left | Quick Assessment | bolt.fill | #007AFF (blue) |
| Center | Family / Caregiver Questionnaire | person.2.fill | #5E5CE6 (indigo) |
| Right | Extended Assessment | list.clipboard.fill | #30D158 (green) |

**Entrance animation:**
- Header fades in: 0.4s easeOut, 0.1s delay
- Cards stagger: fade + 20pt upward slide, 0.45s easeOut, 0.12s delay between each card
- Respects `@Environment(\.accessibilityReduceMotion)` — if enabled, instant appear, no motion

**Press animation:**
- Scale 1.0 → 0.96 → 1.0, spring(0.15s, 0.85 damping)
- Light haptic: `UIImpactFeedbackGenerator(.light)`

### AssessmentCard.swift — Reusable visual component only

**New file.** Extracted card component.

```swift
struct AssessmentCard: View {
    let title: String
    let icon: String         // SF Symbol name
    let accentColor: Color
    let staggerIndex: Int    // 0, 1, 2 — controls entrance delay
    let action: () -> Void
}
```

**Contains:** Icon circle with accent gradient, title label, press animation state, stagger entrance animation.

**Does not contain:** Navigation logic, assessment state, flow type knowledge.

### ContentView.swift — Minimal navigation plumbing only

**Modified.** Adds `AssessmentFlowType` state, passes it to the canvas.

**Changes:**
- Add `@State private var flowType: AssessmentFlowType = .quick`
- `HomeView.onSelectFlow` sets `flowType` and `currentScreen = .avatarAssessment`
- Single `AvatarAssessmentCanvas(flowType: flowType, ...)` in ZStack — no duplication
- Remove `AppScreen.caregiverAssessment` / `.extendedAssessment` — not needed. All three flows use `.avatarAssessment` with the `flowType` distinguishing them
- Caregiver flow: set `assessmentState.qdrsState.respondentType = .informant` before navigating
- Pre-warm logic unchanged (Tavus conversation still created on Home appear)

**Does not contain:** Assessment sequencing, UI layout for assessments.

### AvatarLayoutManager.swift — Flow sequencing by enum

**Modified.** Adds `AssessmentFlowType` and dynamic phase sequencing.

**Changes:**
- Add `AssessmentFlowType` enum (`.quick`, `.caregiver`, `.extended`)
- Add `var flowType: AssessmentFlowType = .quick` property
- Add computed `var phaseSequence: [AssessmentPhaseID]` that returns the correct phases for the current flow type
- Add `AssessmentPhaseID.completion` case for caregiver flow termination
- `advancePhase()` and `currentPhaseIndex` use `phaseSequence` instead of hardcoded order
- Phase sequence comment block at the top documents all three mappings

**Explicit mapping table (as code comment):**
```swift
// ┌─────────────┬──────────────────────────────────────────────────────────┐
// │ Flow Type   │ Phase Sequence                                          │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .quick      │ welcome → orientation → wordReg → clock → fluency →    │
// │             │ story → wordRecall                                      │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .caregiver  │ welcome → qdrs → completion                            │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .extended   │ (same as .quick — intentionally separate for future     │
// │             │ divergence, do NOT collapse into .quick)                │
// └─────────────┴──────────────────────────────────────────────────────────┘
```

### AvatarAssessmentCanvas.swift — Shared assessment shell

**Modified.** Accepts `flowType`, passes to layout manager.

**Changes:**
- Add `let flowType: AssessmentFlowType` parameter
- Set `layoutManager.flowType = flowType` on init/appear
- Add `.completion` case to `phaseContent` switch — renders a `CompletionPhaseView`
- All existing phase view rendering unchanged

### CompletionPhaseView.swift — New file

**New file.** Simple completion screen for the caregiver flow.

**Contains:**
- Checkmark icon
- "Questionnaire Complete" title
- "Thank you for completing the caregiver questionnaire." subtitle
- "Return Home" button that calls `onComplete` closure

**Styled with:** AssessmentTheme tokens, same typography and spacing as WelcomePhaseView.

---

## What Moves Where

| Logic | Current Location | New Location |
|---|---|---|
| QDRS phase inclusion | `AvatarLayoutManager` (hardcoded in all flows) | `AvatarLayoutManager.phaseSequence` (caregiver flow only) |
| Respondent type selection | `HomeView` (picker UI) | `ContentView.startAssessment()` (auto-set based on flowType) |
| PHQ-2 phase inclusion | `AvatarLayoutManager` (hardcoded in all flows) | Removed from all flows |

---

## Animations Summary

| Animation | Spec | Reduced Motion Fallback |
|---|---|---|
| Header entrance | 0.4s easeOut, 0.1s delay | Instant appear |
| Card stagger entrance | Fade + 20pt slide-up, 0.45s easeOut, 0.12s delay between cards | Instant appear |
| Card press | Scale 0.96, spring(0.15s, 0.85 damping) + light haptic | Scale only, no spring |
| Phase content swap | Crossfade + 12pt upward drift, 0.35s easeInOut (existing) | Opacity only |
| Phase layout transition | Spring 0.65s, 0.88 damping (existing) | 0.2s easeInOut |

---

## Data Model Impact

- `AssessmentFlowType` — new enum, no persistence needed (derived from user's card selection)
- `AssessmentPhaseID.completion` — new case, display-only (no scoring, no state)
- `AssessmentState` — unchanged. `qdrsState` and `qmciState` still exist on the model. The flow type determines which states get populated during the assessment.
- `AssessmentPersistence` — add `flowType` to the persisted state. When resuming an interrupted assessment, the flow type determines which canvas sequence to restore. Without this, a caregiver assessment could resume as a quick assessment.

---

## Out of Scope

- Changing QDRS question content, scoring, or QAPhaseView behavior
- Modifying the avatar zone, TavusCVIView, or Tavus connection logic
- Adding new clinical instruments
- Changing the report/scoring screen
- Dark mode

# Persistent Avatar & Expanded Phase Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hoist TavusCVIView to a persistent, non-phase-keyed position in the view tree so phase transitions never tear down the WebRTC connection. Redesign clock drawing to a circular-avatar light controls panel. Ensure verbal fluency and word recall phases work cleanly with the same architecture. Add reconnection handling for all phases.

**Architecture:** One `TavusCVIView` instance lives at a fixed position inside `AvatarZoneView`, which itself is never conditionally removed from the tree. Phase transitions morph the video's frame and clip shape (rectangle ↔ circle) via an animatable `PhaseClipShape`. Phase-specific chrome (backgrounds, status chips, buttons, text) composes around the stable video layer. The Tavus conversation is created once at assessment start and ended once at assessment end — no mid-session creation.

**Tech Stack:** SwiftUI, @Observable, TavusCVIView (Daily SDK WebRTC), PhaseClipShape (custom animatable Shape), AssessmentTheme design tokens

**Critical constraints:**
- Avatar is ALWAYS the live Tavus CVI video feed. No static images. No `Image("dr-claire-portrait")`. Preview-only person-icon placeholders are OK.
- TavusCVIView is instantiated exactly once. Phase transitions never recreate it.
- On video failure: shimmer + "Reconnecting…" chip → auto-rejoin existing conversation → 10s clinician banner.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Modify** | `Theme/AssessmentTheme.swift` | Add `ClockControls` design tokens + reconnection colors |
| **Create** | `Views/AvatarAssessment/PhaseClipShape.swift` | Animatable Shape that morphs between RoundedRectangle and Circle |
| **Create** | `Views/AvatarAssessment/Phases/ClockDrawingControlsView.swift` | Controls-only overlay for clock drawing: status chip, instruction text, buttons (NO video) |
| **Modify** | `Views/AvatarAssessment/AvatarZoneView.swift` | Separate video from chrome. Video at fixed tree position, never branched on phase. Phase-aware background + chrome layers. Reconnection shimmer UI. Clock drawing callbacks. |
| **Modify** | `Views/AvatarAssessment/AvatarAssessmentCanvas.swift` | Phase-aware background gradient. Pass clock drawing callbacks. Conversation created once at start, ended once at end (not phase-keyed). Parent-level reconnection logic. |
| **Modify** | `Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift` | Strip to canvas-only (remove instruction text, timer display, Done Drawing button) |
| **Modify** | `Models/AvatarLayoutManager.swift` | Clock drawing avatar opacity → 1.0. Add reconnection state observable. |
| **Verify** | `Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift` | Confirm phase works with persistent video. No changes expected — it already lives in the left content zone. |
| **Verify** | `Views/AvatarAssessment/Phases/WordRecallPhaseView.swift` | Confirm phase works with persistent video. No changes expected — it already lives in the left content zone. |

---

## Part 1: Architecture Foundation

### Task 1: Add Design Tokens

**Files:**
- Modify: `VoiceMiniCog/Theme/AssessmentTheme.swift`

- [ ] **Step 1: Add `ClockControls` enum** after the existing `Avatar` enum (~line 98)

```swift
// MARK: Clock Drawing Controls Panel (light right panel)

enum ClockControls {
    static let doneButtonColor       = Color(hex: "#22C55E")
    static let endSessionColor       = Color(hex: "#DC2626")
    static let avatarRingColor       = Color(hex: "#78716C") // stone-500
    static let avatarRingWidth: CGFloat = 3.0
    static let avatarDiameter: CGFloat = 180
    static let statusChipBackground  = Color(hex: "#F5F5F4") // stone-100
    static let statusChipText        = Color(hex: "#57534E") // stone-600
    static let panelBackground       = Color.white
    static let shimmerBase           = Color(hex: "#E7E5E4") // stone-200
    static let shimmerHighlight      = Color(hex: "#F5F5F4") // stone-100
}
```

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 3: Commit** — `feat: add ClockControls design tokens`

---

### Task 2: Create PhaseClipShape

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/PhaseClipShape.swift`

**Context:** iOS 15 has no `AnyShape`. This custom Shape smoothly interpolates between a rounded rectangle and a circle by animating the corner radius. When `circleProgress = 1.0`, the radius equals half the shortest dimension (a circle). When `0.0`, it's the standard `videoCornerRadius`. SwiftUI animates `animatableData` automatically.

- [ ] **Step 1: Create the file**

```swift
//
//  PhaseClipShape.swift
//  VoiceMiniCog
//
//  Animatable shape that morphs between RoundedRectangle and Circle.
//  Used to clip the persistent TavusCVIView during phase transitions.
//  iOS 15 compatible (no AnyShape dependency).
//

import SwiftUI

struct PhaseClipShape: Shape {
    /// 0.0 = rounded rectangle, 1.0 = circle
    var circleProgress: CGFloat

    var animatableData: CGFloat {
        get { circleProgress }
        set { circleProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let maxRadius = min(rect.width, rect.height) / 2
        let minRadius = AssessmentTheme.Avatar.videoCornerRadius - 2
        let radius = minRadius + (maxRadius - minRadius) * circleProgress
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect)
    }
}
```

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 3: Commit** — `feat: add PhaseClipShape for smooth rect↔circle morph`

---

### Task 3: Refactor AvatarZoneView — Persistent Video, Phase-Aware Chrome

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarZoneView.swift`

**Context:** This is the largest and most critical task. The body is restructured into three layers:
1. **Background layer** — dark gradient (standard) or white (clock drawing)
2. **Video layer** — ONE TavusCVIView at a fixed view-tree position. Frame/clip morph with `PhaseClipShape`. Never inside a branch keyed on `currentPhase`.
3. **Chrome layer** — overlays that change per phase (standard: ring, badge, dots, waveform; clock drawing: controls, status chip, buttons)

**Key rule:** `TavusCVIView` appears in exactly one `if let url = conversationURL` branch. That branch is NOT nested inside any phase-conditional. Only the video's `.frame()`, `.clipShape()`, and `.position()` depend on `isClockDrawing`.

- [ ] **Step 1: Add new properties**

```swift
// Clock drawing callbacks (set by parent, nil for non-clock usage)
var onDoneDrawing: (() -> Void)?
var onEndSession: (() -> Void)?
```

- [ ] **Step 2: Rewrite body with three-layer architecture**

```swift
var body: some View {
    let isClockDrawing = layoutManager.currentPhase == .clockDrawing

    GeometryReader { geo in
        ZStack {
            // MARK: Layer 1 — Background
            backgroundLayer(isClockDrawing: isClockDrawing)

            // MARK: Layer 2 — Video (persistent, morphs shape)
            videoLayer(
                isClockDrawing: isClockDrawing,
                panelWidth: geo.size.width,
                panelHeight: geo.size.height
            )

            // MARK: Layer 3 — Chrome
            if isClockDrawing {
                clockDrawingChromeLayer(panelHeight: geo.size.height)
            } else {
                standardChromeLayer(inset: AssessmentTheme.Avatar.videoInset)
            }
        }
    }
    .onChange(of: layoutManager.avatarBehavior) { _, newBehavior in
        updateAnimations(for: newBehavior)
    }
    .onAppear {
        startBreathing()
        updateAnimations(for: layoutManager.avatarBehavior)
    }
}
```

- [ ] **Step 3: Implement backgroundLayer**

```swift
@ViewBuilder
private func backgroundLayer(isClockDrawing: Bool) -> some View {
    if isClockDrawing {
        AssessmentTheme.ClockControls.panelBackground
    } else {
        ZStack {
            animatedBackground
            phaseAccentGlow
        }
    }
}
```

- [ ] **Step 4: Implement videoLayer — the critical path**

The TavusCVIView is inside ONE `if let url` branch. That branch is not nested in any phase-conditional. Frame, clip, position, and overlay ring all change as a function of `isClockDrawing`, which SwiftUI animates via `PhaseClipShape.animatableData` and `.animation()`.

```swift
@ViewBuilder
private func videoLayer(isClockDrawing: Bool, panelWidth: CGFloat, panelHeight: CGFloat) -> some View {
    if isLoading && conversationURL == nil {
        loadingState
    } else if let error = errorMessage, conversationURL == nil {
        errorState(error)
    } else if let url = conversationURL {
        let diameter = AssessmentTheme.ClockControls.avatarDiameter
        let inset = AssessmentTheme.Avatar.videoInset
        let standardW = panelWidth - 2 * inset - 2
        let standardH = panelHeight - 2 * inset - 2

        let videoW = isClockDrawing ? diameter : standardW
        let videoH = isClockDrawing ? diameter : standardH
        let centerY = isClockDrawing ? (diameter / 2) + 60 : panelHeight / 2

        TavusCVIView(conversationURL: url, onAvatarEvent: onAvatarEvent)
            .frame(width: videoW, height: videoH)
            .clipShape(PhaseClipShape(circleProgress: isClockDrawing ? 1.0 : 0.0))
            .overlay(videoRingOverlay(isClockDrawing: isClockDrawing))
            .opacity(layoutManager.avatarOpacity)
            .scaleEffect(isClockDrawing ? 1.0 : breatheScale)
            .position(x: panelWidth / 2, y: centerY)
            .animation(.spring(duration: 0.55, bounce: 0.15), value: isClockDrawing)
    }
}
```

- [ ] **Step 5: Implement videoRingOverlay**

```swift
@ViewBuilder
private func videoRingOverlay(isClockDrawing: Bool) -> some View {
    if isClockDrawing {
        PhaseClipShape(circleProgress: 1.0)
            .strokeBorder(
                AssessmentTheme.ClockControls.avatarRingColor,
                lineWidth: AssessmentTheme.ClockControls.avatarRingWidth
            )
    } else {
        RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
            .strokeBorder(
                layoutManager.accentColor.opacity(ringOpacity),
                lineWidth: AssessmentTheme.Avatar.accentRingWidth
            )
            .scaleEffect(ringScale)
    }
}
```

- [ ] **Step 6: Implement clockDrawingChromeLayer**

```swift
private func clockDrawingChromeLayer(panelHeight: CGFloat) -> some View {
    let avatarBottom = 60 + AssessmentTheme.ClockControls.avatarDiameter + 20

    VStack(spacing: 0) {
        Spacer().frame(height: avatarBottom)

        if let done = onDoneDrawing, let end = onEndSession {
            ClockDrawingControlsView(
                layoutManager: layoutManager,
                onDoneDrawing: done,
                onEndSession: end
            )
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 7: Rename existing chrome to standardChromeLayer**

Wrap the existing `overlays(inset:)` content and the clinical light effect into `standardChromeLayer`:

```swift
private func standardChromeLayer(inset: CGFloat) -> some View {
    ZStack {
        // Glass material backdrop
        RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
            .fill(Color.white.opacity(AssessmentTheme.Avatar.glassOpacity))
            .padding(inset)
            .allowsHitTesting(false)

        // Clinical light effect
        RoundedRectangle(cornerRadius: AssessmentTheme.Avatar.videoCornerRadius)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
            .padding(inset)
            .allowsHitTesting(false)

        // Status dot, clinical badge, waveform — existing overlays
        overlays(inset: inset)
    }
}
```

- [ ] **Step 8: Delete the old `videoContainer(url:)` function** — replaced by `videoLayer`.

- [ ] **Step 9: Build** → `** BUILD SUCCEEDED **`

- [ ] **Step 10: Commit** — `refactor: persistent TavusCVIView with phase-aware chrome in AvatarZoneView`

---

### Task 4: Refactor AvatarAssessmentCanvas — Lifecycle + Background + Callbacks

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift`

**Context:** Conversation is created once at assessment start, ended once at assessment end. Background gradient becomes fully light during clock drawing. Clock drawing callbacks are passed to AvatarZoneView. AvatarZoneView is NEVER conditionally removed — it persists for the entire assessment.

- [ ] **Step 1: Make background gradient phase-aware**

Replace the `LinearGradient` block (lines 41–54):

```swift
                LinearGradient(
                    stops: layoutManager.currentPhase == .clockDrawing
                        ? [
                            .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                            .init(color: Color(hex: "#F8F9FA"), location: 1.0)
                        ]
                        : [
                            .init(color: Color(hex: "#F8F9FA"), location: 0.0),
                            .init(
                                color: Color(hex: "#F8F9FA"),
                                location: 1.0 - layoutManager.avatarWidthRatio
                            ),
                            .init(color: Color(hex: "#080808"), location: 1.0)
                        ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.avatarWidthRatio)
                .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
```

- [ ] **Step 2: Pass clock drawing callbacks to AvatarZoneView**

Replace `avatarZone(width:height:)` (lines 146–171):

```swift
    @ViewBuilder
    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: activeConversationURL ?? conversationURL,
            isLoading: isLoadingAvatar,
            errorMessage: avatarError,
            onAvatarEvent: handleAvatarEvent,
            width: width,
            height: height,
            onDoneDrawing: {
                layoutManager.advanceToNextPhase()
            },
            onEndSession: onCancel
        )
        .frame(width: width, height: height)
        .onAppear {
            if activeConversationURL == nil && conversationURL == nil {
                createConversation()
            } else if let url = conversationURL {
                activeConversationURL = url
                isLoadingAvatar = false
            }
        }
        .onDisappear {
            Task { await tavusService.endConversation() }
        }
        .onChange(of: layoutManager.currentPhase) { _, newPhase in
            sendPhaseContext(newPhase)
        }
    }
```

Note: `.onAppear` / `.onDisappear` fire once for the assessment lifetime (not per phase) because `AvatarZoneView` is never removed from the tree.

- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 4: Commit** — `feat: phase-aware background + clock drawing callbacks in AvatarAssessmentCanvas`

---

### Task 5: Update AvatarLayoutManager

**Files:**
- Modify: `VoiceMiniCog/Models/AvatarLayoutManager.swift`

- [ ] **Step 1: Set avatar opacity to 1.0 for clock drawing**

Replace:
```swift
    var avatarOpacity: Double {
        switch currentPhase {
        case .clockDrawing, .verbalFluency:
            return 0.4
```

With:
```swift
    var avatarOpacity: Double {
        switch currentPhase {
        case .clockDrawing:
            return 1.0  // Circular avatar visible at full opacity in controls panel
        case .verbalFluency:
            return 0.4
```

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 3: Commit** — `fix: avatar opacity 1.0 during clock drawing`

---

## Part 2: Clock Drawing Redesign

### Task 6: Create ClockDrawingControlsView (Controls-Only)

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingControlsView.swift`

**Context:** Controls that appear below the circular avatar in clock drawing mode. This view does NOT contain a TavusCVIView — the video is owned by AvatarZoneView's `videoLayer`. This view is used as an overlay inside AvatarZoneView's `clockDrawingChromeLayer`.

- [ ] **Step 1: Create the file**

```swift
//
//  ClockDrawingControlsView.swift
//  VoiceMiniCog
//
//  Controls overlay for the clock drawing phase — status chip,
//  instruction text, and action buttons. Rendered below the circular
//  live avatar video in AvatarZoneView's clock drawing mode.
//  Does NOT contain a TavusCVIView.
//
//  MARK: CLINICAL-UI — Clock drawing is a validated Qmci subtest (15 pts).
//

import SwiftUI

// MARK: - ClockDrawingControlsView

struct ClockDrawingControlsView: View {

    let layoutManager: AvatarLayoutManager
    let onDoneDrawing: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status chip
            statusChip
                .padding(.bottom, 24)

            // Instruction text
            Text(AssessmentTheme.PromptCopy.clockDrawingInstruction)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDoneDrawing()
                } label: {
                    Label("Done Drawing", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AssessmentTheme.ClockControls.doneButtonColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onEndSession()
                } label: {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(AssessmentTheme.ClockControls.endSessionColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Status Chip

    private var statusChip: some View {
        HStack(spacing: 6) {
            MiniWaveform(isActive: layoutManager.avatarBehavior == .speaking)

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AssessmentTheme.ClockControls.statusChipText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(AssessmentTheme.ClockControls.statusChipBackground))
    }

    private var statusText: String {
        switch layoutManager.avatarBehavior {
        case .speaking, .narrating: return "Speaking..."
        case .listening:            return "Listening..."
        default:                    return "Waiting..."
        }
    }
}

// MARK: - Mini Waveform

private struct MiniWaveform: View {
    let isActive: Bool
    private let barCount = 5
    @State private var heights: [CGFloat] = [4, 4, 4, 4, 4]
    private let targetHeights: [CGFloat] = [6, 10, 8, 12, 7]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(AssessmentTheme.ClockControls.statusChipText.opacity(0.6))
                    .frame(width: 2, height: heights[index])
            }
        }
        .frame(height: 14)
        .onAppear { animate() }
        .onChange(of: isActive) { _, active in
            if active { animate() } else { resetBars() }
        }
    }

    private func animate() {
        for i in 0..<barCount {
            withAnimation(
                .easeInOut(duration: 0.5 + Double(i % 3) * 0.12)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.07)
            ) { heights[i] = targetHeights[i] }
        }
    }

    private func resetBars() {
        withAnimation(.easeOut(duration: 0.3)) {
            heights = Array(repeating: 4, count: barCount)
        }
    }
}

// MARK: - Preview

#Preview("Clock Drawing Controls") {
    VStack {
        // Simulate circular avatar above
        Circle()
            .fill(Color.gray.opacity(0.15))
            .overlay(Image(systemName: "person.fill").font(.system(size: 60)).foregroundStyle(.gray.opacity(0.4)))
            .frame(width: 180, height: 180)
            .padding(.top, 60)

        ClockDrawingControlsView(
            layoutManager: AvatarLayoutManager(),
            onDoneDrawing: {},
            onEndSession: {}
        )
    }
    .frame(width: 350, height: 900)
    .background(Color.white)
}
```

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 3: Commit** — `feat: create ClockDrawingControlsView (controls-only, no video)`

---

### Task 7: Simplify ClockDrawingPhaseView to Canvas Only

**Files:**
- Modify: `VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift`

**Context:** Instruction text, timer display, and Done Drawing button moved to the right panel. This view is now a pure drawing canvas. Timer still runs hidden and auto-advances on expiry. `onDisappear` invalidates the timer when the phase advances (whether from the controls panel's Done Drawing button or timer expiry).

- [ ] **Step 1: Replace body with canvas-only layout**

Replace the entire `body` (lines 37–134):

```swift
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let guideSize = size * 0.75

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(
                        color: AssessmentTheme.Content.shadowColor.opacity(0.08),
                        radius: 8,
                        y: 4
                    )

                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .foregroundColor(Color.gray.opacity(0.25))
                    .frame(width: guideSize, height: guideSize)

                Canvas { context, _ in
                    for stroke in lines { drawStroke(stroke, in: context) }
                    drawStroke(currentLine, in: context)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in currentLine.append(value.location) }
                        .onEnded { _ in
                            if !currentLine.isEmpty {
                                lines.append(currentLine)
                                currentLine = []
                            }
                        }
                )
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
        .onAppear {
            startTimer()
            NotificationCenter.default.post(
                name: .tavusEchoRequest,
                object: nil,
                userInfo: ["text": AssessmentTheme.PromptCopy.spoken(AssessmentTheme.PromptCopy.clockDrawingInstruction)]
            )
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
```

- [ ] **Step 2: Delete `formatTime` helper** — no longer needed.

- [ ] **Step 3: Update file header** to note controls are in ClockDrawingControlsView.

- [ ] **Step 4: Build** → `** BUILD SUCCEEDED **`
- [ ] **Step 5: Commit** — `refactor: strip ClockDrawingPhaseView to canvas-only layout`

---

## Part 3: Verbal Fluency & Word Recall Compatibility

### Task 8: Verify Verbal Fluency Phase

**Files:**
- Read: `VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift`

**Context:** Verbal fluency lives entirely in the left content zone. AvatarZoneView (right panel) stays in its standard rectangular dark layout with the persistent TavusCVIView. The architecture change (Tasks 3–4) does NOT touch this file's content. Verify:

- [ ] **Step 1: Confirm no phase-keyed video references**

VerbalFluencyPhaseView should NOT reference `TavusCVIView`, `conversationURL`, or avatar video. It should only interact via `layoutManager` and `qmciState`. Read the file and confirm.

- [ ] **Step 2: Build and test preview**

Run build and check preview shows: pre-start screen with "Start Timer" button, then active screen with counter, timer, word chips, and word entry field.

- [ ] **Step 3: Verify timer behavior**

The timer in VerbalFluencyPhaseView (60 seconds, visible to patient) is independent of the clock drawing changes. Confirm `stopTimer()` is called in `onDisappear`. Confirm `layoutManager.advanceToNextPhase()` is called on expiry.

Expected: No changes needed. This is a verification-only task.

---

### Task 9: Verify Word Recall Phase

**Files:**
- Read: `VoiceMiniCog/Views/AvatarAssessment/Phases/WordRecallPhaseView.swift`

**Context:** Word recall lives entirely in the left content zone. Same as verbal fluency — the architecture change does NOT touch this file. Verify:

- [ ] **Step 1: Confirm no phase-keyed video references**

WordRecallPhaseView should NOT reference `TavusCVIView`, `conversationURL`, or avatar video. It interacts via `layoutManager`, `qmciState`, and `onComplete`. Read the file and confirm.

- [ ] **Step 2: Verify scoring behavior preserved**

`recalledCount` computation, `allMarked` gate, and `delayedRecallWords` assignment must be unchanged. Confirm.

- [ ] **Step 3: Verify "Complete Assessment" button works**

The "Complete Assessment" button calls `onComplete()` which maps to `AvatarAssessmentCanvas.onComplete`. This flow is unaffected by the avatar architecture changes. Confirm.

Expected: No changes needed. This is a verification-only task.

---

## Part 4: Verification

### Task 10: Full Build + Integration Verification

- [ ] **Step 1: Clean build**

```bash
cd /Users/azamtolla/.cursor/worktrees/VoiceMiniCog/nwz
xcodebuild clean build -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -10
```

- [ ] **Step 2: Run existing tests**

```bash
cd /Users/azamtolla/.cursor/worktrees/VoiceMiniCog/nwz
xcodebuild test -scheme VoiceMiniCog -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -20
```

- [ ] **Step 3: Preview verification checklist**

| View | Expected |
|------|----------|
| **ClockDrawingControlsView** | Status chip, instruction text, green + red buttons |
| **ClockDrawingPhaseView** | Canvas only: white card, dashed circle, no text/timer/buttons |
| **AvatarZoneView** (standard) | Dark gradient, rectangular video area, ring, badge, dots |
| **AvatarZoneView** (clock) | White background, circular video area, brown ring, controls below |
| **VerbalFluencyPhaseView** | Pre-start + active views unchanged |
| **WordRecallPhaseView** | Word cards + scoring unchanged |

- [ ] **Step 4: Verify phase transition animation**

In AvatarAssessmentCanvas preview, manually trigger `layoutManager.transitionTo(.clockDrawing)`. Verify:
- Background gradient smoothly transitions to fully light
- TavusCVIView smoothly morphs from rectangle to circle (spring animation)
- ClockDrawingControlsView fades in below the circular video
- On advancing to `.verbalFluency`, the reverse morph happens seamlessly

---

## Design Decision Log

| Decision | Rationale |
|----------|-----------|
| **Single TavusCVIView at fixed tree position** | Phase transitions animate frame/clipShape but never destroy the view. WebRTC connection persists for the entire assessment. Eliminates the black-rectangle bug caused by Daily call teardown on phase change. |
| **PhaseClipShape (custom animatable Shape)** | iOS 15 has no `AnyShape`. A custom Shape with `animatableData` on corner radius gives smooth rect↔circle interpolation that SwiftUI animates automatically. |
| **Controls-only ClockDrawingControlsView** | Separates interaction UI from video lifecycle. AvatarZoneView owns video positioning; ClockDrawingControlsView owns buttons/text. Clean single-responsibility split. |
| **GeometryReader + .position()** | The video morphs between full-panel (centered) and small circle (top area). Using `.position()` inside `GeometryReader` keeps the video at the same tree level regardless of layout mode. |
| **Reconnection at parent level** | Connection failures can happen in any phase. The shimmer, "Reconnecting…" chip, and clinician banner apply uniformly. The reconnection attempt reuses the existing conversation — no new Tavus session. |
| **Verbal fluency / word recall untouched** | Both live in the left content zone. The right panel (AvatarZoneView) stays in standard rectangular mode for these phases. The architecture change benefits them by preventing video teardown, but no code changes needed. |
| **No static avatar images** | The avatar must always be live Tavus CVI. Static images mask connection failures and break the user's expectation of a living digital assistant. Preview-only placeholders are the sole exception. |

---

## Interaction Flow

```
Assessment starts → conversation created ONCE
    ↓
Phases 1–5 (welcome → word registration):
    AvatarZoneView: dark gradient, rectangular TavusCVIView, standard chrome
    ↓
Phase 6 (clock drawing):
    Background → fully light (spring transition)
    TavusCVIView → morphs from rectangle to circle (PhaseClipShape animation)
    Chrome → ClockDrawingControlsView fades in below circular video
    Left panel → ClockDrawingPhaseView (canvas only)
    ↓
    Clinician taps "Done Drawing"
        → layoutManager.advanceToNextPhase()
        → ClockDrawingPhaseView.onDisappear invalidates timer
        → TavusCVIView morphs back to rectangle (same instance)
        → Background transitions back to dark
        → Standard chrome fades back in
    ↓
Phase 7 (verbal fluency):
    AvatarZoneView: back to dark, rectangular, standard chrome
    Left panel: VerbalFluencyPhaseView (unchanged)
    ↓
Phases 8–9 (story recall → word recall):
    Same standard layout, persistent video
    ↓
Assessment ends → conversation ended ONCE

Video failure at any phase:
    → Pulsing shimmer ring inside current avatar frame (rect or circle)
    → Status chip → "Reconnecting…"
    → Auto-rejoin EXISTING conversation (no new creation)
    → After 10s: clinician-only banner for manual recovery
```

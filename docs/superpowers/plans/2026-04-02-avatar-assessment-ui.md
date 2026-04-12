# Avatar-Guided Assessment UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fluid split-screen assessment UI where a Tavus avatar on the right guides patients through 9 phases, with the left content zone adapting per phase — all in pure SwiftUI with spring animations, light content zone, dark avatar zone, and phase-specific accent colors.

**Architecture:** Single SwiftUI view (`AvatarAssessmentCanvas`) owns the entire screen. An `AvatarLayoutManager` (@Observable) controls avatar width, phase state, accent colors, and transition choreography. Content is rendered by phase-specific child views that swap with crossfade animations. The Tavus WebView persists on the right and never reloads.

**Tech Stack:** SwiftUI (iOS 17+), @Observable, withAnimation(.spring), LinearGradient, WKWebView (existing TavusCVIView), GeometryReader

**Design Spec:** `docs/superpowers/specs/2026-04-02-avatar-assessment-ui-design.md`

---

## File Structure

### New Files (Create)

| File | Responsibility |
|------|---------------|
| `Theme/AssessmentTheme.swift` | New color palette (light content zone, dark avatar zone, phase accents, typography) — does NOT modify MCDesign |
| `Models/AvatarLayoutManager.swift` | @Observable state: current phase, avatar width ratio, accent color, avatar state machine, transition timing |
| `Views/AvatarAssessment/AvatarAssessmentCanvas.swift` | Root view — HStack of content zone + avatar zone, gradient background, progress bar |
| `Views/AvatarAssessment/AvatarZoneView.swift` | Right side — dark radial gradient, TavusCVIView embed, accent ring, state label, opacity control |
| `Views/AvatarAssessment/ContentZoneView.swift` | Left side — phase router that swaps child views with crossfade |
| `Views/AvatarAssessment/ProgressTrackView.swift` | Weighted segmented progress bar at top of content zone |
| `Views/AvatarAssessment/PauseButtonView.swift` | Persistent pill button pinned at bottom of content zone |
| `Views/AvatarAssessment/Phases/WelcomePhaseView.swift` | Phase 1 — intro text, subtest list, begin button |
| `Views/AvatarAssessment/Phases/QAPhaseView.swift` | Reusable Q&A template — used by QDRS (10Q), PHQ-2 (2Q), Orientation (5Q) |
| `Views/AvatarAssessment/Phases/WordRegistrationPhaseView.swift` | Phase 5 — listening prompt, progressive word chip reveal |
| `Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift` | Phase 6 EXPANDED — full canvas, timer, done button |
| `Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift` | Phase 7 EXPANDED — live counter, progress bar, word chips |
| `Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift` | Phase 8 — listen/recall phases, minimal UI |
| `Views/AvatarAssessment/Phases/WordRecallPhaseView.swift` | Phase 9 — reference chips, correct/incorrect reveal, score |

### Modified Files

| File | Change |
|------|--------|
| `ContentView.swift` | Replace `.avatarAssessment` case to launch `AvatarAssessmentCanvas` instead of `TavusAssessmentView` |

### Untouched Files

All existing views (HomeView, QDRSView, PHQ2View, QmciAssessmentView, etc.), models, services, and theme files remain unchanged. The new assessment UI is an entirely separate view tree that reads from existing `AssessmentState` and `QmciState`.

---

## Task 1: AssessmentTheme — Color Palette & Typography

**Files:**
- Create: `VoiceMiniCog/Theme/AssessmentTheme.swift`

- [ ] **Step 1: Create AssessmentTheme.swift**

```swift
//
//  AssessmentTheme.swift
//  VoiceMiniCog
//
//  Color palette and typography for avatar-guided assessment.
//  Light content zone (left) + dark avatar zone (right).
//  Does NOT replace MCDesign — used only by AvatarAssessment views.
//

import SwiftUI

enum AssessmentTheme {

    // MARK: - Content Zone (Light, Patient-Facing)

    enum Content {
        static let background = Color(hex: "#F8F9FA")
        static let textPrimary = Color(hex: "#1C1C1E")
        static let textSecondary = Color(hex: "#6E6E73")
        static let surface = Color.white
        static let surfaceShadow = Color.black.opacity(0.08)
        static let buttonBorder = Color.black.opacity(0.1)
    }

    // MARK: - Avatar Zone (Dark)

    enum Avatar {
        static let backgroundCenter = Color(hex: "#1A1A2E")
        static let backgroundEdge = Color(hex: "#080808")
        static let labelText = Color.white.opacity(0.7)
    }

    // MARK: - Unified Background Gradient

    static let gradientDark = Color(hex: "#080808")
    static let gradientLight = Color(hex: "#F8F9FA")

    // MARK: - Phase Accent Colors

    static let phaseAccents: [Int: Color] = [
        1: Color(hex: "#2563EB"), // Welcome — blue
        2: Color(hex: "#D97706"), // QDRS — amber
        3: Color(hex: "#7C3AED"), // PHQ-2 — violet
        4: Color(hex: "#059669"), // Orientation — emerald
        5: Color(hex: "#DB2777"), // Word Registration — pink
        6: Color(hex: "#DC2626"), // Clock Drawing — red
        7: Color(hex: "#0891B2"), // Verbal Fluency — cyan
        8: Color(hex: "#4F46E5"), // Story Recall — indigo
        9: Color(hex: "#16A34A"), // Word Recall — green
    ]

    static func accent(for phase: Int) -> Color {
        phaseAccents[phase] ?? Color(hex: "#2563EB")
    }

    // MARK: - Answer Buttons

    enum Button {
        static let normalFill = Color.white
        static let normalText = Color(hex: "#1C1C1E")
        static let normalBorder = Color.black.opacity(0.1)
        static let correctFill = Color(hex: "#34C759")
        static let incorrectFill = Color(hex: "#FF3B30")
        static let selectedText = Color.white
        static let height: CGFloat = 56
        static let cornerRadius: CGFloat = 14
    }

    // MARK: - Typography

    enum Fonts {
        static let phaseLabel = Font.system(size: 11, weight: .semibold, design: .rounded).uppercaseSmallCaps()
        static let question = Font.system(size: 19, weight: .semibold, design: .default)
        static let helper = Font.system(size: 14, weight: .regular)
        static let buttonLabel = Font.system(size: 16, weight: .medium)
        static let timerSmall = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let timerLarge = Font.system(size: 32, weight: .bold, design: .monospaced)
        static let counterHero = Font.system(size: 48, weight: .bold, design: .monospaced)
        static let scoreDisplay = Font.system(size: 28, weight: .bold, design: .monospaced)
        static let avatarLabel = Font.system(size: 11, weight: .medium)
    }

    // MARK: - Sizing

    enum Sizing {
        static let buttonMinHeight: CGFloat = 56
        static let progressTrackHeight: CGFloat = 4
        static let avatarRingWidth: CGFloat = 2
        static let pauseButtonHeight: CGFloat = 44
        static let pauseButtonWidth: CGFloat = 120
        static let contentPadding: CGFloat = 16
    }

    // MARK: - Avatar Width Ratios Per Phase

    static let avatarWidthRatios: [Int: CGFloat] = [
        1: 0.65, // Welcome — large
        2: 0.50, // QDRS — medium
        3: 0.50, // PHQ-2 — medium
        4: 0.50, // Orientation — medium
        5: 0.50, // Word Registration — medium
        6: 0.30, // Clock Drawing — small (content takes over)
        7: 0.30, // Verbal Fluency — small (content takes over)
        8: 0.55, // Story Recall — medium-large (narrator)
        9: 0.45, // Word Recall — medium
    ]

    // MARK: - Progress Segment Weights

    /// Relative weights for the 9 phases in the progress bar
    static let progressWeights: [Int] = [1, 4, 1, 2, 1, 3, 3, 2, 1] // 18 units total

    // MARK: - Animation

    enum Anim {
        static let phaseTransition: Animation = .spring(duration: 0.55, bounce: 0.15)
        static let contentFade: Animation = .easeInOut(duration: 0.25)
        static let buttonPress: Animation = .spring(duration: 0.15, bounce: 0.3)
        static let chipAppear: Animation = .spring(duration: 0.35, bounce: 0.25)
        static let ringPulse: Animation = .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Theme/AssessmentTheme.swift', force=False)
project.save()
print('Added AssessmentTheme.swift')
"
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,id=7A23AAEE-441C-4ADF-9564-F11DC3A23B92' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Theme/AssessmentTheme.swift
git commit -m "feat: add AssessmentTheme color palette for avatar-guided assessment"
```

---

## Task 2: AvatarLayoutManager — State Machine & Phase Control

**Files:**
- Create: `VoiceMiniCog/Models/AvatarLayoutManager.swift`

- [ ] **Step 1: Create AvatarLayoutManager.swift**

```swift
//
//  AvatarLayoutManager.swift
//  VoiceMiniCog
//
//  Controls avatar width, phase transitions, accent colors, and avatar state.
//  Single source of truth for the fluid layout system.
//

import SwiftUI
import Observation

// MARK: - Avatar State

enum AvatarBehavior: String {
    case idle          // Welcome, between phases
    case speaking      // Delivering question or instruction
    case listening     // Waiting for patient verbal response
    case waiting       // Patient on independent task (clock, fluency)
    case narrating     // Story recall — sustained speech
    case acknowledging // Post answer-tap flash
    case completing    // End of assessment
}

// MARK: - Assessment Phase

enum AssessmentPhaseID: Int, CaseIterable {
    case welcome = 1
    case qdrs = 2
    case phq2 = 3
    case orientation = 4
    case wordRegistration = 5
    case clockDrawing = 6
    case verbalFluency = 7
    case storyRecall = 8
    case wordRecall = 9

    var displayName: String {
        switch self {
        case .welcome: return "Welcome"
        case .qdrs: return "Memory Questionnaire"
        case .phq2: return "Mood Screen"
        case .orientation: return "Orientation"
        case .wordRegistration: return "Word Learning"
        case .clockDrawing: return "Clock Drawing"
        case .verbalFluency: return "Verbal Fluency"
        case .storyRecall: return "Story Recall"
        case .wordRecall: return "Word Recall"
        }
    }

    var isExpanded: Bool {
        self == .clockDrawing || self == .verbalFluency
    }
}

// MARK: - Layout Manager

@Observable
final class AvatarLayoutManager {

    var currentPhase: AssessmentPhaseID = .welcome
    var avatarBehavior: AvatarBehavior = .idle
    var isTransitioning = false

    // MARK: - Computed Layout

    var avatarWidthRatio: CGFloat {
        AssessmentTheme.avatarWidthRatios[currentPhase.rawValue] ?? 0.50
    }

    var accentColor: Color {
        AssessmentTheme.accent(for: currentPhase.rawValue)
    }

    var avatarOpacity: Double {
        switch currentPhase {
        case .clockDrawing: return 0.4
        case .verbalFluency: return 0.4
        case .wordRecall: return 0.85
        default: return 1.0
        }
    }

    var showAvatarRing: Bool {
        switch avatarBehavior {
        case .waiting: return false
        case .idle: return true
        default: return true
        }
    }

    // MARK: - Phase Navigation

    func advanceToNextPhase() {
        guard let nextPhase = AssessmentPhaseID(rawValue: currentPhase.rawValue + 1) else {
            return
        }
        transitionTo(nextPhase)
    }

    func transitionTo(_ phase: AssessmentPhaseID) {
        guard phase != currentPhase else { return }
        isTransitioning = true

        // ACT 1: fade out content (handled by view animation)
        // ACT 2: resize avatar (spring)
        // ACT 3: fade in new content

        withAnimation(AssessmentTheme.Anim.phaseTransition) {
            currentPhase = phase
            avatarBehavior = defaultBehavior(for: phase)
        }

        // Clear transitioning flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.isTransitioning = false
        }
    }

    private func defaultBehavior(for phase: AssessmentPhaseID) -> AvatarBehavior {
        switch phase {
        case .welcome: return .idle
        case .qdrs, .phq2, .orientation: return .speaking
        case .wordRegistration: return .speaking
        case .clockDrawing: return .waiting
        case .verbalFluency: return .listening
        case .storyRecall: return .narrating
        case .wordRecall: return .listening
        }
    }

    // MARK: - Avatar Behavior Updates

    func setAvatarSpeaking() {
        avatarBehavior = .speaking
    }

    func setAvatarListening() {
        avatarBehavior = .listening
    }

    func setAvatarIdle() {
        avatarBehavior = .idle
    }

    func acknowledgeAnswer() {
        avatarBehavior = .acknowledging
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.avatarBehavior == .acknowledging {
                self?.avatarBehavior = .speaking
            }
        }
    }

    // MARK: - Progress

    var completedPhaseCount: Int {
        currentPhase.rawValue - 1
    }

    var totalPhaseCount: Int {
        AssessmentPhaseID.allCases.count
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Models/AvatarLayoutManager.swift', force=False)
project.save()
print('Added AvatarLayoutManager.swift')
"
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,id=7A23AAEE-441C-4ADF-9564-F11DC3A23B92' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/Models/AvatarLayoutManager.swift
git commit -m "feat: add AvatarLayoutManager state machine for fluid avatar layout"
```

---

## Task 3: AvatarAssessmentCanvas — Root Container View

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p VoiceMiniCog/Views/AvatarAssessment/Phases
```

- [ ] **Step 2: Create AvatarAssessmentCanvas.swift**

```swift
//
//  AvatarAssessmentCanvas.swift
//  VoiceMiniCog
//
//  Root view for the avatar-guided assessment.
//  One unified canvas — content zone left, avatar zone right.
//  Gradient background blends light (left) to dark (right).
//

import SwiftUI

struct AvatarAssessmentCanvas: View {
    @Bindable var assessmentState: AssessmentState
    let conversationURL: String?
    let onComplete: () -> Void
    let onFallback: () -> Void
    let onCancel: () -> Void

    @State private var layoutManager = AvatarLayoutManager()
    @State private var showPauseSheet = false

    var body: some View {
        GeometryReader { geo in
            let avatarWidth = geo.size.width * layoutManager.avatarWidthRatio
            let contentWidth = geo.size.width - avatarWidth

            ZStack {
                // Unified background gradient: light (left) → dark (right)
                unifiedBackground(screenWidth: geo.size.width)

                HStack(spacing: 0) {
                    // Content zone (left)
                    contentZone(width: contentWidth, height: geo.size.height)
                        .frame(width: contentWidth)

                    // Avatar zone (right)
                    avatarZone(width: avatarWidth, height: geo.size.height)
                        .frame(width: avatarWidth)
                }
            }
            .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    // MARK: - Unified Background

    private func unifiedBackground(screenWidth: CGFloat) -> some View {
        let ratio = layoutManager.avatarWidthRatio
        return LinearGradient(
            stops: [
                .init(color: AssessmentTheme.gradientLight, location: 0.0),
                .init(color: AssessmentTheme.gradientLight, location: max(0, 1.0 - ratio - 0.08)),
                .init(color: AssessmentTheme.gradientDark, location: 1.0 - ratio + 0.05),
                .init(color: AssessmentTheme.gradientDark, location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Content Zone

    private func contentZone(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Progress track
            ProgressTrackView(layoutManager: layoutManager)
                .padding(.top, 60) // safe area
                .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)

            // Phase content — swaps with crossfade
            Group {
                switch layoutManager.currentPhase {
                case .welcome:
                    WelcomePhaseView(layoutManager: layoutManager, onStandard: onFallback)

                case .qdrs:
                    QAPhaseView(
                        layoutManager: layoutManager,
                        assessmentState: assessmentState,
                        phaseID: .qdrs
                    )

                case .phq2:
                    QAPhaseView(
                        layoutManager: layoutManager,
                        assessmentState: assessmentState,
                        phaseID: .phq2
                    )

                case .orientation:
                    QAPhaseView(
                        layoutManager: layoutManager,
                        assessmentState: assessmentState,
                        phaseID: .orientation
                    )

                case .wordRegistration:
                    WordRegistrationPhaseView(
                        layoutManager: layoutManager,
                        qmciState: assessmentState.qmciState
                    )

                case .clockDrawing:
                    ClockDrawingPhaseView(
                        layoutManager: layoutManager,
                        assessmentState: assessmentState
                    )

                case .verbalFluency:
                    VerbalFluencyPhaseView(
                        layoutManager: layoutManager,
                        qmciState: assessmentState.qmciState
                    )

                case .storyRecall:
                    StoryRecallPhaseView(
                        layoutManager: layoutManager,
                        qmciState: assessmentState.qmciState
                    )

                case .wordRecall:
                    WordRecallPhaseView(
                        layoutManager: layoutManager,
                        qmciState: assessmentState.qmciState,
                        onComplete: onComplete
                    )
                }
            }
            .padding(.horizontal, AssessmentTheme.Sizing.contentPadding)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .id(layoutManager.currentPhase) // force view identity change for transition
            .animation(AssessmentTheme.Anim.contentFade, value: layoutManager.currentPhase)

            Spacer(minLength: 0)

            // Pause button
            PauseButtonView {
                showPauseSheet = true
            }
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showPauseSheet) {
            pauseSheet
        }
    }

    // MARK: - Avatar Zone

    private func avatarZone(width: CGFloat, height: CGFloat) -> some View {
        AvatarZoneView(
            layoutManager: layoutManager,
            conversationURL: conversationURL,
            width: width,
            height: height
        )
    }

    // MARK: - Pause Sheet

    private var pauseSheet: some View {
        VStack(spacing: 24) {
            Text("Assessment Paused")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AssessmentTheme.Content.textPrimary)

            Text("The patient can take a break. Tap Resume to continue where you left off.")
                .font(.system(size: 16))
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .multilineTextAlignment(.center)

            Button("Resume Assessment") {
                showPauseSheet = false
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(layoutManager.accentColor)
            .cornerRadius(14)

            Button("End Session") {
                showPauseSheet = false
                onCancel()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Color(hex: "#DC2626"))
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 3: Add to Xcode project**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/AvatarAssessmentCanvas.swift', force=False)
project.save()
"
```

- [ ] **Step 4: Build — expect errors (child views don't exist yet)**

This will not compile yet because child views (ProgressTrackView, WelcomePhaseView, etc.) are not created. Proceed to next tasks.

- [ ] **Step 5: Commit (WIP)**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/
git commit -m "wip: add AvatarAssessmentCanvas root container (child views pending)"
```

---

## Task 4: AvatarZoneView, ProgressTrackView, PauseButtonView

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/AvatarZoneView.swift`
- Create: `VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift`
- Create: `VoiceMiniCog/Views/AvatarAssessment/PauseButtonView.swift`

- [ ] **Step 1: Create AvatarZoneView.swift**

```swift
//
//  AvatarZoneView.swift
//  VoiceMiniCog
//
//  Right side of the canvas — dark radial gradient background,
//  Tavus WebView, accent ring, state label. Opacity and ring
//  behavior driven by AvatarLayoutManager.
//

import SwiftUI

struct AvatarZoneView: View {
    let layoutManager: AvatarLayoutManager
    let conversationURL: String?
    let width: CGFloat
    let height: CGFloat

    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Dark radial gradient background
            RadialGradient(
                colors: [
                    AssessmentTheme.Avatar.backgroundCenter,
                    AssessmentTheme.Avatar.backgroundEdge,
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(width, height) * 0.7
            )

            // Tavus video
            if let url = conversationURL {
                TavusCVIView(conversationURL: url)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(16)
                    .opacity(layoutManager.avatarOpacity)
                    .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.avatarOpacity)
            }

            // Accent ring overlay
            if layoutManager.showAvatarRing {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(layoutManager.accentColor, lineWidth: AssessmentTheme.Sizing.avatarRingWidth)
                    .padding(16)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                    .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.accentColor)
            }

            // State label
            if let label = avatarStateLabel {
                VStack {
                    Spacer()
                    Text(label)
                        .font(AssessmentTheme.Fonts.avatarLabel)
                        .foregroundColor(AssessmentTheme.Avatar.labelText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .onChange(of: layoutManager.avatarBehavior) { _, newBehavior in
            updateRingAnimation(for: newBehavior)
        }
        .onAppear {
            updateRingAnimation(for: layoutManager.avatarBehavior)
        }
    }

    private var avatarStateLabel: String? {
        switch layoutManager.avatarBehavior {
        case .speaking: return "Speaking..."
        case .listening: return "Listening..."
        case .narrating: return "Reading story..."
        case .idle, .waiting, .acknowledging, .completing: return nil
        }
    }

    private func updateRingAnimation(for behavior: AvatarBehavior) {
        switch behavior {
        case .speaking, .narrating:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                ringScale = 1.03
            }
            ringOpacity = 1.0
        case .listening:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                ringScale = 1.05
            }
            ringOpacity = 1.0
        case .idle:
            withAnimation(AssessmentTheme.Anim.ringPulse) {
                ringOpacity = 0.4
            }
            ringScale = 1.0
        case .acknowledging:
            withAnimation(.easeOut(duration: 0.3)) {
                ringScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(duration: 0.4)) { ringScale = 1.0 }
            }
            ringOpacity = 1.0
        default:
            ringScale = 1.0
            ringOpacity = 0.0
        }
    }
}
```

- [ ] **Step 2: Create ProgressTrackView.swift**

```swift
//
//  ProgressTrackView.swift
//  VoiceMiniCog
//
//  Weighted segmented progress bar showing assessment progress.
//  Segment widths proportional to phase complexity.
//

import SwiftUI

struct ProgressTrackView: View {
    let layoutManager: AvatarLayoutManager

    private let weights = AssessmentTheme.progressWeights
    private var totalWeight: Int { weights.reduce(0, +) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<weights.count, id: \.self) { index in
                        let phaseIndex = index + 1
                        let segmentWidth = geo.size.width * CGFloat(weights[index]) / CGFloat(totalWeight)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(segmentColor(for: phaseIndex))
                            .frame(width: max(segmentWidth - 2, 4))
                            .opacity(segmentOpacity(for: phaseIndex))
                            .animation(AssessmentTheme.Anim.phaseTransition, value: layoutManager.currentPhase)
                    }
                }
            }
            .frame(height: AssessmentTheme.Sizing.progressTrackHeight)

            // Phase name
            Text(layoutManager.currentPhase.displayName)
                .font(AssessmentTheme.Fonts.phaseLabel)
                .foregroundColor(AssessmentTheme.Content.textSecondary)
                .tracking(0.8)
        }
    }

    private func segmentColor(for phaseIndex: Int) -> Color {
        if phaseIndex <= layoutManager.currentPhase.rawValue {
            return AssessmentTheme.accent(for: phaseIndex)
        }
        return Color.gray.opacity(0.2)
    }

    private func segmentOpacity(for phaseIndex: Int) -> Double {
        if phaseIndex < layoutManager.currentPhase.rawValue {
            return 1.0 // completed
        } else if phaseIndex == layoutManager.currentPhase.rawValue {
            return 1.0 // active (pulse handled separately if needed)
        }
        return 0.3 // upcoming
    }
}
```

- [ ] **Step 3: Create PauseButtonView.swift**

```swift
//
//  PauseButtonView.swift
//  VoiceMiniCog
//
//  Persistent pill-shaped pause button pinned at bottom of content zone.
//

import SwiftUI

struct PauseButtonView: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14))
                Text("Pause")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white.opacity(isPressed ? 1.0 : 0.7))
            .frame(width: AssessmentTheme.Sizing.pauseButtonWidth,
                   height: AssessmentTheme.Sizing.pauseButtonHeight)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { isPressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.1)) { isPressed = false } }
        )
    }
}
```

- [ ] **Step 4: Add all 3 files to Xcode project**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/AvatarZoneView.swift', force=False)
project.add_file('VoiceMiniCog/Views/AvatarAssessment/ProgressTrackView.swift', force=False)
project.add_file('VoiceMiniCog/Views/AvatarAssessment/PauseButtonView.swift', force=False)
project.save()
"
```

- [ ] **Step 5: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/
git commit -m "feat: add AvatarZoneView, ProgressTrackView, PauseButtonView"
```

---

## Task 5: WelcomePhaseView — Phase 1

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/WelcomePhaseView.swift`

- [ ] **Step 1: Create WelcomePhaseView.swift**

```swift
//
//  WelcomePhaseView.swift
//  VoiceMiniCog
//
//  Phase 1 — Welcome screen. Shows assessment overview,
//  subtest list with points, and Begin button.
//

import SwiftUI

struct WelcomePhaseView: View {
    let layoutManager: AvatarLayoutManager
    let onStandard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44))
                    .foregroundColor(layoutManager.accentColor)

                Text("Brain Health Assessment")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AssessmentTheme.Content.textPrimary)

                Text("6 cognitive activities, about 5-7 minutes")
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundColor(AssessmentTheme.Content.textSecondary)

                // Subtest list card
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(QmciSubtest.allCases, id: \.rawValue) { subtest in
                        HStack(spacing: 12) {
                            Image(systemName: subtest.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(layoutManager.accentColor)
                                .frame(width: 28)
                            Text(subtest.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AssessmentTheme.Content.textPrimary)
                            Spacer()
                            Text("\(subtest.maxScore) pts")
                                .font(.system(size: 13))
                                .foregroundColor(AssessmentTheme.Content.textSecondary)
                        }
                    }
                }
                .padding(20)
                .background(AssessmentTheme.Content.surface)
                .cornerRadius(14)
                .shadow(color: AssessmentTheme.Content.surfaceShadow, radius: 12, y: 2)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    layoutManager.transitionTo(.qdrs)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                        Text("Begin Assessment")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AssessmentTheme.Button.height)
                    .background(layoutManager.accentColor)
                    .cornerRadius(AssessmentTheme.Button.cornerRadius)
                    .shadow(color: layoutManager.accentColor.opacity(0.3), radius: 8, y: 4)
                }

                Button {
                    onStandard()
                } label: {
                    Text("Standard Mode (No Avatar)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AssessmentTheme.Content.textSecondary)
                }
                .frame(height: 44)
            }
            .padding(.bottom, 16)
        }
    }
}
```

- [ ] **Step 2: Add to Xcode and build**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/WelcomePhaseView.swift', force=False)
project.save()
"
```

- [ ] **Step 3: Commit**

```bash
git add VoiceMiniCog/Views/AvatarAssessment/Phases/WelcomePhaseView.swift
git commit -m "feat: add WelcomePhaseView for avatar assessment phase 1"
```

---

## Task 6: QAPhaseView — Reusable Q&A Template (QDRS, PHQ-2, Orientation)

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift`

- [ ] **Step 1: Create QAPhaseView.swift**

This is the most complex reusable view — it handles 3 different question sets (QDRS 10Q, PHQ-2 2Q, Orientation 5Q) with phase-appropriate answer buttons, scoring, and auto-advance.

```swift
//
//  QAPhaseView.swift
//  VoiceMiniCog
//
//  Reusable Q&A template for QDRS (10 questions), PHQ-2 (2 questions),
//  and Orientation (5 questions). Shows question text, answer buttons,
//  and progress. Avatar asks questions vocally; this provides visual
//  reinforcement and clinician scoring.
//

import SwiftUI

struct QAPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var assessmentState: AssessmentState
    let phaseID: AssessmentPhaseID

    @State private var currentIndex = 0
    @State private var selectedAnswer: Int? = nil
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Question counter
                Text("\(currentIndex + 1) of \(totalQuestions)")
                    .font(AssessmentTheme.Fonts.timerSmall)
                    .foregroundColor(AssessmentTheme.Content.textSecondary)

                // Question text
                Text(currentQuestionText)
                    .font(AssessmentTheme.Fonts.question)
                    .foregroundColor(AssessmentTheme.Content.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 10)

                // Answer buttons
                VStack(spacing: 8) {
                    ForEach(Array(currentAnswers.enumerated()), id: \.offset) { index, answer in
                        answerButton(text: answer, index: index)
                    }
                }
                .opacity(animateIn ? 1 : 0)
            }

            Spacer()

            // Phase-specific score display
            if phaseID == .orientation {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(orientationDotColor(at: i))
                            .frame(width: 10, height: 10)
                    }
                    Spacer()
                    Text("\(assessmentState.qmciState.orientationScore)/10")
                        .font(AssessmentTheme.Fonts.timerSmall)
                        .foregroundColor(AssessmentTheme.Content.textSecondary)
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.3).delay(0.15)) { animateIn = true } }
        .onChange(of: currentIndex) { _, _ in
            animateIn = false
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) { animateIn = true }
        }
    }

    // MARK: - Answer Button

    private func answerButton(text: String, index: Int) -> some View {
        Button {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            selectedAnswer = index
            recordAnswer(index)
            layoutManager.acknowledgeAnswer()

            // Auto-advance after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if currentIndex < totalQuestions - 1 {
                    selectedAnswer = nil
                    currentIndex += 1
                } else {
                    // Phase complete — advance
                    layoutManager.advanceToNextPhase()
                }
            }
        } label: {
            Text(text)
                .font(AssessmentTheme.Fonts.buttonLabel)
                .foregroundColor(selectedAnswer == index ? AssessmentTheme.Button.selectedText : AssessmentTheme.Button.normalText)
                .frame(maxWidth: .infinity)
                .frame(height: AssessmentTheme.Button.height)
                .background(selectedAnswer == index ? layoutManager.accentColor : AssessmentTheme.Button.normalFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AssessmentTheme.Button.cornerRadius)
                        .stroke(selectedAnswer == index ? Color.clear : AssessmentTheme.Button.normalBorder, lineWidth: 1)
                )
                .cornerRadius(AssessmentTheme.Button.cornerRadius)
                .shadow(
                    color: selectedAnswer == index ? layoutManager.accentColor.opacity(0.3) : .clear,
                    radius: selectedAnswer == index ? 8 : 0,
                    y: selectedAnswer == index ? 4 : 0
                )
                .scaleEffect(selectedAnswer == index ? 1.0 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Binding

    private var totalQuestions: Int {
        switch phaseID {
        case .qdrs: return 10
        case .phq2: return 2
        case .orientation: return ORIENTATION_ITEMS.count
        default: return 0
        }
    }

    private var currentQuestionText: String {
        switch phaseID {
        case .qdrs:
            return assessmentState.qdrsState.questions[safe: currentIndex]?.text ?? ""
        case .phq2:
            return currentIndex < PHQ2_QUESTIONS.count ? PHQ2_QUESTIONS[currentIndex] : ""
        case .orientation:
            return ORIENTATION_ITEMS[safe: currentIndex]?.question ?? ""
        default:
            return ""
        }
    }

    private var currentAnswers: [String] {
        switch phaseID {
        case .qdrs:
            return ["No Change", "Sometimes", "Yes, Changed"]
        case .phq2:
            return ["Not at all", "Several days", "More than half the days", "Nearly every day"]
        case .orientation:
            return ["Correct", "Incorrect"]
        default:
            return []
        }
    }

    private func recordAnswer(_ index: Int) {
        switch phaseID {
        case .qdrs:
            let answer = QDRSAnswer(rawValue: index) ?? .noChange
            assessmentState.qdrsState.setAnswer(at: currentIndex, answer: answer)
        case .phq2:
            let answer = PHQ2Answer(rawValue: index) ?? .notAtAll
            if currentIndex == 0 {
                assessmentState.phq2State.answer1 = answer
            } else {
                assessmentState.phq2State.answer2 = answer
            }
        case .orientation:
            assessmentState.qmciState.orientationAnswers[currentIndex] = (index == 0)
        default:
            break
        }
    }

    private func orientationDotColor(at index: Int) -> Color {
        guard let answer = assessmentState.qmciState.orientationAnswers[safe: index] else {
            return Color.gray.opacity(0.2)
        }
        if let correct = answer {
            return correct ? Color(hex: "#34C759") : Color(hex: "#FF3B30")
        }
        return Color.gray.opacity(0.2)
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 2: Add to Xcode and commit**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift', force=False)
project.save()
"
git add VoiceMiniCog/Views/AvatarAssessment/Phases/QAPhaseView.swift
git commit -m "feat: add reusable QAPhaseView for QDRS, PHQ-2, Orientation"
```

---

## Task 7: WordRegistrationPhaseView — Phase 5

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/WordRegistrationPhaseView.swift`

- [ ] **Step 1: Create WordRegistrationPhaseView.swift**

```swift
//
//  WordRegistrationPhaseView.swift
//  VoiceMiniCog
//
//  Phase 5 — Avatar reads 5 words. Word chips appear progressively.
//  Patient repeats words. Clinician observes.
//

import SwiftUI

struct WordRegistrationPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var revealedCount = 0
    @State private var isRevealing = false

    var words: [String] { qmciState.registrationWords }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "ear.fill")
                    .font(.system(size: 40))
                    .foregroundColor(layoutManager.accentColor)

                Text("Listen carefully")
                    .font(AssessmentTheme.Fonts.question)
                    .foregroundColor(AssessmentTheme.Content.textPrimary)

                Text("The avatar will say 5 words.\nRepeat them back when asked.")
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundColor(AssessmentTheme.Content.textSecondary)
                    .multilineTextAlignment(.center)

                // Word chips — revealed progressively
                HStack(spacing: 10) {
                    ForEach(0..<words.count, id: \.self) { index in
                        wordChip(word: words[index], isRevealed: index < revealedCount)
                    }
                }
                .padding(.top, 8)
            }

            Spacer()

            // Advance when avatar finishes
            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                layoutManager.advanceToNextPhase()
            } label: {
                Text("Continue to Clock Drawing")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AssessmentTheme.Button.height)
                    .background(layoutManager.accentColor)
                    .cornerRadius(AssessmentTheme.Button.cornerRadius)
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            startWordReveal()
        }
    }

    private func wordChip(word: String, isRevealed: Bool) -> some View {
        Text(isRevealed ? word : "...")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(isRevealed ? AssessmentTheme.Content.textPrimary : AssessmentTheme.Content.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isRevealed ? layoutManager.accentColor.opacity(0.12) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .scaleEffect(isRevealed ? 1.0 : 0.9)
            .animation(AssessmentTheme.Anim.chipAppear, value: isRevealed)
    }

    private func startWordReveal() {
        guard !isRevealing else { return }
        isRevealing = true
        for i in 0..<words.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                withAnimation { revealedCount = i + 1 }
            }
        }
    }
}
```

- [ ] **Step 2: Add to Xcode and commit**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/WordRegistrationPhaseView.swift', force=False)
project.save()
"
git add VoiceMiniCog/Views/AvatarAssessment/Phases/
git commit -m "feat: add WordRegistrationPhaseView with progressive chip reveal"
```

---

## Task 8: ClockDrawingPhaseView — Phase 6 (EXPANDED)

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift`

- [ ] **Step 1: Create ClockDrawingPhaseView.swift**

```swift
//
//  ClockDrawingPhaseView.swift
//  VoiceMiniCog
//
//  Phase 6 EXPANDED — Drawing canvas fills the content zone.
//  Avatar shrinks to 30%, dims to 0.4, waits patiently.
//  Timer + Done button at bottom.
//

import SwiftUI

struct ClockDrawingPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var assessmentState: AssessmentState

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []
    @State private var timeRemaining = 180 // 3 minutes
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            // Instruction
            Text("Draw a clock. Put in all the numbers.\nSet the hands to ten past eleven.")
                .font(AssessmentTheme.Fonts.question)
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            // Canvas — fills all available space
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)

                ZStack {
                    // White drawing surface
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)

                    // Dashed circle guide
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                        .foregroundColor(Color.gray.opacity(0.25))
                        .frame(width: size * 0.75, height: size * 0.75)

                    // Drawing
                    Canvas { context, canvasSize in
                        for line in lines {
                            drawStroke(line, in: context)
                        }
                        if !currentLine.isEmpty {
                            drawStroke(currentLine, in: context)
                        }
                    }
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                currentLine.append(value.location)
                            }
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

            // Bottom bar: timer + done button
            HStack {
                // Timer
                Text(formatTime(timeRemaining))
                    .font(AssessmentTheme.Fonts.timerLarge)
                    .foregroundColor(timeRemaining <= 30 ? Color(hex: "#DC2626") : AssessmentTheme.Content.textPrimary)
                    .monospacedDigit()

                Spacer()

                // Done button
                Button {
                    timer?.invalidate()
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    layoutManager.advanceToNextPhase()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("Done Drawing")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: AssessmentTheme.Button.height)
                    .background(layoutManager.accentColor)
                    .cornerRadius(AssessmentTheme.Button.cornerRadius)
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func drawStroke(_ points: [CGPoint], in context: GraphicsContext) {
        var path = Path()
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(.black), lineWidth: 2.5)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                layoutManager.advanceToNextPhase()
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
```

- [ ] **Step 2: Add to Xcode and commit**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/ClockDrawingPhaseView.swift', force=False)
project.save()
"
git add VoiceMiniCog/Views/AvatarAssessment/Phases/
git commit -m "feat: add ClockDrawingPhaseView with full canvas and timer"
```

---

## Task 9: VerbalFluencyPhaseView — Phase 7 (EXPANDED)

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift`

- [ ] **Step 1: Create VerbalFluencyPhaseView.swift**

```swift
//
//  VerbalFluencyPhaseView.swift
//  VoiceMiniCog
//
//  Phase 7 EXPANDED — 60-second animal naming task.
//  Large counter, progress bar, word chips that spring in.
//

import SwiftUI

struct VerbalFluencyPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var timeRemaining = 60
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var wordsEntered: [String] = []
    @State private var currentWord = ""

    var body: some View {
        VStack(spacing: 16) {
            if !isRunning {
                // Pre-start
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundColor(layoutManager.accentColor)

                    Text("Name as many animals\nas you can")
                        .font(AssessmentTheme.Fonts.question)
                        .foregroundColor(AssessmentTheme.Content.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("You have one minute.")
                        .font(AssessmentTheme.Fonts.helper)
                        .foregroundColor(AssessmentTheme.Content.textSecondary)

                    Button {
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        startTimer()
                    } label: {
                        Text("Start Timer")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 200, height: AssessmentTheme.Button.height)
                            .background(layoutManager.accentColor)
                            .cornerRadius(AssessmentTheme.Button.cornerRadius)
                    }
                }
                Spacer()
            } else {
                // Active — counter + progress + chips
                VStack(spacing: 8) {
                    // Big counter
                    Text("\(wordsEntered.count)")
                        .font(AssessmentTheme.Fonts.counterHero)
                        .foregroundColor(layoutManager.accentColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("animals")
                        .font(AssessmentTheme.Fonts.helper)
                        .foregroundColor(AssessmentTheme.Content.textSecondary)

                    // Progress bar (60s)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(layoutManager.accentColor)
                                .frame(width: geo.size.width * CGFloat(60 - timeRemaining) / 60.0)
                                .animation(.linear(duration: 1), value: timeRemaining)
                        }
                    }
                    .frame(height: 4)

                    // Timer
                    Text("0:\(String(format: "%02d", timeRemaining))")
                        .font(AssessmentTheme.Fonts.timerSmall)
                        .foregroundColor(timeRemaining <= 10 ? Color(hex: "#DC2626") : AssessmentTheme.Content.textSecondary)
                        .monospacedDigit()
                }
                .padding(.top, 8)

                // Word chips
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(wordsEntered, id: \.self) { word in
                            Text(word)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AssessmentTheme.Content.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(layoutManager.accentColor.opacity(0.12))
                                .cornerRadius(8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                // Manual word entry (clinician taps to add words heard)
                HStack(spacing: 8) {
                    TextField("Add animal...", text: $currentWord)
                        .font(.system(size: 16))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AssessmentTheme.Content.surface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AssessmentTheme.Button.normalBorder, lineWidth: 1)
                        )
                        .submitLabel(.done)
                        .onSubmit { addWord() }

                    Button {
                        addWord()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(layoutManager.accentColor)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onDisappear {
            timer?.invalidate()
            qmciState.verbalFluencyWords = wordsEntered
        }
    }

    private func addWord() {
        let word = currentWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, !wordsEntered.contains(word) else { return }
        withAnimation(AssessmentTheme.Anim.chipAppear) {
            wordsEntered.append(word)
        }
        currentWord = ""
    }

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                qmciState.verbalFluencyWords = wordsEntered
                layoutManager.advanceToNextPhase()
            }
        }
    }
}

// MARK: - Flow Layout (horizontal wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

- [ ] **Step 2: Add to Xcode and commit**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/VerbalFluencyPhaseView.swift', force=False)
project.save()
"
git add VoiceMiniCog/Views/AvatarAssessment/Phases/
git commit -m "feat: add VerbalFluencyPhaseView with counter, timer, flow layout chips"
```

---

## Task 10: StoryRecallPhaseView + WordRecallPhaseView — Phases 8 & 9

**Files:**
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift`
- Create: `VoiceMiniCog/Views/AvatarAssessment/Phases/WordRecallPhaseView.swift`

- [ ] **Step 1: Create StoryRecallPhaseView.swift**

```swift
//
//  StoryRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 8 — Avatar reads story (narrating state), then patient retells.
//  Minimal left panel — just instruction text and phase indicator.
//

import SwiftUI

struct StoryRecallPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState

    @State private var phase: StoryPhase = .listening

    enum StoryPhase { case listening, recalling }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: phase == .listening ? "book.fill" : "mic.fill")
                    .font(.system(size: 44))
                    .foregroundColor(layoutManager.accentColor)

                Text(phase == .listening
                     ? "Listen carefully to\nthis short story"
                     : "Now tell me everything\nyou remember")
                    .font(AssessmentTheme.Fonts.question)
                    .foregroundColor(AssessmentTheme.Content.textPrimary)
                    .multilineTextAlignment(.center)

                Text(phase == .listening
                     ? "The avatar is reading a story.\nPay close attention."
                     : "Take your time. Say everything\nyou can recall.")
                    .font(AssessmentTheme.Fonts.helper)
                    .foregroundColor(AssessmentTheme.Content.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if phase == .listening {
                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    withAnimation { phase = .recalling }
                    layoutManager.setAvatarListening()
                } label: {
                    Text("Story Finished — Begin Recall")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AssessmentTheme.Button.height)
                        .background(layoutManager.accentColor)
                        .cornerRadius(AssessmentTheme.Button.cornerRadius)
                }
                .padding(.bottom, 16)
            } else {
                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    layoutManager.advanceToNextPhase()
                } label: {
                    Text("Continue to Word Recall")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AssessmentTheme.Button.height)
                        .background(layoutManager.accentColor)
                        .cornerRadius(AssessmentTheme.Button.cornerRadius)
                }
                .padding(.bottom, 16)
            }
        }
    }
}
```

- [ ] **Step 2: Create WordRecallPhaseView.swift**

```swift
//
//  WordRecallPhaseView.swift
//  VoiceMiniCog
//
//  Phase 9 — Patient recalls the 5 registration words.
//  Shows reference chips, correct/incorrect marking, final score.
//

import SwiftUI

struct WordRecallPhaseView: View {
    let layoutManager: AvatarLayoutManager
    @Bindable var qmciState: QmciState
    let onComplete: () -> Void

    @State private var recallResults: [Bool?]

    init(layoutManager: AvatarLayoutManager, qmciState: QmciState, onComplete: @escaping () -> Void) {
        self.layoutManager = layoutManager
        self.qmciState = qmciState
        self.onComplete = onComplete
        _recallResults = State(initialValue: Array(repeating: nil, count: qmciState.registrationWords.count))
    }

    var words: [String] { qmciState.registrationWords }

    var recalledCount: Int {
        recallResults.compactMap { $0 }.filter { $0 }.count
    }

    var allMarked: Bool {
        recallResults.allSatisfy { $0 != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44))
                    .foregroundColor(layoutManager.accentColor)

                Text("What were the 5 words?")
                    .font(AssessmentTheme.Fonts.question)
                    .foregroundColor(AssessmentTheme.Content.textPrimary)

                // Word chips with correct/incorrect marking
                VStack(spacing: 10) {
                    ForEach(0..<words.count, id: \.self) { index in
                        wordRow(index: index)
                    }
                }
                .padding(20)
                .background(AssessmentTheme.Content.surface)
                .cornerRadius(14)
                .shadow(color: AssessmentTheme.Content.surfaceShadow, radius: 12, y: 2)

                // Score
                if allMarked {
                    Text("\(recalledCount)/\(words.count) recalled")
                        .font(AssessmentTheme.Fonts.scoreDisplay)
                        .foregroundColor(layoutManager.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()

            if allMarked {
                Button {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    qmciState.delayedRecallWords = words.enumerated().compactMap { i, w in
                        recallResults[i] == true ? w : nil
                    }
                    onComplete()
                } label: {
                    Text("Complete Assessment")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AssessmentTheme.Button.height)
                        .background(layoutManager.accentColor)
                        .cornerRadius(AssessmentTheme.Button.cornerRadius)
                        .shadow(color: layoutManager.accentColor.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func wordRow(index: Int) -> some View {
        HStack(spacing: 12) {
            Text(words[index])
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AssessmentTheme.Content.textPrimary)
                .strikethrough(recallResults[index] == false)

            Spacer()

            // Correct button
            Button {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(AssessmentTheme.Anim.buttonPress) { recallResults[index] = true }
            } label: {
                Image(systemName: recallResults[index] == true ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundColor(recallResults[index] == true ? Color(hex: "#34C759") : Color.gray.opacity(0.3))
            }

            // Incorrect button
            Button {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(AssessmentTheme.Anim.buttonPress) { recallResults[index] = false }
            } label: {
                Image(systemName: recallResults[index] == false ? "xmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 28))
                    .foregroundColor(recallResults[index] == false ? Color(hex: "#FF3B30") : Color.gray.opacity(0.3))
            }
        }
        .frame(height: 48)
    }
}
```

- [ ] **Step 3: Add both to Xcode and commit**

```bash
python3 -c "
from pbxproj import XcodeProject
project = XcodeProject.load('VoiceMiniCog.xcodeproj/project.pbxproj')
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/StoryRecallPhaseView.swift', force=False)
project.add_file('VoiceMiniCog/Views/AvatarAssessment/Phases/WordRecallPhaseView.swift', force=False)
project.save()
"
git add VoiceMiniCog/Views/AvatarAssessment/Phases/
git commit -m "feat: add StoryRecallPhaseView and WordRecallPhaseView"
```

---

## Task 11: Wire Into ContentView + Build + Verify

**Files:**
- Modify: `VoiceMiniCog/ContentView.swift`

- [ ] **Step 1: Update ContentView .avatarAssessment case**

Replace the existing `.avatarAssessment` case in `ContentView.swift` to launch `AvatarAssessmentCanvas` instead of `TavusAssessmentView`:

```swift
case .avatarAssessment:
    AvatarAssessmentCanvas(
        assessmentState: assessmentState,
        conversationURL: TavusService.shared.activeConversation?.conversation_url,
        onComplete: {
            assessmentState.currentPhase = .scoring
            computeAllScores()
            assessmentState.currentPhase = .report
            currentScreen = .report
        },
        onFallback: {
            currentScreen = .qmciAssessment
        },
        onCancel: {
            currentScreen = .home
        }
    )
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,id=7A23AAEE-441C-4ADF-9564-F11DC3A23B92' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Fix any compilation errors**

Address type mismatches, missing properties, or scope issues discovered during build.

- [ ] **Step 4: Commit**

```bash
git add VoiceMiniCog/ContentView.swift
git commit -m "feat: wire AvatarAssessmentCanvas into ContentView assessment flow"
```

---

## Task 12: End-to-End Walkthrough Test

- [ ] **Step 1: Run app on iPad simulator**

```bash
xcodebuild -scheme VoiceMiniCog -destination 'platform=iOS Simulator,id=7A23AAEE-441C-4ADF-9564-F11DC3A23B92' build
xcrun simctl boot 7A23AAEE-441C-4ADF-9564-F11DC3A23B92
```

- [ ] **Step 2: Manual test checklist**

1. Launch app → Home → Start → QDRS → PHQ-2 → Mode Picker
2. Tap "Use Voice Avatar"
3. Verify: Welcome phase shows with avatar on right (~65% width)
4. Tap "Begin Assessment" → QDRS phase, avatar shrinks to 50%
5. Answer 10 QDRS questions → auto-advances to PHQ-2
6. Answer 2 PHQ-2 questions → advances to Orientation
7. Answer 5 orientation questions → advances to Word Registration
8. Word chips reveal progressively → advance to Clock Drawing
9. Verify avatar shrinks to 30%, dims. Canvas fills left side.
10. Draw → tap Done → Verbal Fluency
11. Start timer, add words → timer ends → Story Recall
12. Avatar narrates → transition to recall → Word Recall
13. Mark words correct/incorrect → Complete Assessment
14. Verify: lands on PCP Report View

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete avatar-guided assessment UI with 9-phase fluid layout"
```

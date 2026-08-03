//
//  AssessmentTheme.swift
//  VoiceMiniCog
//
//  Design tokens for the avatar-guided assessment UI.
//  Parallel to MCDesign/MercyColors — used ONLY by AvatarAssessment views.
//

import SwiftUI

// MARK: - AssessmentTheme

enum AssessmentTheme {

    // MARK: Content Zone (light, patient-facing left panel)

    enum Content {
        /// Page background: #F8F9FA
        static let background    = Color(hex: "#F8F9FA")
        /// Primary text: #1C1C1E (iOS system label equivalent)
        static let textPrimary   = Color(hex: "#1C1C1E")
        /// Secondary text: #6E6E73 (iOS secondary label equivalent)
        static let textSecondary = Color(hex: "#6E6E73")
        /// Card / surface background: white with shadow
        static let surface       = Color.white
        /// Surface shadow — use as shadow color at 0.08 opacity
        static let shadowColor   = Color.black
    }

    // MARK: Avatar Zone (dark right panel)

    enum Avatar {
        /// HA-inspired dark chrome — formalized from Home Assistant palette
        /// Radial gradient center color: #1C1C1C (HA card surface)
        static let gradientCenter = Color(hex: "#1C1C1C")
        /// Radial gradient edge color: #111111 (HA page background)
        static let gradientEdge   = Color(hex: "#111111")

        /// Radial gradient filling the avatar panel.
        static let backgroundGradient = RadialGradient(
            colors: [gradientCenter, gradientEdge],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
    }

    // MARK: Split-Screen Canvas Colors

    /// Dark edge of the split-screen canvas gradient: #080808
    static let canvasDark = Color(hex: "#080808")

    /// Unified canvas base — warm neutral off-white. One color, both panes,
    /// every screen. No accent tint, no gradient. All phases share this.
    static let canvasBase = Color(red: 0.976, green: 0.980, blue: 0.988)

    /// Unified horizontal gradient: canvasDark on the right → Content.background on the left.
    static let splitGradient = LinearGradient(
        stops: [
            .init(color: canvasDark, location: 0.0),
            .init(color: Content.background, location: 1.0)
        ],
        startPoint: .trailing,
        endPoint: .leading
    )

    // MARK: Phase Accent Colors

    /// Nine accent colors, one per assessment phase. These are the
    /// AUTHORITATIVE hues used by both the chevron track and the
    /// full-screen phase tint (see `tint(for:)` below) — the tab color
    /// and the background wash are identical.
    enum Phase {
        static let welcome  = Color.blue                                    // Welcome
        static let orient   = Color(red: 0.2,  green: 0.75, blue: 0.3)       // Orientation — green
        static let register = Color(red: 0.95, green: 0.3,  blue: 0.4)       // Word Registration — pink
        static let clock    = Color(red: 1.0,  green: 0.35, blue: 0.2)       // Clock Drawing — orange-red
        static let fluency  = Color(red: 0.95, green: 0.3,  blue: 0.4)       // (unused in sequence — kept for compat)
        static let story    = Color(red: 0.5,  green: 0.3,  blue: 0.85)      // Story Recall — purple
        static let recall   = Color(red: 0.95, green: 0.3,  blue: 0.4)       // Word Recall — matches Word Registration
        static let qdrs     = Color(red: 0.2,  green: 0.6,  blue: 0.95)      // Caregiver — sky blue (reused for Fluency)
        static let results  = Color(red: 0.2,  green: 0.75, blue: 0.3)       // Completion — green

        // Verbose aliases used by PhaseHeaderBadge and QMCIAvatarContext wiring
        static let orientation:   Color = orient
        static let registration:  Color = register
        static let clockDrawing:  Color = clock
        static let storyRecall:   Color = story
        // wordRecall echoes wordRegistration — Words + Recall are the same
        // memory task split in time, so they share an accent color. The
        // chevron track, ambient bloom, and phase header all read this
        // through either `Phase.wordRecall` or `accent(for:)` below, which
        // both resolve to the same color as wordRegistration.
        static let wordRecall:    Color = fluency   // matches accent(for: 5)

        /// Ordered array matching progress segment weights.
        static let all: [Color] = [
            welcome, orient, register, clock, fluency, story, recall, qdrs, results
        ]
    }

    // MARK: Answer Button Styles

    enum Button {
        // Normal state
        static let normalFill       = Color.white
        static let normalText       = Color(hex: "#1C1C1E")
        static let normalBorder     = Color(hex: "#E5E5EA") // subtle gray border

        // Selected state (uses phase accent fill + white text — apply accent externally)
        static let selectedText     = Color.white

        // Feedback states
        static let correctFill      = Color(hex: "#34C759") // system green
        static let incorrectFill    = Color(hex: "#FF3B30") // system red
        static let feedbackText     = Color.white
    }

    // MARK: Typography

    enum Typography {
        /// Phase label above question — 11pt, rounded, all-caps weight
        static let phaseLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
        /// Main question text — 19pt semibold
        static let question   = Font.system(size: 19, weight: .semibold, design: .default)
        /// Helper / instruction text — 14pt regular
        static let helper     = Font.system(size: 14, weight: .regular, design: .default)
        /// Answer button label — 16pt medium
        static let buttonLabel = Font.system(size: 16, weight: .medium, design: .default)
        /// Avatar zone label — 13pt medium
        static let avatarLabel = Font.system(size: 13, weight: .medium, design: .default)

        // Timers & counters (monospaced for stable width)
        /// General timer display — 17pt monospaced regular
        static let timer          = Font.system(size: 17, weight: .regular, design: .monospaced)
        /// Small timer display — 13pt monospaced medium
        static let timerSmall     = Font.system(size: 13, weight: .medium, design: .monospaced)
        /// Large counter hero (e.g., fluency word count) — 48pt monospaced bold
        static let counterHero    = Font.system(size: 48, weight: .bold, design: .monospaced)
        /// Score display — 28pt monospaced bold
        static let score          = Font.system(size: 28, weight: .bold, design: .monospaced)
        /// Score display alias
        static let scoreDisplay   = Font.system(size: 28, weight: .bold, design: .monospaced)
    }

    /// Alias for views that reference `Fonts` instead of `Typography`
    typealias Fonts = Typography

    // MARK: Sizing

    enum Size {
        /// Minimum tappable height for answer buttons: 56 pt
        static let buttonMinHeight: CGFloat = 56
        /// Progress track thickness: 4 pt
        static let progressTrack: CGFloat = 4
        /// Progress track height (alias)
        static let progressTrackHeight: CGFloat = 4
        /// Ring / indicator line width: 2 pt
        static let ring: CGFloat = 2
        /// Avatar accent ring stroke width: 3 pt
        static let avatarRingWidth: CGFloat = 3
        /// Pause button diameter: 44 pt
        static let pauseButton: CGFloat = 44
        /// Pause button width: 44 pt
        static let pauseButtonWidth: CGFloat = 44
        /// Pause button height: 44 pt
        static let pauseButtonHeight: CGFloat = 44
        /// Standard horizontal padding for content panel: 16 pt
        static let contentPadding: CGFloat = 16
    }

    /// Alias for views that reference `Sizing` instead of `Size`
    typealias Sizing = Size

    // MARK: Avatar Width Ratios (fraction of total screen width)

    enum AvatarRatio {
        /// Welcome / intro — balanced 50/50
        static let welcome: CGFloat      = 0.50
        /// Q&A phases (orientation, registration, word recall) — balanced 50/50
        static let qa: CGFloat           = 0.50
        /// Clock drawing — content takes over (70/30) so the canvas gets room
        static let clock: CGFloat        = 0.30
        /// Verbal fluency — slightly wider avatar pane (0.45) so the ring
        /// + counter feel anchored, avatar stays present as "listener"
        static let fluency: CGFloat      = 0.45
        /// Back-compat alias — prefer `clock` or `fluency`
        static let clockFluency: CGFloat = clock
        /// Story recall — avatar dominant (40/60), patient just listens
        static let story: CGFloat        = 0.60
        /// Delayed word recall — balanced 50/50
        static let recall: CGFloat       = 0.50
    }

    // MARK: Avatar Width Ratios by Phase ID

    /// Maps AssessmentPhaseID.rawValue → avatar width fraction.
    static let avatarWidthRatios: [Int: CGFloat] = [
        1: AvatarRatio.welcome,       // welcome
        2: AvatarRatio.qa,            // qdrs
        3: AvatarRatio.qa,            // phq2
        4: AvatarRatio.qa,            // orientation
        5: AvatarRatio.qa,            // wordRegistration
        6: AvatarRatio.clock,         // clockDrawing
        7: AvatarRatio.fluency,       // verbalFluency — 0.45 per design brief
        8: AvatarRatio.story,         // storyRecall
        9: AvatarRatio.recall,        // wordRecall
        10: AvatarRatio.welcome,      // completion
    ]

    /// Phase accent color by AssessmentPhaseID.rawValue (1-based).
    /// Authoritative mapping — both the chevron track and the full-screen
    /// phase tint derive from this single switch. Words + Recall share a
    /// hue so patients see the link between the two halves of the memory
    /// task.
    static func accent(for phaseRawValue: Int) -> Color {
        switch phaseRawValue {
        case 1:  return Phase.welcome    // Welcome
        case 2:  return Phase.qdrs       // QDRS (Caregiver) — sky blue
        case 3:  return Phase.qdrs       // PHQ-2 — reuse sky blue
        case 4:  return Phase.orient     // Orientation — green
        case 5:  return Phase.register   // Word Registration — pink
        case 6:  return Phase.clock      // Clock Drawing — orange-red
        case 7:  return Phase.qdrs       // Verbal Fluency — sky blue
        case 8:  return Phase.story      // Story Recall — purple
        case 9:  return Phase.register   // Word Recall — matches Word Registration
        case 10: return Phase.results    // Completion — green
        default: return Phase.welcome
        }
    }

    /// Full-screen phase tint — the accent color at 6% opacity. The
    /// root canvas paints this edge-to-edge behind both panes and the
    /// WKWebView, animating on phase change so the room appears to
    /// gently shift lighting.
    static func tint(for phaseRawValue: Int) -> Color {
        accent(for: phaseRawValue).opacity(0.06)
    }

    // MARK: Progress Segment Weights

    /// Relative weight of each phase segment in the progress bar.
    /// 9 values corresponding to: welcome, orient, register, clock, fluency, story, recall, qdrs, results.
    static let progressWeights: [Int] = [1, 4, 1, 2, 1, 3, 3, 2, 1]

    // MARK: Animation Constants

    /// Alias for views that reference `Anim` instead of `Animation`
    typealias Anim = Animation

    enum Animation {
        /// Phase layout transition — spring tuned for elderly patients (slower, no bounce)
        static let phaseTransition = SwiftUI.Animation.spring(
            response: 0.65,
            dampingFraction: 0.88,
            blendDuration: 0
        )

        /// Phase content swap — crossfade + upward drift, purposeful not playful
        static let contentSwap = SwiftUI.Animation.easeInOut(duration: 0.35)

        /// Content fade in/out — 0.25 s ease-in-out
        static let contentFade = SwiftUI.Animation.easeInOut(duration: 0.25)

        /// Content enter — staggered fade + slide-up for phase elements
        static let contentEnter = SwiftUI.Animation.easeOut(duration: 0.4)

        /// Button press feedback — spring, 0.15 s
        static let buttonPress = SwiftUI.Animation.spring(
            response: 0.15,
            dampingFraction: 0.85,
            blendDuration: 0
        )

        /// Button success confirmation — scale pulse 1.0 → 1.03 → 1.0
        static let successPulse = SwiftUI.Animation.easeInOut(duration: 0.3)

        /// Word chip appear — spring, 0.35 s
        static let chipAppear = SwiftUI.Animation.spring(
            response: 0.35,
            dampingFraction: 0.8,
            blendDuration: 0
        )

        /// Ring / halo pulse period — 1.8 s, repeating
        static let ringPulseDuration: Double = 1.8
        static let ringPulse = SwiftUI.Animation.easeInOut(duration: ringPulseDuration)
            .repeatForever(autoreverses: true)

        /// Reduced-motion fallback — opacity only, no spatial movement
        static let reducedMotion = SwiftUI.Animation.easeInOut(duration: 0.2)
    }

    // MARK: Motion (design-engineer tokens, 2026-04-14)

    /// Narrative motion vocabulary for phase + content choreography.
    /// Each token names the *intent*, not the curve — use these so design
    /// decisions read consistently across the app.
    enum Motion {
        /// Content settling into place when a new phase enters. No bounce —
        /// conveys "arrived" without celebration. Elderly-patient friendly.
        static let phaseEnter = SwiftUI.Animation.smooth(duration: 0.55, extraBounce: 0.0)

        /// Content leaving cleanly — short ease-in so eyes stay on what's
        /// coming next, not on what's leaving.
        static let phaseExit = SwiftUI.Animation.easeIn(duration: 0.22)

        /// Smooth crossfade for color, opacity, and accent transitions.
        static let contentFade = SwiftUI.Animation.easeInOut(duration: 0.3)

        /// Snappy response for press / tap — immediate but not jittery.
        static let microFeedback = SwiftUI.Animation.spring(
            response: 0.22,
            dampingFraction: 0.78,
            blendDuration: 0
        )

        /// Slow, calm breathing used for avatar ring + glow. Long period
        /// (3.6s) so it reads as life-sign rather than pulse.
        static let avatarPulseDuration: Double = 3.6
        static let avatarPulse = SwiftUI.Animation.easeInOut(duration: avatarPulseDuration)
            .repeatForever(autoreverses: true)

        /// Bouncy spring for phase-completion checkmark — the one place in
        /// the assessment where a little playful confirmation is warranted.
        static let celebrationBounce = SwiftUI.Animation.spring(
            response: 0.42,
            dampingFraction: 0.55,
            blendDuration: 0
        )

        /// Snappy tight spring for counter increments — 1.0 → 1.15 → 1.0.
        /// Used by verbal fluency "N named" and countdown ring seconds.
        static let numberPop = SwiftUI.Animation.spring(
            response: 0.26,
            dampingFraction: 0.62,
            blendDuration: 0
        )
    }

    // MARK: Depth (shadow + glow tokens)

    enum Depth {
        /// Card at rest — subtle, soft shadow.
        static let cardResting = ShadowStyle(
            color: Color.black.opacity(0.06),
            radius: 10,
            x: 0,
            y: 4
        )

        /// Card raised / pressed — deeper, more confident shadow.
        static let cardRaised = ShadowStyle(
            color: Color.black.opacity(0.16),
            radius: 18,
            x: 0,
            y: 10
        )

        /// Phase-accent-colored glow used behind the avatar panel and for
        /// selected answer feedback.
        static func glowAccent(color: Color, intensity: Double = 0.45) -> ShadowStyle {
            ShadowStyle(
                color: color.opacity(intensity),
                radius: 26,
                x: 0,
                y: 0
            )
        }
    }

    /// Lightweight shadow descriptor — SwiftUI's `.shadow` takes raw args, so
    /// we store the parts and apply them via a View extension.
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - Shadow application

extension View {
    /// Apply a design-token shadow to a view.
    func assessmentShadow(_ shadow: AssessmentTheme.ShadowStyle) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - MotionSafe

/// Applies an animation unless accessibilityReduceMotion is on, in which
/// case it substitutes a short opacity crossfade. Every animated view in
/// the assessment UI should either use this modifier or gate on the
/// `@Environment(\.accessibilityReduceMotion)` flag directly.
struct MotionSafeModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? AssessmentTheme.Anim.reducedMotion : animation,
            value: value
        )
    }
}

extension View {
    /// Animate `value` changes with the given animation, but fall back to a
    /// simple opacity fade when the user has enabled Reduce Motion.
    func motionSafe<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionSafeModifier(animation: animation, value: value))
    }
}

// MARK: - Glass helper (iOS 26 Liquid Glass with iOS 17 fallback)

/// Applies a tinted glass surface:
/// - iOS 26+ uses `.glassEffect(.regular.tint(...).interactive(...), in: shape)`
/// - iOS 17 falls back to `.ultraThinMaterial` / `.regularMaterial`.
///
/// All iOS 26-specific APIs are gated with `#available(iOS 26, *)` per the
/// design brief. Non-interactive by default — pass `interactive: true` for
/// tappable controls.
struct AssessmentGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let prominence: Prominence
    let interactive: Bool

    enum Prominence { case thin, regular }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            glassBody(content)
        } else {
            fallbackBody(content)
        }
    }

    @available(iOS 26, *)
    @ViewBuilder private func glassBody(_ content: Content) -> some View {
        let base = Glass.regular
        let tinted = tint.map { base.tint($0.opacity(0.35)) } ?? base
        let final = interactive ? tinted.interactive() : tinted
        content.glassEffect(final, in: shape)
    }

    @ViewBuilder private func fallbackBody(_ content: Content) -> some View {
        let material: Material = (prominence == .thin) ? .ultraThinMaterial : .regularMaterial
        content
            .background(material, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 0.5))
            .overlay(tint.map { shape.fill($0.opacity(0.06)) })
    }
}

extension View {
    /// Apply a glass-style translucent surface. iOS 26 uses Liquid Glass;
    /// earlier versions fall back to SwiftUI Materials.
    func assessmentGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        prominence: AssessmentGlassBackground<S>.Prominence = .regular,
        interactive: Bool = false
    ) -> some View {
        modifier(AssessmentGlassBackground(shape: shape, tint: tint, prominence: prominence, interactive: interactive))
    }
}

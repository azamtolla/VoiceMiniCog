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
        /// Radial gradient center color: #1A1A2E
        static let gradientCenter = Color(hex: "#1A1A2E")
        /// Radial gradient edge color: #080808
        static let gradientEdge   = Color(hex: "#080808")

        /// Radial gradient filling the avatar panel.
        static let backgroundGradient = RadialGradient(
            colors: [gradientCenter, gradientEdge],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
    }

    // MARK: Split-Screen Gradient (avatar dark → content light)

    /// Unified horizontal gradient: #080808 on the right → #F8F9FA on the left.
    static let splitGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#080808"), location: 0.0),
            .init(color: Color(hex: "#F8F9FA"), location: 1.0)
        ],
        startPoint: .trailing,
        endPoint: .leading
    )

    // MARK: Phase Accent Colors

    /// Nine accent colors, one per assessment phase.
    enum Phase {
        static let welcome  = Color(hex: "#007AFF") // blue
        static let orient   = Color(hex: "#FF9F0A") // amber
        static let register = Color(hex: "#BF5AF2") // violet
        static let clock    = Color(hex: "#30D158") // emerald
        static let fluency  = Color(hex: "#FF375F") // pink
        static let story    = Color(hex: "#FF3B30") // red
        static let recall   = Color(hex: "#32ADE6") // cyan
        static let qdrs     = Color(hex: "#5E5CE6") // indigo
        static let results  = Color(hex: "#34C759") // green

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
        /// Welcome / intro phase: avatar is large
        static let welcome: CGFloat  = 0.65
        /// Orientation & registration Q&A phases
        static let qa: CGFloat       = 0.50
        /// Clock drawing & fluency (avatar steps back)
        static let clockFluency: CGFloat = 0.30
        /// Logical memory story delivery
        static let story: CGFloat    = 0.55
        /// Delayed recall
        static let recall: CGFloat   = 0.45
    }

    // MARK: Avatar Width Ratios by Phase ID

    /// Maps AssessmentPhaseID.rawValue → avatar width fraction.
    static let avatarWidthRatios: [Int: CGFloat] = [
        1: AvatarRatio.welcome,       // welcome
        2: AvatarRatio.qa,            // qdrs
        3: AvatarRatio.qa,            // phq2
        4: AvatarRatio.qa,            // orientation
        5: AvatarRatio.qa,            // wordRegistration
        6: AvatarRatio.clockFluency,  // clockDrawing
        7: AvatarRatio.clockFluency,  // verbalFluency
        8: AvatarRatio.story,         // storyRecall
        9: AvatarRatio.recall,        // wordRecall
    ]

    /// Phase accent color by AssessmentPhaseID.rawValue (1-based).
    static func accent(for phaseRawValue: Int) -> Color {
        let index = max(0, min(phaseRawValue - 1, Phase.all.count - 1))
        return Phase.all[index]
    }

    // MARK: Progress Segment Weights

    /// Relative weight of each phase segment in the progress bar.
    /// 9 values corresponding to: welcome, orient, register, clock, fluency, story, recall, qdrs, results.
    static let progressWeights: [Int] = [1, 4, 1, 2, 1, 3, 3, 2, 1]

    // MARK: Animation Constants

    /// Alias for views that reference `Anim` instead of `Animation`
    typealias Anim = Animation

    enum Animation {
        /// Phase transition — spring, 0.55 s, 0.15 bounce
        static let phaseTransition = SwiftUI.Animation.spring(
            response: 0.55,
            dampingFraction: 1.0 - 0.15,
            blendDuration: 0
        )

        /// Content fade in/out — 0.25 s ease-in-out
        static let contentFade = SwiftUI.Animation.easeInOut(duration: 0.25)

        /// Button press feedback — spring, 0.15 s
        static let buttonPress = SwiftUI.Animation.spring(
            response: 0.15,
            dampingFraction: 0.85,
            blendDuration: 0
        )

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
    }
}

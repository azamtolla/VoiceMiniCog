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
    enum PromptCopy {
        // Welcome
        static let welcomeTitle = "Brain Health Assessment"
        static let welcomeSubtitle = "6 cognitive activities, about 5-7 minutes"

        // Word Registration
        static let wordRegistrationTitle = "Listen carefully"
        static let wordRegistrationSubtitle = "The avatar will say 5 words.\nRepeat them back when asked."

        // Clock Drawing
        static let clockDrawingInstruction = "Draw a clock. Put in all the numbers.\nSet the hands to ten past eleven."

        // Story Recall
        static let storyListeningTitle = "Listen carefully to\nthis short story"
        static let storyListeningSubtitle = "The avatar is reading a story.\nPay close attention."
        static let storyRecallingTitle = "Now tell me everything\nyou remember"
        static let storyRecallingSubtitle = "Take your time. Say everything\nyou can recall."

        // Verbal Fluency
        static let verbalFluencyTitle = "Name as many animals\nas you can"
        static let verbalFluencySubtitle = "You have one minute."
        static let verbalFluencyStartNow = "Start now."

        // Word Recall
        static let wordRecallTitle = "What were the 5 words?"

        static func spoken(_ text: String) -> String {
            text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

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
        /// Animated gradient center: #121226
        static let gradientCenter = Color(hex: "#121226")
        /// Animated gradient edge: #080811
        static let gradientEdge   = Color(hex: "#080811")

        /// Radial gradient filling the avatar panel.
        static let backgroundGradient = RadialGradient(
            colors: [gradientCenter, gradientEdge],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )

        /// Glass material backdrop opacity for video container
        static let glassOpacity: Double = 0.03
        /// Accent ring stroke width (thin, premium)
        static let accentRingWidth: CGFloat = 0.75
        /// Status dot size
        static let statusDotSize: CGFloat = 8
        /// Waveform bar width
        static let waveBarWidth: CGFloat = 2.5
        /// Waveform bar count
        static let waveBarCount: Int = 7
        /// Video container corner radius
        static let videoCornerRadius: CGFloat = 16
        /// Video container inset from edges
        static let videoInset: CGFloat = 12
        /// Breathing animation scale amount
        static let breatheScale: CGFloat = 1.015
        /// Breathing animation duration
        static let breatheDuration: Double = 4.0
        /// Clinical badge background opacity
        static let badgeOpacity: Double = 0.35
    }

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

    // MARK: Phase Named Accents

    /// Named phase accent colors for direct use in views.
    enum Phase {
        static let welcome          = Color(hex: "#2563EB") // blue
        static let qdrs             = Color(hex: "#D97706") // amber
        static let phq2             = Color(hex: "#7C3AED") // violet
        static let orientation      = Color(hex: "#059669") // emerald
        static let wordRegistration = Color(hex: "#DB2777") // pink
        static let clock            = Color(hex: "#DC2626") // red
        static let verbalFluency    = Color(hex: "#0891B2") // cyan
        static let storyRecall      = Color(hex: "#4F46E5") // indigo
        static let wordRecall       = Color(hex: "#16A34A") // green
        static let results          = Color(hex: "#16A34A") // green (same as wordRecall / completion)
    }

    // MARK: Phase Accent Colors

    /// Accent color dictionary keyed by AssessmentPhaseID.rawValue (1-9).
    /// Order: welcome, qdrs, phq2, orientation, wordRegistration, clockDrawing, verbalFluency, storyRecall, wordRecall
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

    /// Look up accent color by phase number (1-9). Falls back to blue.
    static func accent(for phase: Int) -> Color {
        phaseAccents[phase] ?? Color(hex: "#2563EB")
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

    enum Fonts {
        /// Phase label above question — 11pt, rounded, all-caps weight
        static let phaseLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
        /// Main question text — 19pt semibold
        static let question   = Font.system(size: 19, weight: .semibold, design: .default)
        /// Helper / instruction text — 14pt regular
        static let helper     = Font.system(size: 14, weight: .regular, design: .default)
        /// Answer button label — 16pt medium
        static let buttonLabel = Font.system(size: 16, weight: .medium, design: .default)

        // Timers & counters (monospaced for stable width)
        /// Small timer — 13pt monospaced
        static let timerSmall     = Font.system(size: 13, weight: .regular, design: .monospaced)
        /// Large timer — 32pt monospaced bold
        static let timerLarge     = Font.system(size: 32, weight: .bold, design: .monospaced)
        /// Large counter hero (e.g., fluency word count) — 48pt monospaced bold
        static let counterHero    = Font.system(size: 48, weight: .bold, design: .monospaced)
        /// Score display — 28pt monospaced bold
        static let scoreDisplay   = Font.system(size: 28, weight: .bold, design: .monospaced)
        /// Avatar state label — 11pt medium
        static let avatarLabel    = Font.system(size: 11, weight: .medium)
    }

    // MARK: Sizing

    enum Sizing {
        /// Minimum tappable height for answer buttons: 56 pt
        static let buttonMinHeight: CGFloat = 56
        /// Progress track thickness: 4 pt
        static let progressTrack: CGFloat = 4
        static let progressTrackHeight: CGFloat = 4
        /// Ring / indicator line width: 2 pt
        static let ring: CGFloat = 2
        /// Pause button height: 44 pt
        static let pauseButtonHeight: CGFloat = 44
        /// Pause button width: 120 pt
        static let pauseButtonWidth: CGFloat = 120
        /// Avatar ring stroke width: 2 pt
        static let avatarRingWidth: CGFloat = 2
        /// Standard horizontal padding for content panel: 16 pt
        static let contentPadding: CGFloat = 16
    }

    // MARK: Avatar Width Ratios (fraction of total screen width)

    /// Avatar width ratio keyed by AssessmentPhaseID.rawValue (1-9).
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

    // MARK: Progress Segment Weights

    /// Relative weight of each phase segment in the progress bar.
    /// 9 values corresponding to: welcome, orient, register, clock, fluency, story, recall, qdrs, results.
    static let progressWeights: [Int] = [1, 4, 1, 2, 1, 3, 3, 2, 1]

    // MARK: Animation Constants

    enum Anim {
        /// Phase transition — spring, 0.55 s, 0.15 bounce
        static let phaseTransition = SwiftUI.Animation.spring(
            response: 0.55,
            dampingFraction: 1.0 - 0.15,
            blendDuration: 0
        )

        /// Content enter — spring, 0.4 s, fade + slide-up entrance
        static let contentEnter = SwiftUI.Animation.spring(
            response: 0.4,
            dampingFraction: 0.85,
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

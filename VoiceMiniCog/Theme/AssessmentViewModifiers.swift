//
//  AssessmentViewModifiers.swift
//  VoiceMiniCog
//
//  Reusable view modifiers and button styles for the assessment UI.
//  Created to support Cursor-authored phase views.
//

import SwiftUI

// MARK: - Content Enter Modifier

/// Fade + slide-up entrance animation for assessment content elements.
/// Usage: .assessmentContentEnter(isVisible: contentVisible, yOffset: 14)
struct AssessmentContentEnterModifier: ViewModifier {
    let isVisible: Bool
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : yOffset)
    }
}

extension View {
    func assessmentContentEnter(isVisible: Bool, yOffset: CGFloat = 12) -> some View {
        modifier(AssessmentContentEnterModifier(isVisible: isVisible, yOffset: yOffset))
    }
}

// MARK: - Icon Header Accent Modifier

/// Subtle glow/accent effect for phase header icons.
struct AssessmentIconHeaderAccentModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: accentColor.opacity(0.2), radius: 8, y: 2)
    }
}

extension View {
    func assessmentIconHeaderAccent(_ color: Color) -> some View {
        modifier(AssessmentIconHeaderAccentModifier(accentColor: color))
    }
}

// MARK: - Assessment Primary Button Style

/// Button style with scale-on-press feedback for assessment action buttons.
struct AssessmentPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// MARK: - PhaseTransitionContainer

/// Wraps phase content with a coordinated enter / exit choreography that
/// reads as one motion rather than a hard swap. Paired with the layout
/// reflow in AvatarAssessmentCanvas so the avatar width change, content
/// swap, and accent color crossfade move together.
///
/// Enter: slide up ~32pt + fade in, scoped by the phase id.
/// Exit: short fade + scale down to 0.985 so the prior phase recedes.
///
/// When Reduce Motion is on, both paths degrade to a pure opacity fade.
struct PhaseTransitionContainer<Phase: Hashable, Content: View>: View {
    let phase: Phase
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // No accent wash — the canvas is a single warm neutral everywhere.
        // Content still animates enter / exit per phase.
        content()
            .transition(phaseTransition)
            .id(phase)
            .animation(
                reduceMotion ? AssessmentTheme.Anim.reducedMotion : AssessmentTheme.Motion.phaseEnter,
                value: phase
            )
    }

    private var phaseTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 32)),
            removal: .opacity.combined(with: .scale(scale: 0.985))
        )
    }
}

// MARK: - Tappable card press modifier

/// Press-down behavior for tappable content cards / buttons:
/// resting → `cardResting` shadow, pressed → scale 0.97 + `cardRaised`
/// shadow + accent-colored glow, release → spring back on `microFeedback`.
///
/// Use on tappable cells that aren't already wrapped in a `Button` with
/// a ButtonStyle — e.g., custom answer tiles.
struct AssessmentTappableCardModifier: ViewModifier {
    let accentColor: Color
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
            .assessmentShadow(isPressed ? AssessmentTheme.Depth.cardRaised : AssessmentTheme.Depth.cardResting)
            .assessmentShadow(isPressed
                ? AssessmentTheme.Depth.glowAccent(color: accentColor, intensity: 0.35)
                : AssessmentTheme.Depth.glowAccent(color: accentColor, intensity: 0.0))
            .animation(AssessmentTheme.Motion.microFeedback, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    /// Apply press-scale + raised-shadow + accent-glow feedback.
    func assessmentTappableCard(accent: Color) -> some View {
        modifier(AssessmentTappableCardModifier(accentColor: accent))
    }
}

// MARK: - Phase Completion Checkmark

/// A centered SF Symbol checkmark that celebrationBounces in, holds briefly,
/// then fades — gives each phase a satisfying close before the next starts.
/// Drive with a `trigger` that changes from nil → phase-id when the phase
/// completes.
struct PhaseCompletionCheckmark: View {
    let accentColor: Color
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0.0

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(accentColor)
            .symbolRenderingMode(.hierarchical)
            .scaleEffect(scale)
            .opacity(opacity)
            .assessmentShadow(AssessmentTheme.Depth.glowAccent(color: accentColor, intensity: 0.6))
            .onChange(of: isVisible) { _, visible in
                if visible { play() } else { reset() }
            }
            .onAppear { if isVisible { play() } }
            .accessibilityLabel("Phase complete")
    }

    private func play() {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) {
                scale = 1.0
                opacity = 1.0
            }
            return
        }
        withAnimation(AssessmentTheme.Motion.celebrationBounce) {
            scale = 1.0
            opacity = 1.0
        }
        // Fade after a short hold — uses withAnimation.delay, NOT
        // DispatchQueue, per the swiftui-animation skill guidance.
        withAnimation(AssessmentTheme.Motion.contentFade.delay(0.9)) {
            opacity = 0.0
        }
    }

    private func reset() {
        scale = 0.3
        opacity = 0.0
    }
}

// MARK: - Thinking Dots

/// Four small dots with a staggered-wave animation used while the avatar
/// is in `.acknowledging` (thinking) state. Tinted with the current phase
/// accent so it integrates with the rest of the UI.
struct ThinkingDots: View {
    let color: Color
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            HStack(spacing: 6) {
                ForEach(0..<4) { _ in
                    Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6)
                }
            }
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isActive)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = t * 2.0 - Double(i) * 0.22
                        let wave = sin(phase) // -1...1
                        let lift = CGFloat(max(0, wave)) * 8.0
                        let alpha = 0.35 + max(0, wave) * 0.65
                        Circle()
                            .fill(color.opacity(alpha))
                            .frame(width: 7, height: 7)
                            .offset(y: -lift)
                    }
                }
            }
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
    }
}

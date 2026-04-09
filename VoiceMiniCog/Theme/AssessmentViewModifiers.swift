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

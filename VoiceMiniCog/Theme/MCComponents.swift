//
//  MCComponents.swift
//  VoiceMiniCog
//
//  Reusable UI components for the MCDesign system.
//  Every patient-facing button is 60pt+, every touch target 60pt+.
//

import SwiftUI

// MARK: - Primary Button

/// Full-width filled button. 60pt height, 22pt semibold label, shadow, press feedback.
struct MCPrimaryButton: View {
    let title: String // swiftlint:disable:this redundant_string_enum_value

    init(_ title: String, icon: String? = nil, color: Color = MCDesign.Colors.primary700,
         height: CGFloat = MCDesign.Sizing.primaryButtonHeight, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.height = height
        self.action = action
    }
    var icon: String? = nil
    var color: Color = MCDesign.Colors.primary700
    var height: CGFloat = MCDesign.Sizing.primaryButtonHeight
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                }
                Text(title)
                    .font(MCDesign.Fonts.buttonLabel)
            }
            .foregroundColor(MCDesign.Colors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(color)
            .cornerRadius(MCDesign.Radius.medium)
            .mcShadow(isPressed ? MCDesign.Shadow.pressed : MCDesign.Shadow.button)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(MCDesign.Anim.quick) { isPressed = true } }
                .onEnded { _ in withAnimation(MCDesign.Anim.quick) { isPressed = false } }
        )
    }
}

// MARK: - Secondary Button

/// Full-width outline button. 52pt height, primary border, no fill.
struct MCSecondaryButton: View {
    let title: String

    init(_ title: String, icon: String? = nil, color: Color = MCDesign.Colors.primary700,
         height: CGFloat = MCDesign.Sizing.secondaryButtonHeight, width: CGFloat? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.height = height
        self.width = width
        self.action = action
    }
    var icon: String? = nil
    var color: Color = MCDesign.Colors.primary700
    var height: CGFloat = MCDesign.Sizing.secondaryButtonHeight
    var width: CGFloat? = nil
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                }
                Text(title)
                    .font(MCDesign.Fonts.bodySemibold)
            }
            .foregroundColor(color)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .background(MCDesign.Colors.surface)
            .cornerRadius(MCDesign.Radius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: MCDesign.Radius.medium)
                    .stroke(isPressed ? color.opacity(0.5) : MCDesign.Colors.border, lineWidth: 1.5)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(MCDesign.Anim.quick) { isPressed = true } }
                .onEnded { _ in withAnimation(MCDesign.Anim.quick) { isPressed = false } }
        )
    }
}

// MARK: - Card

/// White surface card with shadow and optional accent strip + header.
struct MCCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var accentColor: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MCDesign.Spacing.md) {
            if let title {
                HStack(spacing: MCDesign.Spacing.sm) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundColor(accentColor ?? MCDesign.Colors.primary500)
                    }
                    Text(title)
                        .font(MCDesign.Fonts.reportHeading)
                        .foregroundColor(MCDesign.Colors.textPrimary)
                }
            }
            content()
        }
        .padding(MCDesign.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MCDesign.Colors.surface)
        .cornerRadius(MCDesign.Radius.large)
        .overlay(
            Group {
                if let accent = accentColor {
                    HStack {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 5)
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MCDesign.Radius.large))
        )
        .mcShadow(MCDesign.Shadow.card)
    }
}

// MARK: - Progress Bar

/// Thin animated progress bar. No timer, no anxiety-inducing colors.
struct MCProgressBar: View {
    let progress: Double     // 0.0 – 1.0
    var label: String? = nil
    var color: Color = MCDesign.Colors.primary500
    var height: CGFloat = MCDesign.Sizing.progressBarHeight

    var body: some View {
        VStack(alignment: .leading, spacing: MCDesign.Spacing.xs) {
            if let label {
                Text(label)
                    .font(MCDesign.Fonts.smallCaption)
                    .foregroundColor(MCDesign.Colors.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(MCDesign.Colors.primary100)
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(color)
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                        .animation(MCDesign.Anim.standard, value: progress)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Risk Badge

/// Large pill showing risk level with icon + text. Always colorblind-accessible.
struct MCRiskBadge: View {
    enum Level { case low, moderate, high }

    let level: Level
    var label: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .bold))
            Text(label ?? defaultLabel)
                .font(MCDesign.Fonts.bodySemibold)
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, MCDesign.Spacing.lg)
        .padding(.vertical, MCDesign.Spacing.md)
        .background(badgeColor.opacity(0.12))
        .cornerRadius(MCDesign.Radius.medium)
    }

    private var badgeColor: Color {
        switch level {
        case .low: return MCDesign.Colors.riskLow
        case .moderate: return MCDesign.Colors.riskMod
        case .high: return MCDesign.Colors.riskHigh
        }
    }

    private var iconName: String {
        switch level {
        case .low: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .high: return "xmark.circle.fill"
        }
    }

    private var defaultLabel: String {
        switch level {
        case .low: return "Low Risk"
        case .moderate: return "Moderate Risk"
        case .high: return "High Risk"
        }
    }
}

// MARK: - Listening Indicator

/// Large pulsing green circle with "Listening..." label.
struct MCListeningIndicator: View {
    var isActive: Bool = true

    @State private var pulse = false

    var body: some View {
        VStack(spacing: MCDesign.Spacing.md) {
            ZStack {
                Circle()
                    .fill(MCDesign.Colors.success.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                        value: pulse
                    )

                Circle()
                    .fill(MCDesign.Colors.success.opacity(0.3))
                    .frame(width: 60, height: 60)

                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundColor(MCDesign.Colors.success)
            }

            Text("Listening...")
                .font(MCDesign.Fonts.body)
                .foregroundColor(MCDesign.Colors.success)
        }
        .onAppear { pulse = isActive }
        .onChange(of: isActive) { _, active in pulse = active }
    }
}

// MARK: - Icon Circle

/// Circular background with centered SF Symbol. Neo-skeuomorphic subtle gradient.
struct MCIconCircle: View {
    let icon: String
    var color: Color = MCDesign.Colors.primary500
    var size: CGFloat = MCDesign.Sizing.iconMedium

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.12), color.opacity(0.06)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.4))
                .foregroundColor(color)
        }
    }
}

// MARK: - Phase Header Badge

/// Capsule badge shown at the top-left of each assessment phase's content panel.
/// Displays the phase name in all-caps with a tinted SF Symbol icon.
struct PhaseHeaderBadge: View {
    let phaseName: String
    let icon: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(phaseName.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)
                .tracking(1.0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(accentColor.opacity(0.10)))
        .overlay(Capsule().stroke(accentColor.opacity(0.20), lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: phaseName)
    }
}

// MARK: - State Chip

/// Small pill showing assistant state (Speaking/Listening/Thinking).
struct MCStateChip: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(MCDesign.Fonts.smallCaption)
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(MCDesign.Radius.pill)
    }
}

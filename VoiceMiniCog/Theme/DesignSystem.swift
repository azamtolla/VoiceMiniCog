//
//  DesignSystem.swift
//  VoiceMiniCog
//
//  MCDesign: Neo-skeuomorphic, accessibility-first design system.
//

import SwiftUI

enum MCDesign {
    enum Colors {
        static let primary900 = Color(hex: "#0e2b3d")
        static let primary700 = Color(hex: "#1a5276")
        static let primary500 = Color(hex: "#2980b9")
        static let primary300 = Color(hex: "#85c1e9")
        static let primary100 = Color(hex: "#d6eaf8")
        static let primary50  = Color(hex: "#ebf5fb")
        static let background   = Color(hex: "#F1F5F9")
        static let surface      = Color.white
        static let surfaceInset = Color(hex: "#F8FAFC")
        static let textPrimary   = Color(hex: "#1E293B")
        static let textSecondary = Color(hex: "#475569")
        static let textTertiary  = Color(hex: "#94A3B8")
        static let textOnPrimary = Color.white
        static let success       = Color(hex: "#059669")
        static let successSurface = Color(hex: "#D1FAE5")
        static let warning       = Color(hex: "#D97706")
        static let warningSurface = Color(hex: "#FEF3C7")
        static let error         = Color(hex: "#DC2626")
        static let errorSurface  = Color(hex: "#FEE2E2")
        static let info          = Color(hex: "#0284C7")
        static let infoSurface   = Color(hex: "#E0F2FE")
        static let riskLow  = Color(hex: "#2980b9")
        static let riskMod  = Color(hex: "#F39C12")
        static let riskHigh = Color(hex: "#D35400")
        static let border       = Color(hex: "#E2E8F0")
        static let borderFocused = primary500
        static let divider      = Color(hex: "#EAECEE")
        static let qdrsAccent   = Color(hex: "#EA580C")
        static let phq2Accent   = Color(hex: "#7C3AED")
        static let storyAccent  = Color(hex: "#6366F1")
        static let clockAccent  = Color(hex: "#0891B2")
    }

    enum Fonts {
        static let heroTitle    = Font.system(size: 34, weight: .bold)
        static let screenTitle  = Font.system(size: 28, weight: .bold)
        static let sectionTitle = Font.system(size: 24, weight: .semibold)
        static let body         = Font.system(size: 20, weight: .regular)
        static let bodyMedium   = Font.system(size: 20, weight: .medium)
        static let bodySemibold = Font.system(size: 20, weight: .semibold)
        static let buttonLabel  = Font.system(size: 22, weight: .semibold)
        static let caption      = Font.system(size: 18, weight: .regular)
        static let smallCaption = Font.system(size: 16, weight: .regular)
        static let reportTitle   = Font.system(size: 22, weight: .bold)
        static let reportHeading = Font.system(size: 18, weight: .semibold)
        static let reportBody    = Font.system(size: 15, weight: .regular)
        static let reportCaption = Font.system(size: 13, weight: .regular)
        static let reportData    = Font.system(size: 15, weight: .medium, design: .monospaced)
        static let scoreDisplay  = Font.system(size: 48, weight: .bold)
        static let scoreMedium   = Font.system(size: 32, weight: .bold)
    }

    enum Sizing {
        static let primaryButtonHeight: CGFloat = 60
        static let secondaryButtonHeight: CGFloat = 52
        static let touchTargetMin: CGFloat = 60
        static let avatarHeight: CGFloat = 300
        static let progressBarHeight: CGFloat = 6
        static let iconSmall: CGFloat = 36
        static let iconMedium: CGFloat = 56
        static let iconLarge: CGFloat = 80
        static let iconXL: CGFloat = 100
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let patientPadding: CGFloat = 24
        static let patientGap: CGFloat = 20
        static let providerPadding: CGFloat = 16
        static let providerGap: CGFloat = 12
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 9999
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        static let card     = ShadowStyle(color: .black.opacity(0.06), radius: 6, y: 3)
        static let button   = ShadowStyle(color: .black.opacity(0.08), radius: 6, y: 3)
        static let elevated = ShadowStyle(color: .black.opacity(0.12), radius: 12, y: 4)
        static let header   = ShadowStyle(color: .black.opacity(0.03), radius: 2, y: 1)
        static let pressed  = ShadowStyle(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    enum Anim {
        static let quick    = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let gentle   = SwiftUI.Animation.easeInOut(duration: 0.4)
    }
}

extension View {
    func mcShadow(_ style: MCDesign.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}

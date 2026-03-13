//
//  MercyColors.swift
//  VoiceMiniCog
//
//  Mercy Health brand colors matching the React app exactly
//

import SwiftUI

struct MercyColors {
    // Primary brand color - Mercy Blue
    static let mercyBlue = Color(hex: "#005EB8")
    static let mercyBlueDark = Color(hex: "#004A91")
    static let mercyBlueLight = Color(hex: "#1976D2")

    // Secondary brand color - Mercy Green
    static let mercyGreen = Color(hex: "#0F9B49")
    static let mercyGreenDark = Color(hex: "#0B7A3A")
    static let mercyGreenLight = Color(hex: "#27AD5F")

    // Gray scale (matching React exactly)
    static let gray50 = Color(hex: "#F8FAFC")
    static let gray100 = Color(hex: "#F1F5F9")
    static let gray200 = Color(hex: "#E2E8F0")
    static let gray300 = Color(hex: "#CBD5E1")
    static let gray400 = Color(hex: "#94A3B8")
    static let gray500 = Color(hex: "#64748B")
    static let gray600 = Color(hex: "#475569")
    static let gray700 = Color(hex: "#334155")
    static let gray800 = Color(hex: "#1E293B")
    static let gray900 = Color(hex: "#0F172A")

    // Semantic colors
    static let success = Color(hex: "#059669")
    static let successLight = Color(hex: "#D1FAE5")
    static let warning = Color(hex: "#D97706")
    static let warningLight = Color(hex: "#FEF3C7")
    static let error = Color(hex: "#DC2626")
    static let errorLight = Color(hex: "#FEE2E2")
    static let info = Color(hex: "#0284C7")
    static let infoLight = Color(hex: "#E0F2FE")

    // Phase colors (matching React PHASE_META)
    static let phaseGreeting = Color(hex: "#1a5276")
    static let phaseRegistration = Color(hex: "#7c3aed")
    static let phaseClock = Color(hex: "#0891b2")
    static let phaseRecall = Color(hex: "#c026d3")
    static let phaseAD8 = Color(hex: "#ea580c")
    static let phaseResults = Color(hex: "#16a34a")

    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [mercyBlue, mercyBlueDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

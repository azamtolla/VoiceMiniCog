//
//  CompositeRisk.swift
//  VoiceMiniCog
//
//  Composite cognitive risk calculation matching React implementation
//

import Foundation

enum RiskTier: String, Codable {
    case low
    case intermediate
    case high
}

struct CompositeRiskOutput: Codable {
    let tier: RiskTier
    let label: String
    let summaryLine: String
    let narrative: String
    let suggestedActions: [String]
}

struct MiniCogInput {
    let totalScore: Int
    let recallScore: Int
    let clockScore: Int
    let aiClockExecutiveFlag: Bool
}

struct AD8Input {
    let totalScore: Int
    let respondentType: AD8RespondentType
    let flaggedDomains: [String]
    let uncertainCount: Int
}

func computeCompositeRisk(miniCog: MiniCogInput, ad8: AD8Input) -> CompositeRiskOutput {
    let mcPositive = miniCog.totalScore < 3
    let ad8Positive = ad8.totalScore >= 2

    // Concordance check
    let concordant = (mcPositive && ad8Positive) || (!mcPositive && !ad8Positive)

    var tier: RiskTier
    var label: String
    var summaryLine: String
    var narrative: String
    var suggestedActions: [String] = []

    if mcPositive && ad8Positive {
        // Both positive - High risk
        tier = .high
        label = "High Risk"
        summaryLine = "Both Mini-Cog and AD8 screen positive"
        narrative = "Concordant positive findings on both screening instruments indicate elevated likelihood of cognitive impairment. Further diagnostic evaluation is strongly recommended."
        suggestedActions = [
            "Consider formal cognitive assessment (MoCA, SLUMS)",
            "Order reversible dementia workup (TSH, B12, CBC, CMP)",
            "Consider structural neuroimaging",
            "Refer to neurology or memory clinic"
        ]
    } else if !mcPositive && !ad8Positive {
        // Both negative - Low risk
        tier = .low
        label = "Low Risk"
        summaryLine = "Both Mini-Cog and AD8 screen negative"
        narrative = "Concordant negative findings suggest low likelihood of significant cognitive impairment at this time. Routine monitoring recommended."
        suggestedActions = [
            "Continue routine cognitive monitoring",
            "Repeat screening in 12 months if risk factors present"
        ]
    } else {
        // Discordant results - Intermediate risk
        tier = .intermediate
        label = "Intermediate Risk"

        if mcPositive && !ad8Positive {
            summaryLine = "Mini-Cog positive but AD8 negative (discordant)"
            narrative = "Discordant findings with objective screening positive but subjective report negative. This may reflect early impairment with limited awareness, or performance factors affecting the Mini-Cog."
        } else {
            summaryLine = "AD8 positive but Mini-Cog negative (discordant)"
            narrative = "Discordant findings with subjective concerns but objective screening negative. This may reflect subjective cognitive decline, anxiety, depression, or very early changes not yet captured by brief screening."
        }

        suggestedActions = [
            "Consider formal cognitive assessment for clarification",
            "Evaluate for depression, anxiety, sleep disorders",
            "Review medications that may affect cognition",
            "Repeat screening in 6 months"
        ]

        // Adjust for self-report AD8 with borderline score
        if ad8.respondentType == .selfReport && ad8.totalScore >= 2 && ad8.totalScore <= 3 {
            narrative += " Note: Self-report AD8 scores of 2-3 have lower specificity; consider informant corroboration."
        }
    }

    // Add executive flag note if applicable
    if miniCog.aiClockExecutiveFlag {
        narrative += " AI clock analysis suggests possible executive dysfunction despite normal Mini-Cog score."
        if tier == .low {
            tier = .intermediate
            label = "Low-Intermediate Risk"
            suggestedActions.append("Monitor executive function given AI clock findings")
        }
    }

    // Add domain-specific observations
    if !ad8.flaggedDomains.isEmpty && ad8.flaggedDomains.count >= 3 {
        narrative += " Multiple functional domains affected: \(ad8.flaggedDomains.joined(separator: ", "))."
    }

    return CompositeRiskOutput(
        tier: tier,
        label: label,
        summaryLine: summaryLine,
        narrative: narrative,
        suggestedActions: suggestedActions
    )
}

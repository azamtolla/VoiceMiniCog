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

// AD8 removed — use computeCompositeRiskQmciQDRS instead

func computeCompositeRiskMiniCogQDRS(
    miniCog: MiniCogInput,
    qdrs: QDRSInput
) -> CompositeRiskOutput {
    let mcPositive = miniCog.totalScore < 3
    let qPositive = qdrs.isPositiveScreen

    var tier: RiskTier
    var label: String
    var summary: String
    var narrative: String
    var actions: [String] = []

    switch (mcPositive, qPositive) {
    case (true, true):
        tier = .high
        label = "High Risk"
        summary = "Both Mini-Cog and QDRS screen positive"
        narrative = "Concordant positive findings on objective and patient-reported measures suggest elevated likelihood of cognitive impairment."
        actions = [
            "Formal cognitive assessment (MoCA, SLUMS)",
            "Reversible dementia workup (TSH, B12, CBC, CMP)",
            "Consider structural neuroimaging",
            "Refer to neurology or memory clinic"
        ]

    case (false, false):
        tier = .low
        label = "Low Risk"
        summary = "Both Mini-Cog and QDRS screen negative"
        narrative = "Concordant negative findings suggest low likelihood of significant cognitive impairment at this time."
        actions = [
            "Continue routine cognitive monitoring",
            "Repeat screening in 12 months if risk factors present"
        ]

    case (true, false):
        tier = .intermediate
        label = "Intermediate Risk"
        summary = "Mini-Cog positive, QDRS negative (discordant)"
        narrative = "Objective screening positive without patient-reported functional concerns. May reflect limited insight or early impairment. Further evaluation recommended."
        actions = [
            "Consider formal cognitive assessment",
            "Seek informant history",
            "Review medications and comorbidities"
        ]

    case (false, true):
        tier = .intermediate
        label = "Intermediate Risk"
        summary = "QDRS positive, Mini-Cog negative (discordant)"
        narrative = "Patient reports functional/memory concerns without objective impairment. May reflect subjective cognitive decline, anxiety, or depression."
        actions = [
            "Screen for depression, anxiety, sleep disorder",
            "Repeat screening in 6–12 months",
            "Consider formal cognitive testing if concerns persist"
        ]
    }

    if miniCog.aiClockExecutiveFlag {
        narrative += " AI clock analysis suggests possible executive dysfunction despite Mini-Cog score."
        if tier == .low {
            tier = .intermediate
            label = "Low-Intermediate Risk"
            actions.append("Monitor executive function given AI clock findings")
        }
    }

    return CompositeRiskOutput(
        tier: tier,
        label: label,
        summaryLine: summary,
        narrative: narrative,
        suggestedActions: actions
    )
}

// MARK: - Qmci + QDRS Composite Risk

func computeCompositeRiskQmciQDRS(
    qmciState: QmciState,
    qdrsState: QDRSState,
    phq2Score: Int,
    clockAnalysis: ClockAnalysisResponse?
) -> CompositeRiskOutput {
    let qPositive = qmciState.classification.isPositive
    let qdrsPositive = qdrsState.isPositiveScreen

    var tier: RiskTier
    var label: String
    var summary: String
    var narrative: String
    var actions: [String] = []

    switch (qPositive, qdrsPositive) {
    case (true, true):
        tier = .high
        label = "High Risk — Concordant Positive"
        summary = "Qmci \(qmciState.totalScore)/100 and QDRS \(String(format: "%.1f", qdrsState.totalScore)) both positive"
        narrative = "Concordant positive findings on objective testing and patient-reported measures. Consistent with MCI or early dementia."
        actions = [
            "Order reversible cause workup (TSH, B12, CBC, CMP)",
            "Order brain MRI",
            "Consider plasma p-tau217 for amyloid pathology",
            "Refer to neurology or memory clinic",
        ]
    case (false, false):
        tier = .low
        label = "Low Risk — Concordant Negative"
        summary = "Qmci \(qmciState.totalScore)/100 and QDRS \(String(format: "%.1f", qdrsState.totalScore)) both negative"
        narrative = "Concordant negative findings suggest low likelihood of significant cognitive impairment."
        actions = ["Continue routine monitoring", "Repeat screening at next AWV"]
    case (true, false):
        tier = .intermediate
        label = "Intermediate — Qmci+/QDRS-"
        summary = "Qmci positive but patient reports no functional decline"
        narrative = "Objective impairment without reported functional difficulty. May indicate early MCI with limited self-awareness."
        actions = ["Consider neuropsychological testing", "Obtain informant history", "Order reversible cause workup"]
    case (false, true):
        tier = .intermediate
        label = "Intermediate — Qmci-/QDRS+"
        summary = "Qmci negative but patient reports functional concerns"
        narrative = "Subjective concerns without objective impairment. May reflect depression, anxiety, or very early changes."
        actions = ["Screen for depression (PHQ-9)", "Evaluate anxiety/sleep", "Review medications"]
    }

    if phq2Score >= 3 {
        narrative += " PHQ-2 positive (\(phq2Score)/6) — depression may contribute."
        if !actions.contains(where: { $0.contains("depression") }) {
            actions.insert("Evaluate and treat depression before attributing to neurodegeneration", at: 0)
        }
    }

    if let clock = clockAnalysis, clock.aiClass < 2, tier == .low {
        tier = .intermediate
        label = "Low-Intermediate Risk"
        actions.append("Monitor executive function given AI clock findings")
    }

    return CompositeRiskOutput(tier: tier, label: label, summaryLine: summary,
                                narrative: narrative, suggestedActions: actions)
}

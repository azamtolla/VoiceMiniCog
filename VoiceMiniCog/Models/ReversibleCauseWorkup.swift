//
//  ReversibleCauseWorkup.swift
//  VoiceMiniCog
//

import Foundation

struct ReversibleCauseOrder: Identifiable {
    let id = UUID()
    let name: String
    let code: String
    let rationale: String
    let priority: OrderPriority
    var isSelected: Bool = true
}

enum OrderPriority { case required, recommended, optional }

func generateWorkupOrders(qmciClassification: QmciClassification, phq2Score: Int, isFirstEvaluation: Bool) -> [ReversibleCauseOrder] {
    var orders: [ReversibleCauseOrder] = []
    if qmciClassification.isPositive {
        orders.append(contentsOf: [
            ReversibleCauseOrder(name: "TSH", code: "84443", rationale: "Rule out hypothyroidism", priority: .required),
            ReversibleCauseOrder(name: "Vitamin B12", code: "82607", rationale: "Rule out B12 deficiency", priority: .required),
            ReversibleCauseOrder(name: "CBC with differential", code: "85025", rationale: "Baseline", priority: .required),
            ReversibleCauseOrder(name: "CMP", code: "80053", rationale: "Electrolytes, renal/hepatic function", priority: .required),
            ReversibleCauseOrder(name: "Brain MRI without contrast", code: "70553", rationale: "Structural evaluation; baseline for anti-amyloid", priority: .recommended),
        ])
    }
    if phq2Score >= 3 {
        orders.append(ReversibleCauseOrder(name: "PHQ-9", code: "96127", rationale: "PHQ-2 positive (\(phq2Score)/6)", priority: .required))
    }
    if qmciClassification == .mciProbable {
        orders.append(contentsOf: [
            ReversibleCauseOrder(name: "Plasma p-tau217/AB42 ratio", code: "LOINC 96923-0", rationale: "Amyloid confirmation", priority: .recommended),
            ReversibleCauseOrder(name: "ApoE genotyping", code: "81401", rationale: "ARIA risk stratification", priority: .recommended),
        ])
    }
    return orders
}

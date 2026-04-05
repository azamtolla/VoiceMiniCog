//
//  AntiAmyloidTriage.swift
//  VoiceMiniCog
//
//  Eligibility logic for lecanemab/donanemab anti-amyloid therapy.
//

import Foundation

enum AmyloidEligibility: String {
    case candidate = "Candidate for Amyloid Workup"
    case notEligible = "Not Currently Eligible"
    case needsFurtherEval = "Needs Further Evaluation"
    case tooImpaired = "Below Treatment Window"
}

struct AmyloidTriageResult {
    let eligibility: AmyloidEligibility
    let cdrScore: Double
    let qmciScore: Int
    let qmciClassification: QmciClassification
    let checklist: [AmyloidChecklistItem]
    let narrative: String
    let nextSteps: [String]
}

struct AmyloidChecklistItem: Identifiable {
    let id = UUID()
    let label: String
    let status: ChecklistStatus
    let detail: String
}

enum ChecklistStatus { case met, notMet, needsReview, notAssessed }

struct MedicationFlags: Codable {
    var onAnticoagulant: Bool = false
    var anticoagulantAssessed: Bool = false
    var onAnticholinergic: Bool = false
    var onBenzodiazepine: Bool = false
    var onOpioid: Bool = false
    var medicationsReviewed: Bool = false
}

func computeAmyloidTriage(qmciState: QmciState, qdrsState: QDRSState, medications: MedicationFlags) -> AmyloidTriageResult {
    let cdrEquivalent = qdrsState.totalScore
    let qmciTotal = qmciState.totalScore
    let classification = qmciState.classification
    var checklist: [AmyloidChecklistItem] = []
    var eligible = true

    let cdrInRange = cdrEquivalent >= 0.5 && cdrEquivalent <= 1.0
    checklist.append(AmyloidChecklistItem(label: "CDR-equivalent 0.5 or 1.0", status: cdrInRange ? .met : .notMet, detail: "QDRS score \(String(format: "%.1f", cdrEquivalent))"))
    if !cdrInRange { eligible = false }

    let qmciInRange = qmciTotal < 67 && qmciTotal >= 36
    checklist.append(AmyloidChecklistItem(label: "Cognitive score in treatment window", status: qmciInRange ? .met : .notMet, detail: "Qmci \(qmciTotal)/100 (\(classification.rawValue))"))
    if !qmciInRange { eligible = false }

    checklist.append(AmyloidChecklistItem(label: "No therapeutic anticoagulation", status: medications.onAnticoagulant ? .notMet : (medications.anticoagulantAssessed ? .met : .notAssessed), detail: medications.onAnticoagulant ? "Patient on anticoagulant — ARIA risk" : "No anticoagulant identified"))
    if medications.onAnticoagulant { eligible = false }

    checklist.append(AmyloidChecklistItem(label: "Amyloid pathology confirmation", status: .needsReview, detail: "Requires amyloid PET, CSF, or plasma p-tau217"))
    checklist.append(AmyloidChecklistItem(label: "ApoE genotyping", status: .needsReview, detail: "ApoE4 homozygotes at high ARIA risk"))
    checklist.append(AmyloidChecklistItem(label: "Baseline brain MRI", status: .needsReview, detail: "Rule out >4 microhemorrhages"))

    let finalEligibility: AmyloidEligibility = qmciTotal < 36 ? .tooImpaired : (eligible ? .candidate : .notEligible)

    let narrative: String
    var nextSteps: [String] = []
    switch finalEligibility {
    case .candidate:
        narrative = "Cognitive profile falls within the treatment window for anti-amyloid therapy. Amyloid confirmation, ApoE genotyping, and baseline MRI required."
        nextSteps = ["Order plasma p-tau217", "Order ApoE genotyping", "Order brain MRI with SWI/GRE", "Refer to neurology"]
    case .notEligible:
        narrative = "Patient does not currently meet eligibility criteria for anti-amyloid therapy."
        nextSteps = ["Order reversible cause workup (TSH, B12, CBC, CMP)", "Screen and treat depression", "Repeat screening in 6-12 months"]
    case .tooImpaired:
        narrative = "Cognitive impairment is below the treatment window for anti-amyloid therapy."
        nextSteps = ["Refer to neurology for dementia staging", "Assess safety: driving, fall risk", "Consider cholinesterase inhibitor"]
    case .needsFurtherEval:
        narrative = "Additional evaluation needed."
        nextSteps = ["Refer for neuropsychological testing", "Order reversible cause workup"]
    }

    return AmyloidTriageResult(eligibility: finalEligibility, cdrScore: cdrEquivalent, qmciScore: qmciTotal, qmciClassification: classification, checklist: checklist, narrative: narrative, nextSteps: nextSteps)
}

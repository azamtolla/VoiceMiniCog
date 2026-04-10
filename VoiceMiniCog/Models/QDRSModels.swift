//
//  QDRSModels.swift
//  VoiceMiniCog
//
//  Quick Dementia Rating Scale (QDRS) - informant/caregiver version
//  Based on Galvin JE et al. (2014). Free for clinical use.
//  Scoring: Each item 0/0.5/1. Cutoff >= 1.5 = positive screen.
//  NOTE: This is the informant version. The avatar speaks the full question
//  text verbatim (no shortened aliases) to maintain scoring validity.
//

import Foundation
import SwiftUI
import Combine

enum QDRSAnswer: String, Codable, CaseIterable {
    case normal = "normal"
    case sometimes = "sometimes"
    case changed = "changed"

    var score: Double {
        switch self {
        case .normal: return 0.0
        case .sometimes: return 0.5
        case .changed: return 1.0
        }
    }

    var displayLabel: String {
        switch self {
        case .normal: return "No Change"
        case .sometimes: return "Sometimes"
        case .changed: return "Yes, Changed"
        }
    }

    var color: Color {
        switch self {
        case .normal: return MCDesign.Colors.success
        case .sometimes: return MCDesign.Colors.warning
        case .changed: return MCDesign.Colors.error
        }
    }
}

struct QDRSQuestion: Identifiable {
    let id: Int
    let domain: String
    let text: String
    let voicePrompt: String
}

let QDRS_QUESTIONS: [QDRSQuestion] = [
    QDRSQuestion(id: 0, domain: "Memory", text: "Has the patient had more trouble remembering things that happened recently, like conversations or appointments?", voicePrompt: "Has the patient had more trouble remembering things that happened recently, like conversations or appointments?"),
    QDRSQuestion(id: 1, domain: "Orientation", text: "Does the patient sometimes get confused about the date, day of the week, or where they are?", voicePrompt: "Does the patient sometimes get confused about the date, day of the week, or where they are?"),
    QDRSQuestion(id: 2, domain: "Judgment", text: "Have you noticed any changes in the patient's ability to make decisions or solve everyday problems?", voicePrompt: "Have you noticed any changes in the patient's ability to make decisions or solve everyday problems?"),
    QDRSQuestion(id: 3, domain: "Community", text: "Has it become harder for the patient to manage things outside the home, like shopping or handling finances?", voicePrompt: "Has it become harder for the patient to manage things outside the home, like shopping or handling finances?"),
    QDRSQuestion(id: 4, domain: "Home Activities", text: "Has the patient had more difficulty with tasks around the house, like cooking, cleaning, or using appliances?", voicePrompt: "Has the patient had more difficulty with tasks around the house, like cooking, cleaning, or using appliances?"),
    QDRSQuestion(id: 5, domain: "Personal Care", text: "Does the patient need more help than before with personal care, like bathing, dressing, or grooming?", voicePrompt: "Does the patient need more help than before with personal care, like bathing, dressing, or grooming?"),
    QDRSQuestion(id: 6, domain: "Behavior", text: "Have you noticed any changes in the patient's mood, personality, or behavior that seem different from their usual self?", voicePrompt: "Have you noticed any changes in the patient's mood, personality, or behavior that seem different from their usual self?"),
    QDRSQuestion(id: 7, domain: "Language", text: "Does the patient have more trouble than before finding the right words or following a conversation?", voicePrompt: "Does the patient have more trouble than before finding the right words or following a conversation?"),
    QDRSQuestion(id: 8, domain: "Interest", text: "Has the patient lost interest in hobbies or activities they used to enjoy?", voicePrompt: "Has the patient lost interest in hobbies or activities they used to enjoy?"),
    QDRSQuestion(id: 9, domain: "Repetition", text: "Do you find that the patient repeats the same questions or stories more than before?", voicePrompt: "Do you find that the patient repeats the same questions or stories more than before?"),
]

final class QDRSState: ObservableObject, Codable {
    @Published var answers: [QDRSAnswer?] = Array(repeating: nil, count: QDRS_QUESTIONS.count)
    @Published var currentIndex: Int = 0
    @Published var declined: Bool = false
    @Published var isComplete: Bool = false
    @Published var respondentType: QDRSRespondentType = .patient

    var totalScore: Double { answers.compactMap { $0?.score }.reduce(0, +) }
    var isPositiveScreen: Bool { totalScore >= 1.5 }
    var answeredCount: Int { answers.compactMap { $0 }.count }
    var progress: Double {
        guard !QDRS_QUESTIONS.isEmpty else { return 0 }
        return Double(answeredCount) / Double(QDRS_QUESTIONS.count)
    }
    var currentQuestion: QDRSQuestion? {
        guard currentIndex < QDRS_QUESTIONS.count else { return nil }
        return QDRS_QUESTIONS[currentIndex]
    }
    var flaggedDomains: [String] {
        answers.enumerated().compactMap { index, answer in
            guard let a = answer, a != .normal, index < QDRS_QUESTIONS.count else { return nil }
            return QDRS_QUESTIONS[index].domain
        }
    }
    var riskLabel: String {
        switch totalScore {
        case 0..<1.5: return "Low Concern"
        case 1.5..<3.0: return "Mild Concern"
        case 3.0..<5.0: return "Moderate Concern"
        default: return "Significant Concern"
        }
    }
    var riskColor: Color {
        switch totalScore {
        case 0..<1.5: return MCDesign.Colors.success
        case 1.5..<3.0: return MCDesign.Colors.warning
        default: return MCDesign.Colors.error
        }
    }

    // MARK: - Codable (manual for @Observable)

    enum CodingKeys: String, CodingKey {
        case answers, currentIndex, declined, isComplete, respondentType
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answers = try c.decode([QDRSAnswer?].self, forKey: .answers)
        currentIndex = try c.decode(Int.self, forKey: .currentIndex)
        declined = try c.decode(Bool.self, forKey: .declined)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        respondentType = try c.decode(QDRSRespondentType.self, forKey: .respondentType)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answers, forKey: .answers)
        try c.encode(currentIndex, forKey: .currentIndex)
        try c.encode(declined, forKey: .declined)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encode(respondentType, forKey: .respondentType)
    }

    init() {}

    // Avoid swift_task_deinitOnExecutorMainActorBackDeploy crash on iOS 17.6
    // by never hopping to the main actor at dealloc time.
    nonisolated deinit {}

    func answer(_ answer: QDRSAnswer) {
        guard currentIndex < QDRS_QUESTIONS.count else { return }
        answers[currentIndex] = answer
        if currentIndex < QDRS_QUESTIONS.count - 1 { currentIndex += 1 }
        else { isComplete = true }
    }

    func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        answers[currentIndex] = nil
        isComplete = false
    }

    func reset() {
        answers = Array(repeating: nil, count: QDRS_QUESTIONS.count)
        currentIndex = 0; declined = false; isComplete = false; respondentType = .patient
    }
}

enum QDRSRespondentType: String, Codable {
    case patient = "patient"
    case informant = "informant"
}

struct QDRSInput {
    let totalScore: Double
    let isPositiveScreen: Bool
    let respondentType: QDRSRespondentType
    let flaggedDomains: [String]
}

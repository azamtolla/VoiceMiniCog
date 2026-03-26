//
//  QDRSModels.swift
//  VoiceMiniCog
//
//  Quick Dementia Rating Scale (QDRS) - patient-reported version
//  Based on Galvin JE et al. (2014). Free for clinical use.
//  Scoring: Each item 0/0.5/1. Cutoff >= 1.5 = positive screen.
//

import Foundation
import SwiftUI

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
    QDRSQuestion(id: 0, domain: "Memory", text: "Do you have more trouble remembering things that happened recently, like conversations or appointments?", voicePrompt: "Do you have more trouble remembering recent things?"),
    QDRSQuestion(id: 1, domain: "Orientation", text: "Do you sometimes get confused about the date, day of the week, or where you are?", voicePrompt: "Do you sometimes get confused about the date or where you are?"),
    QDRSQuestion(id: 2, domain: "Judgment", text: "Have you noticed any changes in your ability to make decisions or solve everyday problems?", voicePrompt: "Have you noticed changes in your ability to make decisions?"),
    QDRSQuestion(id: 3, domain: "Community", text: "Has it become harder to manage things outside the home, like shopping, driving, or handling finances?", voicePrompt: "Has it become harder to manage things outside the home?"),
    QDRSQuestion(id: 4, domain: "Home Activities", text: "Have you had more difficulty with tasks around the house, like cooking, cleaning, or using appliances?", voicePrompt: "Have you had more difficulty with tasks around the house?"),
    QDRSQuestion(id: 5, domain: "Personal Care", text: "Do you need more help than before with personal care, like bathing, dressing, or grooming?", voicePrompt: "Do you need more help with personal care?"),
    QDRSQuestion(id: 6, domain: "Behavior", text: "Have you noticed any changes in your mood, personality, or behavior that are different from your usual self?", voicePrompt: "Have you noticed changes in your mood or behavior?"),
    QDRSQuestion(id: 7, domain: "Language", text: "Do you have more trouble than before finding the right words or following a conversation?", voicePrompt: "Do you have more trouble finding the right words?"),
    QDRSQuestion(id: 8, domain: "Interest", text: "Have you lost interest in hobbies or activities that you used to enjoy?", voicePrompt: "Have you lost interest in hobbies you used to enjoy?"),
    QDRSQuestion(id: 9, domain: "Repetition", text: "Do people tell you that you repeat the same questions or stories more than before?", voicePrompt: "Do people tell you that you repeat questions or stories?"),
]

@Observable
class QDRSState {
    var answers: [QDRSAnswer?] = Array(repeating: nil, count: QDRS_QUESTIONS.count)
    var currentIndex: Int = 0
    var declined: Bool = false
    var isComplete: Bool = false
    var respondentType: QDRSRespondentType = .patient

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

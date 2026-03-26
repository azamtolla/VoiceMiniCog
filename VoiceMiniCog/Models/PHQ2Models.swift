//
//  PHQ2Models.swift
//  VoiceMiniCog
//
//  PHQ-2 depression gate (2 questions). Positive ≥ 3 triggers PHQ-9.
//

import Foundation

let PHQ2_QUESTIONS: [String] = [
    "Over the past 2 weeks, how often have you been bothered by having little interest or pleasure in doing things?",
    "Over the past 2 weeks, how often have you been bothered by feeling down, depressed, or hopeless?"
]

enum PHQ2Answer: Int, CaseIterable {
    case notAtAll = 0
    case severalDays = 1
    case moreThanHalf = 2
    case nearlyEveryDay = 3

    var displayLabel: String {
        switch self {
        case .notAtAll: return "Not at all"
        case .severalDays: return "Several days"
        case .moreThanHalf: return "More than half the days"
        case .nearlyEveryDay: return "Nearly every day"
        }
    }
}

struct PHQ2State {
    var answers: [PHQ2Answer?] = [nil, nil]
    var totalScore: Int { answers.compactMap { $0?.rawValue }.reduce(0, +) }
    var isPositive: Bool { totalScore >= 3 }
    var isComplete: Bool { answers.allSatisfy { $0 != nil } }
}

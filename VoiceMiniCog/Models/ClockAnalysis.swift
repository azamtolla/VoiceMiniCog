//
//  ClockAnalysis.swift
//  VoiceMiniCog
//
//  Clock drawing analysis models matching React implementation
//

import Foundation

struct ClockAnalysisResponse: Codable {
    let aiClass: Int  // 0, 1, or 2
    let shulmanRange: String
    let severity: String
    let confidence: Double
    let interpretation: String
    let clinicalAction: String
    let probabilities: ClockProbabilities

    enum CodingKeys: String, CodingKey {
        case aiClass = "ai_class"
        case shulmanRange = "shulman_range"
        case severity
        case confidence
        case interpretation
        case clinicalAction = "clinical_action"
        case probabilities
    }
}

struct ClockProbabilities: Codable {
    let severe01: Double
    let moderate23: Double
    let normal45: Double

    enum CodingKeys: String, CodingKey {
        case severe01 = "severe_0_1"
        case moderate23 = "moderate_2_3"
        case normal45 = "normal_4_5"
    }
}

enum ClockScoreSource: String, Codable {
    case ai
    case clinician
}

// Shulman scoring guide
struct ShulmanScore {
    let score: Int
    let label: String
    let description: String

    static let all: [ShulmanScore] = [
        ShulmanScore(score: 5, label: "Perfect", description: "All numbers correct, hands point to 11 and 2"),
        ShulmanScore(score: 4, label: "Minor errors", description: "Slight spacing issues, correct time shown"),
        ShulmanScore(score: 3, label: "Inaccurate time", description: "Numbers present, hands wrong or unclear"),
        ShulmanScore(score: 2, label: "Moderate disorganization", description: "Numbers missing/bunched, no clear time"),
        ShulmanScore(score: 1, label: "Severe disorganization", description: "Numbers scattered, no clock face"),
        ShulmanScore(score: 0, label: "Unable to attempt", description: "No recognizable clock or refused"),
    ]
}

// Mini-Cog clock score options (0, 1, 2)
struct MiniCogClockOption {
    let score: Int
    let label: String
    let description: String
    let shulmanRange: String

    static let all: [MiniCogClockOption] = [
        MiniCogClockOption(score: 0, label: "Severe Impairment", description: "Major errors: blank/unrecognizable, severe spatial distortion, no numbers", shulmanRange: "Shulman 0-1"),
        MiniCogClockOption(score: 1, label: "Moderate Impairment", description: "Some errors: missing numbers, wrong hand positions, mild spacing issues", shulmanRange: "Shulman 2-3"),
        MiniCogClockOption(score: 2, label: "Normal", description: "All 12 numbers present, correct positions, hands showing 11:10", shulmanRange: "Shulman 4-5"),
    ]
}

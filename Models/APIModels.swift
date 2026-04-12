//
//  APIModels.swift
//  VoiceMiniCog
//

import Foundation

// MARK: - Next Step API

struct NextStepRequest: Codable {
    let phase: String
    let transcript: String
    let partialScores: PartialScores
}

struct PartialScores: Codable {
    let wordRegistration: Int
    let clock: Int
    let recall: Int
}

struct NextStepResponse: Codable {
    let nextPrompt: String
    let updatedScores: UpdatedScores?
    let words: [String]?  // Words for registration phase
}

struct UpdatedScores: Codable {
    let wordRegistration: Int?
    let clock: Int?
    let recall: Int?
    let recalledWords: [String]?
}

// MARK: - Clock Analysis API

struct ClockAnalysisResponse: Codable {
    let aiScore: Int           // 0, 1, or 2
    let features: ClockFeatures
    let confidence: Double?
    let interpretation: String?
}

struct ClockFeatures: Codable {
    let hasCircle: Bool?
    let hasAllNumbers: Bool?
    let numbersInCorrectPosition: Bool?
    let hasHourHand: Bool?
    let hasMinuteHand: Bool?
    let handsShowCorrectTime: Bool?
    let overallQuality: String?
}

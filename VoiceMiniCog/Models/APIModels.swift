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

// Clock Analysis models are in ClockAnalysis.swift

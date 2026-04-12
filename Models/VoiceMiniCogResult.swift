//
//  VoiceMiniCogResult.swift
//  VoiceMiniCog
//
//  Final assessment result matching React VoiceMiniCogResult
//

import Foundation

struct VoiceMiniCogResult: Codable {
    let wordListUsed: [String]
    let registrationAttempts: Int
    let registrationResults: [Int]
    let recallCorrectCount: Int
    let recalledWords: [String]
    let clockScore: Int
    let clockScoreSource: String
    let clockRationale: String
    let clockImageBase64: String?
    let clockDrawingTimeSec: Int
    let totalScore: Int
    let miniCogClassification: String
    let fullTranscript: String
    let conversationLog: [ConversationEntry]
    let aiObservations: [String]

    // AD8 integrated fields
    let ad8Score: Int?
    let ad8Answers: [String?]
    let ad8RespondentType: String
    let ad8FlaggedDomains: [String]
    let ad8ScreenPositive: Bool?
    let ad8Declined: Bool

    let compositeRisk: CompositeRiskOutput?
    let completedAt: String
}

struct ConversationEntry: Codable {
    let role: String
    let text: String
    let timestamp: String
}

extension AssessmentState {
    func buildResult() -> VoiceMiniCogResult {
        let finalClockScore = clinicianClockScore ?? clockScore ?? 0
        let total = recallScore + finalClockScore

        // Classification
        var classification: String
        if screenInterpretation == .notInterpretable {
            classification = "screen_positive" // Treat as positive for safety
        } else if screenInterpretation == .positive {
            classification = "screen_positive"
        } else if screenInterpretation == .negative {
            classification = "screen_negative"
        } else {
            classification = miniCogClassification
        }

        // Build transcript
        let transcript = messages
            .filter { $0.role != .system }
            .map { "[\($0.role.rawValue.uppercased())] \($0.content)" }
            .joined(separator: "\n")

        // Build conversation log
        let log = messages.map { msg in
            ConversationEntry(
                role: msg.role.rawValue,
                text: msg.content,
                timestamp: ISO8601DateFormatter().string(from: msg.timestamp)
            )
        }

        // AD8 answers as strings
        let ad8AnswerStrings: [String?] = ad8State.answers.map { $0?.rawValue }

        return VoiceMiniCogResult(
            wordListUsed: words,
            registrationAttempts: registrationAttempt,
            registrationResults: registrationResults,
            recallCorrectCount: recallScore,
            recalledWords: recalledWords,
            clockScore: finalClockScore,
            clockScoreSource: clockScoreSource.rawValue,
            clockRationale: clockRationale,
            clockImageBase64: clockImageBase64,
            clockDrawingTimeSec: clockTimeSec,
            totalScore: total,
            miniCogClassification: classification,
            fullTranscript: transcript,
            conversationLog: log,
            aiObservations: aiObservations,
            ad8Score: ad8State.score,
            ad8Answers: ad8AnswerStrings,
            ad8RespondentType: ad8State.respondentType.rawValue,
            ad8FlaggedDomains: ad8State.flaggedDomains,
            ad8ScreenPositive: ad8State.isScreenPositive,
            ad8Declined: ad8State.declined,
            compositeRisk: compositeRisk,
            completedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

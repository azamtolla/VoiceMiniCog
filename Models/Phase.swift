//
//  Phase.swift
//  VoiceMiniCog
//

import Foundation

enum Phase: String, CaseIterable, Codable {
    case intro
    case wordRegistration
    case clockDrawing
    case recall
    case summary

    var displayName: String {
        switch self {
        case .intro:
            return "Introduction"
        case .wordRegistration:
            return "Word Registration"
        case .clockDrawing:
            return "Clock Drawing"
        case .recall:
            return "Word Recall"
        case .summary:
            return "Summary"
        }
    }

    var prompt: String {
        switch self {
        case .intro:
            return "Hello! I'm going to walk you through a short memory exercise. It only takes a few minutes. Ready to begin?"
        case .wordRegistration:
            return "I'm going to say three words. Please listen carefully and remember them."
        case .clockDrawing:
            return "Now, please draw a clock face with all the numbers. Set the hands to show ten past eleven."
        case .recall:
            return "What were those three words I asked you to remember?"
        case .summary:
            return "Thank you for completing the assessment."
        }
    }

    var next: Phase? {
        switch self {
        case .intro:
            return .wordRegistration
        case .wordRegistration:
            return .clockDrawing
        case .clockDrawing:
            return .recall
        case .recall:
            return .summary
        case .summary:
            return nil
        }
    }

    var requiresListening: Bool {
        switch self {
        case .intro, .wordRegistration, .recall:
            return true
        case .clockDrawing, .summary:
            return false
        }
    }
}

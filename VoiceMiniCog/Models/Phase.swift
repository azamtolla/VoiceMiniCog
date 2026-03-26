//
// Phase.swift
// VoiceMiniCog
//
// Assessment phases for Qmci-based screening.
//

import Foundation

enum Phase: String, CaseIterable, Codable {
    case intake              // QDRS + PHQ-2 + demographics
    case qmciOrientation
    case qmciRegistration
    case qmciClockDrawing
    case qmciVerbalFluency
    case qmciLogicalMemory
    case qmciDelayedRecall
    case scoring             // automatic
    case report              // PCP summary
}

extension Phase {
    var displayName: String {
        switch self {
        case .intake: return "Patient Intake"
        case .qmciOrientation: return "Orientation"
        case .qmciRegistration: return "Word Learning"
        case .qmciClockDrawing: return "Clock Drawing"
        case .qmciVerbalFluency: return "Verbal Fluency"
        case .qmciLogicalMemory: return "Story Recall"
        case .qmciDelayedRecall: return "Word Recall"
        case .scoring: return "Scoring"
        case .report: return "Report"
        }
    }

    var next: Phase? {
        switch self {
        case .intake: return .qmciOrientation
        case .qmciOrientation: return .qmciRegistration
        case .qmciRegistration: return .qmciClockDrawing
        case .qmciClockDrawing: return .qmciVerbalFluency
        case .qmciVerbalFluency: return .qmciLogicalMemory
        case .qmciLogicalMemory: return .qmciDelayedRecall
        case .qmciDelayedRecall: return .scoring
        case .scoring: return .report
        case .report: return nil
        }
    }

    var isQmciSubtest: Bool {
        switch self {
        case .qmciOrientation, .qmciRegistration, .qmciClockDrawing,
             .qmciVerbalFluency, .qmciLogicalMemory, .qmciDelayedRecall:
            return true
        default:
            return false
        }
    }

    var requiresListening: Bool {
        switch self {
        case .qmciOrientation, .qmciRegistration, .qmciVerbalFluency,
             .qmciLogicalMemory, .qmciDelayedRecall:
            return true
        default:
            return false
        }
    }

    var prompt: String {
        switch self {
        case .intake:
            return "Before we begin, I have a few short questions about your everyday memory and activities."
        case .qmciOrientation:
            return "I'm going to ask you a few questions about today's date."
        case .qmciRegistration:
            return "I'm going to say five words. Please listen carefully and remember them."
        case .qmciClockDrawing:
            return "Now, please draw a clock face with all the numbers. Set the hands to show ten past eleven."
        case .qmciVerbalFluency:
            return "Name as many animals as you can in one minute."
        case .qmciLogicalMemory:
            return "I'm going to read you a short story. Listen carefully, and then tell me everything you remember."
        case .qmciDelayedRecall:
            return "What were those five words I asked you to remember earlier?"
        case .scoring:
            return "Calculating scores..."
        case .report:
            return "Assessment complete. Review the summary report."
        }
    }
}

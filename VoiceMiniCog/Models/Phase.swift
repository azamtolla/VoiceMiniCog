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
            return "Thank you for being here today. Before we begin the memory exercises, I have ten brief questions for you — the caregiver or family member. I'll ask you about any changes you may have noticed in the patient's everyday memory and activities. There are no right or wrong answers. Please answer based on what you've observed."
        case .qmciOrientation:
            return "First, I'll ask a few general questions — things like today's date and where we are. There are no trick questions. Just answer as best you can."
        case .qmciRegistration:
            return "I'm going to read you five words. Please listen carefully and try to remember them — I'll ask you about them again later."
        case .qmciClockDrawing:
            return "Now I'd like you to draw a clock face. Put in all twelve numbers. Then draw the hands to show the time eleven ten — like ten minutes after eleven o'clock."
        case .qmciVerbalFluency:
            return "I'd like you to name as many different animals as you can. You can name any animal — dogs, birds, fish, anything. Try to name as many as you can in one minute. Ready? Begin."
        case .qmciLogicalMemory:
            return "I'm going to read you a short story. Listen carefully and try to remember as much of it as you can. When I'm finished, I'll ask you to tell me everything you can recall — even small details. Ready?"
        case .qmciDelayedRecall:
            return "What were those five words I asked you to remember earlier?"
        case .scoring:
            return "Calculating scores..."
        case .report:
            return "Assessment complete. Review the summary report."
        }
    }
}

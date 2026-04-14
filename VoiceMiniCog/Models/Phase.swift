//
// Phase.swift
// VoiceMiniCog
//
// Assessment phases for Qmci-based screening.
//

import Foundation

/// **Persistence / routing enum** — tracks the patient's position in the
/// overall assessment workflow and is `Codable` for state restoration.
///
/// This enum is distinct from `AssessmentPhaseID` (in AvatarLayoutManager.swift),
/// which drives the **avatar layout state machine** (width ratios, accent colors,
/// avatar behavior). The two enums intentionally diverge:
///
///   • `Phase` includes `.intake`, `.scoring`, and `.report` — stages that have
///     no avatar UI and are invisible to the layout manager.
///   • `AssessmentPhaseID` includes `.welcome` and fine-grained intake sub-phases
///     (`.qdrs`, `.phq2`) that `Phase` collapses into `.intake`.
///
/// Mapping between the two happens in `AvatarAssessmentCanvas` and `ContentView`.
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

    /// QMCI verbatim examiner scripts — do not paraphrase
    var prompt: String {
        switch self {
        case .intake:
            return LeftPaneSpeechCopy.qdrsIntro
        case .qmciOrientation:
            return LeftPaneSpeechCopy.orientationIntro
        case .qmciRegistration:
            return LeftPaneSpeechCopy.wordRegistrationIntro
        case .qmciClockDrawing:
            return LeftPaneSpeechCopy.clockDrawingInstruction
        case .qmciVerbalFluency:
            return LeftPaneSpeechCopy.verbalFluencyInstruction
        case .qmciLogicalMemory:
            return LeftPaneSpeechCopy.storyRecallIntro
        case .qmciDelayedRecall:
            return LeftPaneSpeechCopy.delayedRecallPrompt
        case .scoring:
            return "Calculating scores..."
        case .report:
            return "Assessment complete. Review the summary report."
        }
    }
}

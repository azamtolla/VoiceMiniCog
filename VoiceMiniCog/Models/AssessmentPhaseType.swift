//
//  AssessmentPhaseType.swift
//  VoiceMiniCog
//
//  Coarse phase classification used ONLY to scope LLM behavior (e.g. whether
//  speculative_inference is enabled for the current phase). This is distinct
//  from:
//    - `Phase` (persistence/routing enum in Phase.swift)
//    - `AssessmentPhaseID` (avatar layout state machine in AvatarLayoutManager.swift)
//
//  CLINICAL RATIONALE for scope:
//  - Intro and outro phases use natural LLM conversation. speculative_inference
//    improves response latency on the LLM turn and has no clinical-validity
//    implications because nothing the LLM says in these phases is scored.
//  - Subtest phases (registration, clock, recall, etc.) use scripted
//    conversation.echo utterances. The LLM is NOT supposed to generate
//    free-form output. speculative_inference would waste compute on predictions
//    that get overridden by the echo queue, and in rare cases could leak
//    unscripted content into the subtest audio stream — a clinical-validity
//    risk.
//
//  Therefore: speculative_inference ON for .intro / .outro, OFF for all
//  subtests. The mapping is enforced in DailyCallManager.setPhase(_:).
//

import Foundation

public enum AssessmentPhaseType: String, Codable, Sendable {
    case intro              // Welcome, greeting, consent, handoff confirmation
    case orientation        // QMCI orientation questions
    case wordRegistration   // 5-word auditory registration (up to 3 trials)
    case verbalFluency      // Animal-naming fluency
    case clockDrawing       // On-iPad clock drawing
    case storyRecall        // Logical memory
    case wordRecall         // Delayed recall of registered words
    case outro              // Post-assessment wrap-up, next-steps messaging

    /// True when the LLM is doing natural conversation and speculative
    /// prefill is appropriate. False for scripted-echo subtest phases.
    public var allowsSpeculativeInference: Bool {
        switch self {
        case .intro, .outro:
            return true
        case .orientation, .wordRegistration, .verbalFluency,
             .clockDrawing, .storyRecall, .wordRecall:
            return false
        }
    }

    /// True for phases that score patient performance. These require the
    /// deterministic echo flow — no LLM ad-lib permitted.
    public var isScoredSubtest: Bool {
        switch self {
        case .orientation, .wordRegistration, .verbalFluency,
             .clockDrawing, .storyRecall, .wordRecall:
            return true
        case .intro, .outro:
            return false
        }
    }
}

/// Maps the persistence/routing `Phase` enum to its LLM-behavior classification.
/// Internal because `Phase` is internal — Swift forbids public extensions on
/// non-public types.
extension Phase {
    var speculativePhaseType: AssessmentPhaseType {
        switch self {
        case .intake:             return .intro
        case .qmciOrientation:    return .orientation
        case .qmciRegistration:   return .wordRegistration
        case .qmciClockDrawing:   return .clockDrawing
        case .qmciVerbalFluency:  return .verbalFluency
        case .qmciLogicalMemory:  return .storyRecall
        case .qmciDelayedRecall:  return .wordRecall
        case .scoring, .report:   return .outro
        }
    }
}

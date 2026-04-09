//
//  AvatarLayoutManager.swift
//  VoiceMiniCog
//
//  @Observable state machine controlling avatar width, phase transitions,
//  accent colors, and avatar behavior for the avatar-guided assessment UI.
//

import SwiftUI
import Observation

// MARK: - AvatarBehavior

enum AvatarBehavior: String {
    case idle
    case speaking
    case listening
    case waiting
    case narrating
    case acknowledging
    case completing
}

// MARK: - AssessmentFlowType

// ┌─────────────┬──────────────────────────────────────────────────────────┐
// │ Flow Type   │ Phase Sequence                                          │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .quick      │ welcome → orientation → wordReg → clock → fluency →    │
// │             │ story → wordRecall                                      │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .caregiver  │ welcome → qdrs → completion                            │
// ├─────────────┼──────────────────────────────────────────────────────────┤
// │ .extended   │ (same as .quick — intentionally separate for future     │
// │             │ divergence, do NOT collapse into .quick)                │
// └─────────────┴──────────────────────────────────────────────────────────┘

enum AssessmentFlowType: String, Codable {
    /// Patient cognitive screen — no informant questions
    case quick
    /// Informant/caregiver QDRS — no cognitive subtests
    case caregiver
    /// Full battery — currently same as quick, separate route for future divergence
    case extended

    var phaseSequence: [AssessmentPhaseID] {
        switch self {
        case .quick, .extended:
            return [.welcome, .orientation, .wordRegistration, .clockDrawing,
                    .verbalFluency, .storyRecall, .wordRecall]
        case .caregiver:
            return [.welcome, .qdrs, .completion]
        }
    }
}

// MARK: - AssessmentPhaseID

enum AssessmentPhaseID: Int, CaseIterable {
    case welcome         = 1
    case qdrs            = 2
    case phq2            = 3
    case orientation     = 4
    case wordRegistration = 5
    case clockDrawing    = 6
    case verbalFluency   = 7
    case storyRecall     = 8
    case wordRecall      = 9
    case completion      = 10

    var displayName: String {
        switch self {
        case .welcome:          return "Welcome"
        case .qdrs:             return "Memory Questionnaire"
        case .phq2:             return "Mood Check"
        case .orientation:      return "Orientation"
        case .wordRegistration: return "Word Registration"
        case .clockDrawing:     return "Clock Drawing"
        case .verbalFluency:    return "Verbal Fluency"
        case .storyRecall:      return "Story Recall"
        case .wordRecall:       return "Word Recall"
        case .completion:       return "Complete"
        }
    }

    /// True for phases where content takes over the screen (avatar shrinks to minimum)
    var isExpanded: Bool {
        switch self {
        case .clockDrawing, .verbalFluency:
            return true
        default:
            return false
        }
    }
}

// MARK: - AvatarLayoutManager

@Observable
class AvatarLayoutManager {

    // MARK: Properties

    var flowType: AssessmentFlowType = .quick
    var currentPhase: AssessmentPhaseID = .welcome
    var avatarBehavior: AvatarBehavior = .idle
    var isTransitioning: Bool = false

    /// Ordered phases for the current flow type
    var phaseSequence: [AssessmentPhaseID] { flowType.phaseSequence }

    /// Index of the current phase within the sequence
    var currentPhaseIndex: Int { phaseSequence.firstIndex(of: currentPhase) ?? 0 }

    // MARK: Computed Properties

    /// Fraction of total width allocated to avatar zone (right side)
    var avatarWidthRatio: CGFloat {
        AssessmentTheme.avatarWidthRatios[currentPhase.rawValue] ?? 0.50
    }

    /// Phase-specific accent color
    var accentColor: Color {
        AssessmentTheme.accent(for: currentPhase.rawValue)
    }

    /// Avatar opacity per phase — reduced when content takes over
    var avatarOpacity: Double {
        switch currentPhase {
        case .clockDrawing, .verbalFluency:
            return 0.4
        case .wordRecall:
            return 0.85
        default:
            return 1.0
        }
    }

    /// Whether to show the accent ring around the avatar
    var showAvatarRing: Bool {
        avatarBehavior != .waiting
    }

    // MARK: Counts

    var completedPhaseCount: Int {
        currentPhaseIndex
    }

    var totalPhaseCount: Int {
        phaseSequence.count
    }

    // MARK: - Phase Transition

    /// Advance to the next phase in the flow sequence (no-op if already on last phase)
    func advanceToNextPhase() {
        let nextIndex = currentPhaseIndex + 1
        guard nextIndex < phaseSequence.count else { return }
        transitionTo(phaseSequence[nextIndex])
    }

    /// Animate transition to the specified phase
    func transitionTo(_ phase: AssessmentPhaseID) {
        guard !isTransitioning else { return }
        isTransitioning = true

        withAnimation(.spring(duration: 0.55, bounce: 0.15)) {
            currentPhase = phase
            avatarBehavior = defaultBehavior(for: phase)
        }

        // Clear transitioning flag after animation completes
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000) // 0.55s
            isTransitioning = false
        }
    }

    // MARK: - Default Behavior Per Phase

    func defaultBehavior(for phase: AssessmentPhaseID) -> AvatarBehavior {
        switch phase {
        case .welcome:          return .speaking
        case .qdrs:             return .listening
        case .phq2:             return .listening
        case .orientation:      return .listening
        case .wordRegistration: return .speaking
        case .clockDrawing:     return .waiting
        case .verbalFluency:    return .waiting
        case .storyRecall:      return .narrating
        case .wordRecall:       return .listening
        case .completion:       return .completing
        }
    }

    // MARK: - Avatar State Helpers

    func setAvatarSpeaking() {
        avatarBehavior = .speaking
    }

    func setAvatarListening() {
        avatarBehavior = .listening
    }

    func setAvatarIdle() {
        avatarBehavior = .idle
    }

    /// Briefly set avatar to .acknowledging, then revert to .speaking after 1.2 seconds
    func acknowledgeAnswer() {
        avatarBehavior = .acknowledging

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
            avatarBehavior = .speaking
        }
    }
}

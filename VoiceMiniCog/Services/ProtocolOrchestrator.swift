//
//  ProtocolOrchestrator.swift
//  VoiceMiniCog
//
//  State machine driving the 5-phase assessment sequence.
//  Sends overwrite_context to PersonaPlex at each transition,
//  plays scripted clips for deterministic prompts.
//

import Foundation

enum AssessmentPhase: String, CaseIterable {
    case qdrs
    case wordRegistration
    case clockDrawing
    case delayedRecall
    case wrapUp
}

@Observable
final class ProtocolOrchestrator {
    let personaBridge: PersonaBridge
    let audioArbitrator: AudioArbitrator
    let scriptClipPlayer: ScriptClipPlayer

    var currentPhase: AssessmentPhase = .qdrs
    var lastCompletedClipId: String?
    var isRunning = false

    init(personaBridge: PersonaBridge, audioArbitrator: AudioArbitrator, scriptClipPlayer: ScriptClipPlayer) {
        self.personaBridge = personaBridge
        self.audioArbitrator = audioArbitrator
        self.scriptClipPlayer = scriptClipPlayer

        // Wire dependencies
        self.scriptClipPlayer.personaBridge = personaBridge
        self.scriptClipPlayer.audioArbitrator = audioArbitrator
        self.personaBridge.replicaEventObserver = audioArbitrator
    }

    // MARK: - Run Full Assessment

    func runAssessment(wordListId: String = "word_list_A") async {
        isRunning = true

        // Phase 0: QDRS
        await transitionTo(.qdrs)

        // Phase 1: Word Registration (scripted)
        await transitionTo(.wordRegistration)
        await scriptClipPlayer.playClip(id: "word_registration_intro")
        await scriptClipPlayer.playClip(id: wordListId)

        // Phase 2: Clock Drawing (scripted instruction)
        await transitionTo(.clockDrawing)
        await scriptClipPlayer.playClip(id: "clock_instruction")

        // Phase 3: Delayed Recall
        await transitionTo(.delayedRecall)
        await scriptClipPlayer.playClip(id: "recall_prompt")

        // Phase 4: Wrap-up
        await transitionTo(.wrapUp)

        isRunning = false
    }

    // MARK: - Phase Transitions

    func transitionTo(_ phase: AssessmentPhase) async {
        currentPhase = phase
        let context = contextForPhase(phase)
        await personaBridge.overwriteContext(context)
        print("[Orchestrator] Transitioned to: \(phase.rawValue)")
    }

    // MARK: - Cued Recall

    func playCue(for word: String) async {
        switch word.lowercased() {
        case "apple": await scriptClipPlayer.playClip(id: "cue_apple")
        case "table": await scriptClipPlayer.playClip(id: "cue_table")
        case "penny": await scriptClipPlayer.playClip(id: "cue_penny")
        default: print("[Orchestrator] No cue clip for word: \(word)")
        }
    }

    // MARK: - Context Strings

    private func contextForPhase(_ phase: AssessmentPhase) -> String {
        switch phase {
        case .qdrs:
            return """
            You are Anna, a warm and professional cognitive assessment guide. \
            You are administering the QDRS (Quick Dementia Rating Scale). \
            Ask the patient or their informant the following 10 domain questions one at a time. \
            Wait for their response before moving to the next question. \
            Be encouraging and patient. Do not rush. \
            Current domains: memory, orientation, judgment, community affairs, \
            home and hobbies, personal care, language, mood/behavior, mobility, eating.
            """
        case .wordRegistration:
            return """
            You are about to present a 3-word memory list. \
            Stay silent — the scripted word list will play now. \
            After the words play, ask the patient to repeat them back. \
            If they miss a word, gently repeat only the missed word (up to 3 attempts).
            """
        case .clockDrawing:
            return """
            The patient is now drawing a clock showing 10 minutes after 11. \
            Stay silent while they draw. Do not speak unless they ask for help. \
            If they ask, you may repeat: 'Draw a clock with all the numbers, hands showing ten past eleven.'
            """
        case .delayedRecall:
            return """
            Word drawing distractor task is complete. \
            Now ask the patient to recall the 3 words from earlier. \
            Listen carefully. If they recall all 3 freely, move on. \
            If they miss any, provide the semantic category cue for each missed word only. \
            Track: free recall count, cued recall count. Do not reveal the words directly.
            """
        case .wrapUp:
            return """
            The assessment is complete. Thank the patient warmly. \
            Say: 'Thank you so much for your time today. The clinician will review your results shortly.' \
            Then stay silent.
            """
        }
    }
}

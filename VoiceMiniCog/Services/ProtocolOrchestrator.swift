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
            A scripted audio clip is about to play the 3-word memory list. \
            Stay completely silent during clip playback. \
            After the clip finishes, ask the patient to repeat the words back. \
            If they cannot repeat all three, say only: 'Let me play them one more time.' \
            Do NOT say the actual words yourself — the clip will replay. \
            You may encourage: 'Take your time' or 'You're doing great.'
            """
        case .clockDrawing:
            return """
            A scripted audio clip will give the clock drawing instruction. \
            Stay completely silent during clip playback and while the patient draws. \
            Do not speak unless they ask a question. \
            If they ask for help, say only: 'Take your time, draw what you remember.' \
            Do NOT repeat the clock instruction yourself — the clip will replay if needed.
            """
        case .delayedRecall:
            return """
            A scripted audio clip will ask the patient to recall the 5 words. \
            Stay completely silent during clip playback. \
            After the clip plays, listen to the patient's response. \
            Do NOT say any of the words yourself. Do NOT provide hints or cues. \
            If they struggle, say only: 'Take your time, any words you can remember.' \
            The app will play scripted cue clips if needed — you stay silent during those too.
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

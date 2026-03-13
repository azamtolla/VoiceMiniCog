//
//  AssessmentState.swift
//  VoiceMiniCog
//
//  Full assessment state matching React VoiceMiniCog
//

import Foundation
import SwiftUI

// Word lists matching React app
let WORD_LISTS: [[String]] = [
    ["banana", "sunrise", "chair"],
    ["leader", "season", "table"],
    ["village", "kitchen", "baby"],
    ["dollar", "ship", "garden"],
    ["river", "nation", "finger"],
    ["captain", "garden", "picture"],
]

// Listen timeouts per stage (ms) — generous for elderly patients
let LISTEN_TIMEOUTS: [String: Int] = [
    "greeting": 10000,
    "register_words": 12000,
    "register_retry": 12000,
    "recall_prompt": 7000,
    "recall_followup": 5000,
    "default": 10000,
]

// Phase metadata for visual stepper
struct PhaseMeta {
    let key: String
    let label: String
    let iconName: String
    let color: Color
}

let PHASE_META: [PhaseMeta] = [
    PhaseMeta(key: "greeting", label: "Introduction", iconName: "waveform", color: Color(hex: "#1a5276")),
    PhaseMeta(key: "registration", label: "Word Registration", iconName: "brain", color: Color(hex: "#7c3aed")),
    PhaseMeta(key: "clock", label: "Clock Drawing", iconName: "pencil.and.outline", color: Color(hex: "#0891b2")),
    PhaseMeta(key: "recall", label: "Word Recall", iconName: "brain.head.profile", color: Color(hex: "#c026d3")),
    PhaseMeta(key: "ad8", label: "AD8 Questions", iconName: "list.clipboard", color: Color(hex: "#ea580c")),
    PhaseMeta(key: "results", label: "Results", iconName: "checkmark.circle", color: Color(hex: "#16a34a")),
]

// Assistant state
enum AssistantState: String {
    case idle
    case speaking
    case listening
    case processing
    case thinking
    case complete
}

// Chat message
struct ChatMessage: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = "\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(6))"
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum MessageRole: String {
    case assistant
    case patient
    case system
}

// Screen interpretation
enum ScreenInterpretation: String {
    case negative
    case positive
    case notInterpretable = "not_interpretable"
}

@Observable
class AssessmentState {
    // Current phase and state
    var currentPhase: Phase = .intro
    var assistantState: AssistantState = .idle
    var transcript: String = ""
    var interimTranscript: String = ""
    var isListening: Bool = false
    var isSpeaking: Bool = false

    // Word registration
    var words: [String] = []
    var wordListIndex: Int = 0
    var registrationAttempt: Int = 1
    var registrationResults: [Int] = []

    // Scores
    var wordRegistrationScore: Int = 0
    var clockScore: Int? = nil
    var clockScoreSource: ClockScoreSource = .clinician
    var recallScore: Int = 0
    var recalledWords: [String] = []

    // Clock drawing
    var clockImage: UIImage? = nil
    var clockImageBase64: String? = nil
    var clockAnalysis: ClockAnalysisResponse? = nil
    var clockTimeSec: Int = 0
    var clockRationale: String = ""
    var isAIScoringClock: Bool = false

    // AD8
    var ad8State: AD8State = AD8State()

    // Composite risk
    var compositeRisk: CompositeRiskOutput? = nil

    // Prompts from backend or generated
    var currentPrompt: String = ""

    // Error handling
    var errorMessage: String? = nil

    // Conversation log
    var messages: [ChatMessage] = []

    // AI observations
    var aiObservations: [String] = []

    // Clinician selections
    var clinicianClockScore: Int? = nil
    var screenInterpretation: ScreenInterpretation? = nil
    var providerActions: [String] = []
    var positiveScreenActions: [String] = []
    var selectedLabs: [String] = []
    var otherAction: String = ""

    // iOS specific
    var waitingForTapToSpeak: Bool = false
    var canAutoListen: Bool = false

    var totalScore: Int {
        return recallScore + (clockScore ?? 0)
    }

    var clinicianTotalScore: Int {
        return recallScore + (clinicianClockScore ?? clockScore ?? 0)
    }

    var isPositiveScreen: Bool {
        return totalScore < 3
    }

    var miniCogClassification: String {
        if recallScore == 0 {
            return "screen_positive"
        } else if recallScore == 3 {
            return "screen_negative"
        } else {
            // For recall 1-2: clock score of 2 = negative, clock score of 0 or 1 = positive
            return (clockScore ?? 0) == 2 ? "screen_negative" : "screen_positive"
        }
    }

    init() {
        selectWordList()
    }

    func selectWordList() {
        // Get next word list, avoiding last used (matching React logic)
        let key = "minicog_last_word_list_index"
        let lastIndex = UserDefaults.standard.integer(forKey: key)
        var nextIndex: Int
        repeat {
            nextIndex = Int.random(in: 0..<WORD_LISTS.count)
        } while nextIndex == lastIndex && WORD_LISTS.count > 1

        UserDefaults.standard.set(nextIndex, forKey: key)
        wordListIndex = nextIndex
        words = WORD_LISTS[nextIndex]
    }

    func reset() {
        currentPhase = .intro
        assistantState = .idle
        transcript = ""
        interimTranscript = ""
        isListening = false
        isSpeaking = false
        wordRegistrationScore = 0
        clockScore = nil
        clockScoreSource = .clinician
        recallScore = 0
        registrationAttempt = 1
        registrationResults = []
        recalledWords = []
        clockImage = nil
        clockImageBase64 = nil
        clockAnalysis = nil
        clockTimeSec = 0
        clockRationale = ""
        isAIScoringClock = false
        ad8State = AD8State()
        compositeRisk = nil
        currentPrompt = ""
        errorMessage = nil
        messages = []
        aiObservations = []
        clinicianClockScore = nil
        screenInterpretation = nil
        providerActions = []
        positiveScreenActions = []
        selectedLabs = []
        otherAction = ""
        waitingForTapToSpeak = false
        canAutoListen = false
        selectWordList()
    }

    func moveToNextPhase() {
        if let next = currentPhase.next {
            currentPhase = next
            transcript = ""
            currentPrompt = getPromptForPhase(currentPhase)
        }
    }

    // MARK: - Messages

    func addMessage(role: MessageRole, content: String) {
        let msg = ChatMessage(role: role, content: content)
        messages.append(msg)
    }

    func addObservation(_ note: String) {
        aiObservations.append(note)
    }

    // MARK: - Prompts matching React app

    func getPromptForPhase(_ phase: Phase) -> String {
        switch phase {
        case .intro:
            return "Hello! I'm going to walk you through a short memory exercise. It only takes a few minutes. I'll say three words, and I'd like you to remember them. We'll come back to those words a little later. Ready?"

        case .wordRegistration:
            return "I'm going to say three words. Please listen carefully and remember them."

        case .clockDrawing:
            return "Now, please draw a clock face with all the numbers. Set the hands to show ten past eleven."

        case .recall:
            return "Now, what were those three words I asked you to remember earlier?"

        case .summary:
            return "Thank you for completing the assessment."
        }
    }

    func getWordIntroPrompt() -> String {
        return "I'm going to say three words that I'd like you to remember. I'll ask you to recall them later. The words are: \(words[0])... \(words[1])... \(words[2])."
    }

    func getRepeatPrompt() -> String {
        return "Can you repeat those three words for me?"
    }

    func getRetryPrompt(attempt: Int, lastScore: Int) -> String {
        if lastScore == 0 {
            return "Let me say those words one more time. Listen carefully: \(words.joined(separator: "... ")). Now, can you tell me those three words?"
        } else if lastScore == 1 {
            return "Good, you got one! Let's try again. The words are: \(words.joined(separator: "... ")). What are those three words?"
        } else {
            return "Good, you got \(lastScore)! One more time: \(words.joined(separator: "... ")). Can you repeat all three?"
        }
    }

    func getRecallFollowupPrompt(count: Int) -> String {
        if count == 0 {
            return "Take your time. Can you try to remember any of the words?"
        } else {
            return "Good, you remembered \(count). Can you remember any others?"
        }
    }

    func getThankYouPrompt() -> String {
        return "Thank you, nice job."
    }

    func getTransitionToClockPrompt() -> String {
        return "Great, now we're going to do something different."
    }

    func getClockInstructionsPrompt() -> String {
        return "Now I'd like you to draw a clock. Draw a circle, put in all the numbers, and set the hands to show ten minutes past eleven."
    }

    func getAD8IntroPrompt() -> String {
        return "Next I'm going to ask about some everyday abilities. I'm interested in whether you've noticed any changes over the past few years related to thinking or memory — not physical problems like vision or arthritis. For each one, just tell me: yes, there's been a change, no, things are about the same, or you're not sure. Take your time."
    }

    func getAD8OfferPrompt() -> String {
        return "We're almost done. Would you also like to answer a few brief questions about everyday memory? It's completely optional."
    }

    func getFinalThankYouPrompt() -> String {
        return "Thank you for taking the test. We're all done with the memory exercise."
    }

    // MARK: - Phase name mapping for stepper

    func getPhaseName() -> String {
        switch currentPhase {
        case .intro:
            return "greeting"
        case .wordRegistration:
            return "registration"
        case .clockDrawing:
            return "clock"
        case .recall:
            return "recall"
        case .summary:
            return "results"
        }
    }

    // MARK: - Compute composite risk

    func computeCompositeRiskIfNeeded() {
        guard let ad8Score = ad8State.score else { return }

        let mcInput = MiniCogInput(
            totalScore: clinicianTotalScore,
            recallScore: recallScore,
            clockScore: clinicianClockScore ?? clockScore ?? 0,
            aiClockExecutiveFlag: (clinicianClockScore ?? clockScore ?? 0) == 2 &&
                clockAnalysis != nil && clockAnalysis!.aiClass < 2
        )

        let ad8Input = AD8Input(
            totalScore: ad8Score,
            respondentType: ad8State.respondentType,
            flaggedDomains: ad8State.flaggedDomains,
            uncertainCount: ad8State.answers.filter { $0 == .na }.count
        )

        compositeRisk = computeCompositeRisk(miniCog: mcInput, ad8: ad8Input)
    }
}

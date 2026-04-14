//
//  AssessmentState.swift
//  VoiceMiniCog
//
//  Full assessment state matching React VoiceMiniCog
//

import Foundation
import Observation
import SwiftUI

// DEPRECATED: MiniCog 3-word lists replaced by QMCI 5-word lists in QmciModels.swift
// Kept as empty alias to prevent compile errors in legacy views that reference it.
let MINICOG_WORD_SETS: [[String]] = QMCI_WORD_LISTS
let WORD_LISTS = QMCI_WORD_LISTS

// MARK: - Repeat Tracking

/// Tracks how many times each scripted clip has been replayed in this session.
/// Used for clinical documentation and enforcing per-phase limits.
struct RepeatTracker: Codable {
    var wordIntro: Int = 0
    var clockInstructions: Int = 0
    var recallPrompt: Int = 0

    static let maxRepeats = 3

    mutating func increment(for phase: String) {
        switch phase {
        case "word_intro": wordIntro += 1
        case "clock_instructions": clockInstructions += 1
        case "recall_prompt": recallPrompt += 1
        default: break
        }
    }

    func count(for phase: String) -> Int {
        switch phase {
        case "word_intro": return wordIntro
        case "clock_instructions": return clockInstructions
        case "recall_prompt": return recallPrompt
        default: return 0
        }
    }

    func canRepeat(phase: String) -> Bool {
        count(for: phase) < Self.maxRepeats
    }

    mutating func reset() {
        wordIntro = 0
        clockInstructions = 0
        recallPrompt = 0
    }
}

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
    PhaseMeta(key: "qdrs", label: "Memory Questionnaire", iconName: "checklist", color: Color(hex: "#ea580c")),
    PhaseMeta(key: "greeting", label: "Introduction", iconName: "waveform", color: Color(hex: "#1a5276")),
    PhaseMeta(key: "registration", label: "Word Registration", iconName: "brain", color: Color(hex: "#7c3aed")),
    PhaseMeta(key: "clock", label: "Clock Drawing", iconName: "pencil.and.outline", color: Color(hex: "#0891b2")),
    PhaseMeta(key: "recall", label: "Word Recall", iconName: "brain.head.profile", color: Color(hex: "#c026d3")),
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
enum ScreenInterpretation: String, Codable {
    case negative
    case positive
    case notInterpretable = "not_interpretable"
}

@Observable
class AssessmentState: Codable {
    // Current phase and state
    var currentPhase: Phase = .intake
    var assistantState: AssistantState = .idle
    var transcript: String = ""
    var interimTranscript: String = ""
    var isListening: Bool = false
    var isSpeaking: Bool = false

    // Word registration
    var words: [String] = []
    var wordListIndex: Int = 0
    var selectedWordSetIndex: Int = 0
    var registrationAttempt: Int = 1
    var registrationResults: [Int] = []

    // Repeat tracking (for scripted clips)
    var repeatTracker = RepeatTracker()

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

    // QDRS
    var qdrsState: QDRSState = QDRSState()

    // Qmci
    var qmciState: QmciState = QmciState()

    // PHQ-2
    var phq2State: PHQ2State = PHQ2State()

    // Patient demographics
    var patientAge: Int = 0
    var patientEducationYears: Int = 12

    // Medication flags
    var medicationFlags: MedicationFlags = MedicationFlags()

    // Anti-amyloid triage (computed at scoring — not persisted)
    var amyloidTriage: AmyloidTriageResult? = nil

    // Workup orders (computed at scoring — not persisted)
    var workupOrders: [ReversibleCauseOrder] = []

    // Composite risk (computed at scoring — not persisted)
    var compositeRisk: CompositeRiskOutput? = nil

    // ICD-10 suggestion
    var suggestedICD10: String {
        switch qmciState.classification {
        case .normal: return "R41.81 — Age-related cognitive decline"
        case .mciProbable: return "G31.84 — Mild cognitive impairment"
        case .dementiaRange: return "F03.90 — Unspecified dementia"
        }
    }

    // Prompts from backend or generated
    var currentPrompt: String = ""

    // Error handling (transient — not persisted)
    var errorMessage: String? = nil

    // Conversation log (transient — not persisted)
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

    // iOS specific (transient — not persisted)
    var waitingForTapToSpeak: Bool = false
    var canAutoListen: Bool = false

    // MARK: - Codable (manual for @Observable)
    //
    // Skipped properties (transient / non-serializable):
    //   assistantState, isListening, isSpeaking — transient UI state
    //   clockImage — UIImage (clockImageBase64 is persisted instead)
    //   interimTranscript — transient partial speech
    //   messages — transcript history
    //   errorMessage — transient
    //   waitingForTapToSpeak, canAutoListen — transient UI
    //   amyloidTriage, workupOrders, compositeRisk — recomputed at scoring

    enum CodingKeys: String, CodingKey {
        case currentPhase, transcript
        case words, wordListIndex, selectedWordSetIndex
        case registrationAttempt, registrationResults, repeatTracker
        case wordRegistrationScore, clockScore, clockScoreSource
        case recallScore, recalledWords
        case clockImageBase64, clockAnalysis, clockTimeSec
        case clockRationale, isAIScoringClock
        case qdrsState, qmciState, phq2State
        case patientAge, patientEducationYears, medicationFlags
        case currentPrompt, aiObservations
        case clinicianClockScore, screenInterpretation
        case providerActions, positiveScreenActions, selectedLabs, otherAction
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentPhase = try c.decode(Phase.self, forKey: .currentPhase)
        transcript = try c.decode(String.self, forKey: .transcript)
        words = try c.decode([String].self, forKey: .words)
        wordListIndex = try c.decode(Int.self, forKey: .wordListIndex)
        selectedWordSetIndex = try c.decode(Int.self, forKey: .selectedWordSetIndex)
        registrationAttempt = try c.decode(Int.self, forKey: .registrationAttempt)
        registrationResults = try c.decode([Int].self, forKey: .registrationResults)
        repeatTracker = try c.decode(RepeatTracker.self, forKey: .repeatTracker)
        wordRegistrationScore = try c.decode(Int.self, forKey: .wordRegistrationScore)
        clockScore = try c.decodeIfPresent(Int.self, forKey: .clockScore)
        clockScoreSource = try c.decode(ClockScoreSource.self, forKey: .clockScoreSource)
        recallScore = try c.decode(Int.self, forKey: .recallScore)
        recalledWords = try c.decode([String].self, forKey: .recalledWords)
        clockImageBase64 = try c.decodeIfPresent(String.self, forKey: .clockImageBase64)
        clockAnalysis = try c.decodeIfPresent(ClockAnalysisResponse.self, forKey: .clockAnalysis)
        clockTimeSec = try c.decode(Int.self, forKey: .clockTimeSec)
        clockRationale = try c.decode(String.self, forKey: .clockRationale)
        isAIScoringClock = try c.decode(Bool.self, forKey: .isAIScoringClock)
        qdrsState = try c.decode(QDRSState.self, forKey: .qdrsState)
        qmciState = try c.decode(QmciState.self, forKey: .qmciState)
        phq2State = try c.decode(PHQ2State.self, forKey: .phq2State)
        patientAge = try c.decode(Int.self, forKey: .patientAge)
        patientEducationYears = try c.decode(Int.self, forKey: .patientEducationYears)
        medicationFlags = try c.decode(MedicationFlags.self, forKey: .medicationFlags)
        currentPrompt = try c.decode(String.self, forKey: .currentPrompt)
        aiObservations = try c.decode([String].self, forKey: .aiObservations)
        clinicianClockScore = try c.decodeIfPresent(Int.self, forKey: .clinicianClockScore)
        screenInterpretation = try c.decodeIfPresent(ScreenInterpretation.self, forKey: .screenInterpretation)
        providerActions = try c.decode([String].self, forKey: .providerActions)
        positiveScreenActions = try c.decode([String].self, forKey: .positiveScreenActions)
        selectedLabs = try c.decode([String].self, forKey: .selectedLabs)
        otherAction = try c.decode(String.self, forKey: .otherAction)

        // Transient state defaults
        assistantState = .idle
        isListening = false
        isSpeaking = false
        interimTranscript = ""
        clockImage = nil
        errorMessage = nil
        messages = []
        waitingForTapToSpeak = false
        canAutoListen = false
        amyloidTriage = nil
        workupOrders = []
        compositeRisk = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currentPhase, forKey: .currentPhase)
        try c.encode(transcript, forKey: .transcript)
        try c.encode(words, forKey: .words)
        try c.encode(wordListIndex, forKey: .wordListIndex)
        try c.encode(selectedWordSetIndex, forKey: .selectedWordSetIndex)
        try c.encode(registrationAttempt, forKey: .registrationAttempt)
        try c.encode(registrationResults, forKey: .registrationResults)
        try c.encode(repeatTracker, forKey: .repeatTracker)
        try c.encode(wordRegistrationScore, forKey: .wordRegistrationScore)
        try c.encode(clockScore, forKey: .clockScore)
        try c.encode(clockScoreSource, forKey: .clockScoreSource)
        try c.encode(recallScore, forKey: .recallScore)
        try c.encode(recalledWords, forKey: .recalledWords)
        try c.encode(clockImageBase64, forKey: .clockImageBase64)
        try c.encode(clockAnalysis, forKey: .clockAnalysis)
        try c.encode(clockTimeSec, forKey: .clockTimeSec)
        try c.encode(clockRationale, forKey: .clockRationale)
        try c.encode(isAIScoringClock, forKey: .isAIScoringClock)
        try c.encode(qdrsState, forKey: .qdrsState)
        try c.encode(qmciState, forKey: .qmciState)
        try c.encode(phq2State, forKey: .phq2State)
        try c.encode(patientAge, forKey: .patientAge)
        try c.encode(patientEducationYears, forKey: .patientEducationYears)
        try c.encode(medicationFlags, forKey: .medicationFlags)
        try c.encode(currentPrompt, forKey: .currentPrompt)
        try c.encode(aiObservations, forKey: .aiObservations)
        try c.encode(clinicianClockScore, forKey: .clinicianClockScore)
        try c.encode(screenInterpretation, forKey: .screenInterpretation)
        try c.encode(providerActions, forKey: .providerActions)
        try c.encode(positiveScreenActions, forKey: .positiveScreenActions)
        try c.encode(selectedLabs, forKey: .selectedLabs)
        try c.encode(otherAction, forKey: .otherAction)
    }

    var totalScore: Int {
        return recallScore + (clockScore ?? 0)
    }

    var clinicianTotalScore: Int {
        return recallScore + (clinicianClockScore ?? clockScore ?? 0)
    }

    var isPositiveScreen: Bool {
        return totalScore < 3
    }

    var isQDRSPositive: Bool {
        qdrsState.isPositiveScreen
    }

    var isCombinedScreenPositive: Bool {
        isQDRSPositive || isPositiveScreen
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

    /// LEGACY — word list selection is now owned by QmciState.selectWordList()
    /// (which delegates to selectTestVersion). This method keeps the local
    /// `words` / index fields in sync for any remaining callers.
    func selectWordList() {
        // Delegate to QmciState as the single authoritative word list source.
        qmciState.selectWordList()
        wordListIndex = qmciState.registrationWordListIndex
        selectedWordSetIndex = qmciState.registrationWordListIndex
        words = qmciState.registrationWords
    }

    func reset() {
        currentPhase = .intake
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
        qdrsState = QDRSState()
        qmciState = QmciState()
        phq2State = PHQ2State()
        patientAge = 0
        patientEducationYears = 12
        medicationFlags = MedicationFlags()
        amyloidTriage = nil
        workupOrders = []
        compositeRisk = nil
        repeatTracker.reset()
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
        AssessmentPersistence.clear()
    }

    func moveToNextPhase() {
        if let next = currentPhase.next {
            currentPhase = next
            transcript = ""
            currentPrompt = getPromptForPhase(currentPhase)
            AssessmentPersistence.save(self)
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
        return phase.prompt
    }

    // MARK: - QMCI Protocol Prompts (verbatim examiner scripts)

    func getWordIntroPrompt() -> String {
        return LeftPaneSpeechCopy.wordRegistrationIntro
    }

    func getRepeatPrompt() -> String {
        return LeftPaneSpeechCopy.wordRegistrationRepeat
    }

    func getRetryPrompt(attempt: Int, lastScore: Int) -> String {
        let wordList = qmciState.registrationWords
        return LeftPaneSpeechCopy.wordRegistrationRetry(words: wordList)
    }

    func getRecallFollowupPrompt(count: Int) -> String {
        // QMCI protocol: no hints or prompts during delayed recall — 30 seconds, silence
        return ""
    }

    func getThankYouPrompt() -> String {
        return LeftPaneSpeechCopy.closingThankYou
    }

    func getTransitionToClockPrompt() -> String {
        return LeftPaneSpeechCopy.clockDrawingInstruction
    }

    func getClockInstructionsPrompt() -> String {
        return LeftPaneSpeechCopy.clockDrawingInstruction
    }

    func getQDRSIntroPrompt() -> String {
        return LeftPaneSpeechCopy.qdrsIntro
    }

    func getQDRSQuestionPrompt(index: Int) -> String {
        guard index < QDRS_QUESTIONS.count else { return "" }
        return QDRS_QUESTIONS[index].voicePrompt
    }

    func getQDRSCompletionPrompt() -> String {
        return LeftPaneSpeechCopy.qdrsCompletion
    }

    func getStoryRecallPrompt() -> String {
        return LeftPaneSpeechCopy.storyRecallPrompt
    }

    func getStoryRecallFollowupPrompt() -> String {
        return LeftPaneSpeechCopy.storyRecallFollowup
    }

    func getFinalThankYouPrompt() -> String {
        return LeftPaneSpeechCopy.closingThankYou
    }

    // MARK: - Phase name mapping for stepper

    func getPhaseName() -> String {
        return currentPhase.rawValue
    }

    // MARK: - Compute composite risk

    func computeCompositeRiskIfNeeded() {
        let mcInput = MiniCogInput(
            totalScore: clinicianTotalScore,
            recallScore: recallScore,
            clockScore: clinicianClockScore ?? clockScore ?? 0,
            aiClockExecutiveFlag: (clinicianClockScore ?? clockScore ?? 0) == 2 &&
                clockAnalysis != nil && clockAnalysis!.aiClass < 2
        )

        let qInput = QDRSInput(
            totalScore: qdrsState.totalScore,
            isPositiveScreen: qdrsState.isPositiveScreen,
            respondentType: qdrsState.respondentType,
            flaggedDomains: qdrsState.flaggedDomains
        )

        compositeRisk = computeCompositeRiskMiniCogQDRS(
            miniCog: mcInput,
            qdrs: qInput
        )
    }
}

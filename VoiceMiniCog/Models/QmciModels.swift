//
//  QmciModels.swift
//  VoiceMiniCog
//
//  Quick Mild Cognitive Impairment screen (Qmci)
//  O'Caoimh et al. (2012). AUC 0.90 for MCI detection.
//  6 subtests, 100 points total.
//  QMCI validated cutoffs: >=67 = normal, <67 = MCI, <54 = dementia range.
//

import Foundation
import Combine
import CoreGraphics

// MARK: - Qmci Subtest Definitions

enum QmciSubtest: String, CaseIterable, Codable {
    case orientation
    case registration
    case clockDrawing
    case verbalFluency
    case logicalMemory
    case delayedRecall

    var displayName: String {
        switch self {
        case .orientation: return "Orientation"
        case .registration: return "Word Learning"
        case .clockDrawing: return "Clock Drawing"
        case .verbalFluency: return "Verbal Fluency"
        case .logicalMemory: return "Story Recall"
        case .delayedRecall: return "Word Recall"
        }
    }

    var maxScore: Int {
        switch self {
        case .orientation: return 10
        case .registration: return 5
        case .clockDrawing: return 15
        case .verbalFluency: return 20
        case .logicalMemory: return 30
        case .delayedRecall: return 20
        }
    }

    /// QMCI protocol durations
    var durationSeconds: Int {
        switch self {
        case .orientation: return 30      // ~6s per question
        case .registration: return 30     // reading + initial recall
        case .clockDrawing: return 60     // exactly 1 minute per QMCI
        case .verbalFluency: return 60    // exactly 1 minute
        case .logicalMemory: return 60    // ~30s read + 30s recall
        case .delayedRecall: return 30    // 30 seconds, no hints
        }
    }

    var iconName: String {
        switch self {
        case .orientation: return "location.fill"
        case .registration: return "text.badge.star"
        case .clockDrawing: return "clock.fill"
        case .verbalFluency: return "bubble.left.and.text.bubble.right.fill"
        case .logicalMemory: return "book.fill"
        case .delayedRecall: return "brain.head.profile"
        }
    }

    var cognitiveDomainsAssessed: [String] {
        switch self {
        case .orientation: return ["Orientation", "Attention"]
        case .registration: return ["Immediate Memory", "Attention"]
        case .clockDrawing: return ["Executive Function", "Visuospatial"]
        case .verbalFluency: return ["Language", "Executive Function", "Semantic Memory"]
        case .logicalMemory: return ["Episodic Memory", "Language Comprehension"]
        case .delayedRecall: return ["Episodic Memory", "Encoding"]
        }
    }
}

// MARK: - Orientation Items

struct OrientationItem: Identifiable {
    let id: Int
    let question: String
    let voicePrompt: String
    let correctAnswerType: OrientationAnswerType
    let points: Int = 2
}

enum OrientationAnswerType {
    case year
    case month
    case dayOfWeek
    case date
    case country
}

// MARK: - Test Version

/// QMCI coupled test version — selects a single set of registration words AND
/// logical memory story that are administered together. Mapped by raw index to
/// `QMCI_WORD_LISTS` and `LOGICAL_MEMORY_STORIES`.
enum TestVersion: Int, Codable {
    case v1 = 0
    case v2 = 1
    case v3 = 2
}

// MARK: - Clock Drawing Event Capture

struct ClockStrokeEvent: Codable, Equatable {
    let timestamp: TimeInterval   // seconds since canvas start
    let points: [CGPointCodable]  // path points
}

struct ClockPauseEvent: Codable, Equatable {
    let startTimestamp: TimeInterval
    let durationMs: Int
}

/// CGPoint wrapper so we can Codable it.
struct CGPointCodable: Codable, Equatable {
    let x: Double
    let y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    init(x: Double, y: Double) { self.x = x; self.y = y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// QMCI protocol order: country, year, month, date, day of week
// 2 pts each, max 10 sec per answer, no hints
let ORIENTATION_ITEMS: [OrientationItem] = [
    OrientationItem(id: 0, question: "What country is this?", voicePrompt: "What country is this?", correctAnswerType: .country),
    OrientationItem(id: 1, question: "What year is this?", voicePrompt: "What year is this?", correctAnswerType: .year),
    OrientationItem(id: 2, question: "What month is this?", voicePrompt: "What month is this?", correctAnswerType: .month),
    OrientationItem(id: 3, question: "What is today's date?", voicePrompt: "What is today's date?", correctAnswerType: .date),
    OrientationItem(id: 4, question: "What day of the week is it?", voicePrompt: "What day of the week is it?", correctAnswerType: .dayOfWeek),
]

// MARK: - Registration Word Lists (5 words each)

// Validated QMCI word sets — use alternates for repeat testing to reduce practice effects
let QMCI_WORD_LISTS: [[String]] = [
    ["dog", "rain", "butter", "love", "door"],       // Standard set
    ["cat", "dark", "rat", "heat", "bread"],          // Alternate set 2
    ["fear", "round", "bed", "chair", "fruit"],       // Alternate set 3
]

// MARK: - Logical Memory Stories

struct LogicalMemoryStory: Identifiable {
    let id: Int
    let text: String
    let voiceText: String
    let scoringUnits: [String]
    let maxScore: Int = 30
}

// Validated QMCI Logical Memory stories — verbatim recall only, 2 pts per key word
// Use alternates for repeat testing to reduce practice effects
let LOGICAL_MEMORY_STORIES: [LogicalMemoryStory] = [
    // Verbatim O'Caoimh red-fox story and scoring units taken from the Molloy
    // & O'Caoimh QMCI scoring sheet. 15 highlighted content units × 2 pts = 30.
    // Note: "across" is prose, NOT a scoring unit. "fragrant" IS a scoring unit.
    LogicalMemoryStory(
        id: 0,
        text: "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes.",
        voiceText: "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes.",
        scoringUnits: [
            "red", "fox", "ran", "ploughed", "field",
            "chased", "brown", "dog",
            "hot", "May", "morning",
            "fragrant", "blossoms", "forming", "bushes"
        ]
    ),
    LogicalMemoryStory(
        id: 1,
        text: "The brown dog ran across the metal bridge. It was a cold October day. It was hunting a white rabbit. The ripe apples were hanging on the trees.",
        voiceText: "The brown dog ran across the metal bridge. It was a cold October day. It was hunting a white rabbit. The ripe apples were hanging on the trees.",
        scoringUnits: [
            "brown", "dog", "ran", "across", "metal",
            "bridge", "cold", "October", "day",
            "hunting", "white", "rabbit", "ripe",
            "apples", "trees"
        ]
    ),
    LogicalMemoryStory(
        id: 2,
        text: "The white hen walked across the concrete road. It was a warm September afternoon. It was followed by a black cat. The dry leaves were blowing in the wind.",
        voiceText: "The white hen walked across the concrete road. It was a warm September afternoon. It was followed by a black cat. The dry leaves were blowing in the wind.",
        scoringUnits: [
            "white", "hen", "walked", "across", "concrete",
            "road", "warm", "September", "afternoon",
            "followed", "black", "cat", "dry",
            "leaves", "wind"
        ]
    ),
]

// MARK: - Qmci State

final class QmciState: ObservableObject, Codable {
    @Published var currentSubtest: QmciSubtest = .orientation
    /// QMCI orientation scoring — 3 levels per question:
    /// 2 = completely correct, 1 = attempted but incorrect, 0 = no attempt / unrelated.
    /// `nil` = unanswered. Final scoring is clinician-adjusted in the PCP report.
    @Published var orientationScores: [Int?] = Array(repeating: nil, count: 5)
    @Published var registrationWords: [String] = []
    @Published var registrationWordListIndex: Int = 0
    @Published var registrationRecalledWords: [String] = []
    @Published var registrationAttempts: Int = 0
    @Published var verbalFluencyWords: [String] = []
    @Published var verbalFluencyDurationSec: Int = 60
    @Published var verbalFluencyTranscript: String = ""
    @Published var logicalMemoryStoryIndex: Int = 0
    @Published var logicalMemoryRecalledUnits: [String] = []
    @Published var logicalMemoryTranscript: String = ""
    @Published var delayedRecallWords: [String] = []
    @Published var delayedRecallTranscript: String = ""
    @Published var completedSubtests: Set<QmciSubtest> = []
    @Published var isComplete: Bool = false
    @Published var clockDrawingScore: Int = 0

    // MARK: - Spec-required session + capture fields

    /// Coupled test version — keeps `registrationWordListIndex` and
    /// `logicalMemoryStoryIndex` in sync so the same version number
    /// identifies the administered word list and story pair.
    @Published var testVersion: TestVersion = .v1

    @Published var sessionID: UUID = UUID()
    @Published var sessionDateTime: Date = Date()

    /// Raw patient text per orientation question (index-aligned with `orientationScores`).
    @Published var orientationResponses: [String] = Array(repeating: "", count: 5)
    /// True if the patient provided any response to the question at that index.
    @Published var orientationAttempted: [Bool] = Array(repeating: false, count: 5)

    /// Per-trial recalled words for the 3 registration trials.
    @Published var registrationTrialWords: [[String]] = [[], [], []]

    /// Full verbatim list of animals named INCLUDING duplicates. Distinct from
    /// `verbalFluencyWords` which is the unique/scored list.
    @Published var fluencyAnimalsNamed: [String] = []

    /// PNG-encoded clock image bytes (UIImage is not Codable, so store Data).
    @Published var clockDrawingImagePNG: Data? = nil
    @Published var clockStrokeEvents: [ClockStrokeEvent] = []
    @Published var clockPauseEvents: [ClockPauseEvent] = []
    @Published var clockScoreOverrideBy: String? = nil
    @Published var clockScoreOverrideTimestamp: Date? = nil

    @Published var clinicianDecisionWorkup: Bool? = nil
    @Published var clinicianDecisionRepeat: Bool? = nil
    @Published var clinicianDecisionTimestamp: Date? = nil

    // MARK: - Delayed Recall Telemetry (biomarker research)

    /// Milliseconds from prompt end to first correct word recall
    @Published var recallFirstWordLatencyMs: Int? = nil
    /// Millisecond intervals between successive correct word detections
    @Published var recallInterWordIntervalsMs: [Int] = []
    /// Number of non-target words spoken during recall
    @Published var recallIntrusionCount: Int = 0
    /// Non-target words spoken (for clinician review)
    @Published var recallIntrusions: [String] = []
    /// Semantic substitutions: [(target, said)]
    @Published var recallSemanticSubstitutions: [(String, String)] = []
    /// Number of semantic substitutions
    @Published var recallSemanticSubstitutionCount: Int = 0
    /// Total phase duration in milliseconds
    @Published var recallTotalPhaseDurationMs: Int = 0
    /// Silence in ms before "Any others?" prompt (0 if not used)
    @Published var recallSilenceBeforePromptMs: Int = 0
    /// Whether the "Any others?" follow-up was triggered
    @Published var recallAnyOthersPromptUsed: Bool = false
    /// ASR-detected recalled words (clinician can override in review)
    @Published var recallASRDetectedWords: [String] = []
    /// Clinician overrides on ASR results (word → override-correct)
    @Published var recallClinicianOverrides: [String: Bool] = [:]

    // MARK: - QMCI 15-point Clock Drawing (manual clinician scoring)
    //
    // QMCI protocol rubric for clock drawing (max 15 points):
    //   • 1 point per correctly placed number (1-12)            → 12 pts max
    //   • 1 point for minute hand pointing toward 2 (for 11:10) → 1 pt
    //   • 1 point for hour hand pointing toward 11              → 1 pt
    //   • 1 point for pivot (center point where hands meet)     → 1 pt
    //   • -1 per duplicate number or number > 12
    //
    // Populated by the clinician in the PCP Report view. Call
    // `recomputeClockDrawingScore()` after mutating any cdt* field to
    // refresh `clockDrawingScore`.
    @Published var cdtNumbersPlaced: [Bool] = Array(repeating: false, count: 12)
    @Published var cdtMinuteHandCorrect: Bool = false
    @Published var cdtHourHandCorrect: Bool = false
    @Published var cdtPivotCorrect: Bool = false
    @Published var cdtInvalidNumbersCount: Int = 0

    /// QMCI 15-point clock drawing score computed from detailed fields.
    /// Clamped to 0...15.
    var cdtComputedScore: Int {
        let numberPoints = cdtNumbersPlaced.filter { $0 }.count
        let minutePoint = cdtMinuteHandCorrect ? 1 : 0
        let hourPoint = cdtHourHandCorrect ? 1 : 0
        let pivotPoint = cdtPivotCorrect ? 1 : 0
        let raw = numberPoints + minutePoint + hourPoint + pivotPoint - cdtInvalidNumbersCount
        return max(0, min(15, raw))
    }

    /// Recompute `clockDrawingScore` from the detailed 15-point fields and
    /// write it back to the stored property. Call whenever any cdt* field changes.
    func recomputeClockDrawingScore() {
        clockDrawingScore = cdtComputedScore
    }

    /// Sum of 3-level orientation scores (0, 1, or 2 per question). Max 10.
    var orientationScore: Int {
        min(orientationScores.compactMap { $0 }.reduce(0, +), 10)
    }
    var registrationScore: Int { min(registrationRecalledWords.count, 5) }

    /// Spec-compliant Trial 1 registration score (1 pt per correct word from Trial 1 only).
    var trial1RegistrationScore: Int {
        min(registrationTrialWords.first?.count ?? 0, 5)
    }

    /// QMCI verbal fluency: 0.5 pts per unique animal, max 40 animals = 20 pts.
    /// Rounds up (e.g., 15 animals → 7.5 pts → 8).
    var verbalFluencyScore: Int {
        let uniqueCount = min(Set(verbalFluencyWords.map { $0.lowercased() }).count, 40)
        let raw = Double(uniqueCount) * 0.5
        return Int(raw.rounded(.up))
    }
    var logicalMemoryScore: Int { min(logicalMemoryRecalledUnits.count * 2, 30) }
    var delayedRecallScore: Int { min(delayedRecallWords.count * 4, 20) }

    /// True if any detailed clock-drawing field has been touched by the clinician.
    /// Used to decide whether to trust the computed cdt score vs. a legacy stored value.
    private var hasCDTFieldsSet: Bool {
        cdtNumbersPlaced.contains(true) ||
        cdtMinuteHandCorrect || cdtHourHandCorrect || cdtPivotCorrect ||
        cdtInvalidNumbersCount > 0
    }

    /// Effective clock-drawing score used in totals. Prefers the freshly-
    /// computed value when the detailed fields have been populated, so the
    /// total is never stale if the clinician forgets to call
    /// `recomputeClockDrawingScore()` after editing. Falls back to the stored
    /// `clockDrawingScore` for legacy assessments saved before the 15-point
    /// rubric existed.
    var effectiveClockDrawingScore: Int {
        hasCDTFieldsSet ? cdtComputedScore : clockDrawingScore
    }

    var totalScore: Int {
        orientationScore + registrationScore + effectiveClockDrawingScore +
        verbalFluencyScore + logicalMemoryScore + delayedRecallScore
    }
    var maxScore: Int { 100 }
    var classification: QmciClassification {
        if totalScore >= 67 { return .normal }
        if totalScore >= 54 { return .mciProbable }
        return .dementiaRange
    }

    /// Age/education-adjusted classification per QMCI normative guidance
    /// (O'Caoimh et al., 2012).
    ///
    /// - Patients aged 75 or older: add 3 points to raw score
    /// - Patients with fewer than 12 years of education: add 4 points to raw score
    /// - Both adjustments combine additively.
    ///
    /// The adjusted score is then compared against the standard QMCI cutoffs
    /// (>=67 normal, >=54 MCI, <54 dementia range).
    func adjustedClassification(age: Int, educationYears: Int) -> QmciClassification {
        let adjusted = adjustedScore(age: age, educationYears: educationYears)
        if adjusted >= 67 { return .normal }
        if adjusted >= 54 { return .mciProbable }
        return .dementiaRange
    }

    /// Returns the effective score used for normative classification.
    func adjustedScore(age: Int, educationYears: Int) -> Int {
        var score = totalScore
        if age >= 75 { score += 3 }
        if educationYears < 12 { score += 4 }
        return score
    }

    /// Human-readable list of adjustments applied for display in reports.
    func adjustmentReasons(age: Int, educationYears: Int) -> [String] {
        var reasons: [String] = []
        if age >= 75 { reasons.append("Age-adjusted: +3 for age ≥75") }
        if educationYears < 12 { reasons.append("Education-adjusted: +4 for <12 years") }
        return reasons
    }
    var currentStory: LogicalMemoryStory {
        LOGICAL_MEMORY_STORIES[logicalMemoryStoryIndex % LOGICAL_MEMORY_STORIES.count]
    }

    // MARK: - Codable (manual for @Observable)

    enum CodingKeys: String, CodingKey {
        case currentSubtest, orientationScores, orientationAnswers
        case registrationWords, registrationWordListIndex
        case registrationRecalledWords, registrationAttempts
        case verbalFluencyWords, verbalFluencyDurationSec, verbalFluencyTranscript
        case logicalMemoryStoryIndex, logicalMemoryRecalledUnits, logicalMemoryTranscript
        case delayedRecallWords, delayedRecallTranscript
        case completedSubtests, isComplete, clockDrawingScore
        case cdtNumbersPlaced, cdtMinuteHandCorrect, cdtHourHandCorrect
        case cdtPivotCorrect, cdtInvalidNumbersCount
        // New spec-required fields
        case testVersion
        case sessionID, sessionDateTime
        case orientationResponses, orientationAttempted
        case registrationTrialWords
        case fluencyAnimalsNamed
        case clockDrawingImagePNG, clockStrokeEvents, clockPauseEvents
        case clockScoreOverrideBy, clockScoreOverrideTimestamp
        case clinicianDecisionWorkup, clinicianDecisionRepeat, clinicianDecisionTimestamp
        // Delayed recall telemetry
        case recallFirstWordLatencyMs, recallInterWordIntervalsMs
        case recallIntrusionCount, recallIntrusions
        case recallSemanticSubstitutionCount
        case recallTotalPhaseDurationMs, recallSilenceBeforePromptMs
        case recallAnyOthersPromptUsed
        case recallASRDetectedWords, recallClinicianOverrides
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentSubtest = try c.decode(QmciSubtest.self, forKey: .currentSubtest)
        // Prefer the new 3-level scores field; fall back to legacy Bool? answers
        // for backward compatibility with previously-saved assessments.
        if let scores = try c.decodeIfPresent([Int?].self, forKey: .orientationScores) {
            orientationScores = scores
        } else if let legacy = try c.decodeIfPresent([Bool?].self, forKey: .orientationAnswers) {
            orientationScores = legacy.map { bool in
                guard let bool else { return nil }
                return bool ? 2 : 0
            }
        } else {
            orientationScores = Array(repeating: nil, count: 5)
        }
        registrationWords = try c.decode([String].self, forKey: .registrationWords)
        registrationWordListIndex = try c.decode(Int.self, forKey: .registrationWordListIndex)
        registrationRecalledWords = try c.decode([String].self, forKey: .registrationRecalledWords)
        registrationAttempts = try c.decode(Int.self, forKey: .registrationAttempts)
        verbalFluencyWords = try c.decode([String].self, forKey: .verbalFluencyWords)
        verbalFluencyDurationSec = try c.decode(Int.self, forKey: .verbalFluencyDurationSec)
        verbalFluencyTranscript = try c.decode(String.self, forKey: .verbalFluencyTranscript)
        logicalMemoryStoryIndex = try c.decode(Int.self, forKey: .logicalMemoryStoryIndex)
        logicalMemoryRecalledUnits = try c.decode([String].self, forKey: .logicalMemoryRecalledUnits)
        logicalMemoryTranscript = try c.decode(String.self, forKey: .logicalMemoryTranscript)
        delayedRecallWords = try c.decode([String].self, forKey: .delayedRecallWords)
        delayedRecallTranscript = try c.decode(String.self, forKey: .delayedRecallTranscript)
        completedSubtests = try c.decode(Set<QmciSubtest>.self, forKey: .completedSubtests)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        clockDrawingScore = try c.decode(Int.self, forKey: .clockDrawingScore)
        // QMCI 15-point detailed fields (optional for backward compat)
        cdtNumbersPlaced = try c.decodeIfPresent([Bool].self, forKey: .cdtNumbersPlaced)
            ?? Array(repeating: false, count: 12)
        if cdtNumbersPlaced.count != 12 {
            cdtNumbersPlaced = Array(repeating: false, count: 12)
        }
        cdtMinuteHandCorrect = try c.decodeIfPresent(Bool.self, forKey: .cdtMinuteHandCorrect) ?? false
        cdtHourHandCorrect = try c.decodeIfPresent(Bool.self, forKey: .cdtHourHandCorrect) ?? false
        cdtPivotCorrect = try c.decodeIfPresent(Bool.self, forKey: .cdtPivotCorrect) ?? false
        cdtInvalidNumbersCount = try c.decodeIfPresent(Int.self, forKey: .cdtInvalidNumbersCount) ?? 0

        // New spec-required fields (all optional with defaults for back-compat)
        testVersion = try c.decodeIfPresent(TestVersion.self, forKey: .testVersion) ?? .v1
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID) ?? UUID()
        sessionDateTime = try c.decodeIfPresent(Date.self, forKey: .sessionDateTime) ?? Date()
        orientationResponses = try c.decodeIfPresent([String].self, forKey: .orientationResponses)
            ?? Array(repeating: "", count: 5)
        if orientationResponses.count != 5 {
            orientationResponses = Array(repeating: "", count: 5)
        }
        orientationAttempted = try c.decodeIfPresent([Bool].self, forKey: .orientationAttempted)
            ?? Array(repeating: false, count: 5)
        if orientationAttempted.count != 5 {
            orientationAttempted = Array(repeating: false, count: 5)
        }
        registrationTrialWords = try c.decodeIfPresent([[String]].self, forKey: .registrationTrialWords)
            ?? [[], [], []]
        fluencyAnimalsNamed = try c.decodeIfPresent([String].self, forKey: .fluencyAnimalsNamed) ?? []
        clockDrawingImagePNG = try c.decodeIfPresent(Data.self, forKey: .clockDrawingImagePNG)
        clockStrokeEvents = try c.decodeIfPresent([ClockStrokeEvent].self, forKey: .clockStrokeEvents) ?? []
        clockPauseEvents = try c.decodeIfPresent([ClockPauseEvent].self, forKey: .clockPauseEvents) ?? []
        clockScoreOverrideBy = try c.decodeIfPresent(String.self, forKey: .clockScoreOverrideBy)
        clockScoreOverrideTimestamp = try c.decodeIfPresent(Date.self, forKey: .clockScoreOverrideTimestamp)
        clinicianDecisionWorkup = try c.decodeIfPresent(Bool.self, forKey: .clinicianDecisionWorkup)
        clinicianDecisionRepeat = try c.decodeIfPresent(Bool.self, forKey: .clinicianDecisionRepeat)
        clinicianDecisionTimestamp = try c.decodeIfPresent(Date.self, forKey: .clinicianDecisionTimestamp)
        // Delayed recall telemetry (optional for backward compat)
        recallFirstWordLatencyMs = try c.decodeIfPresent(Int.self, forKey: .recallFirstWordLatencyMs)
        recallInterWordIntervalsMs = try c.decodeIfPresent([Int].self, forKey: .recallInterWordIntervalsMs) ?? []
        recallIntrusionCount = try c.decodeIfPresent(Int.self, forKey: .recallIntrusionCount) ?? 0
        recallIntrusions = try c.decodeIfPresent([String].self, forKey: .recallIntrusions) ?? []
        recallSemanticSubstitutionCount = try c.decodeIfPresent(Int.self, forKey: .recallSemanticSubstitutionCount) ?? 0
        recallTotalPhaseDurationMs = try c.decodeIfPresent(Int.self, forKey: .recallTotalPhaseDurationMs) ?? 0
        recallSilenceBeforePromptMs = try c.decodeIfPresent(Int.self, forKey: .recallSilenceBeforePromptMs) ?? 0
        recallAnyOthersPromptUsed = try c.decodeIfPresent(Bool.self, forKey: .recallAnyOthersPromptUsed) ?? false
        recallASRDetectedWords = try c.decodeIfPresent([String].self, forKey: .recallASRDetectedWords) ?? []
        recallClinicianOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .recallClinicianOverrides) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currentSubtest, forKey: .currentSubtest)
        try c.encode(orientationScores, forKey: .orientationScores)
        try c.encode(registrationWords, forKey: .registrationWords)
        try c.encode(registrationWordListIndex, forKey: .registrationWordListIndex)
        try c.encode(registrationRecalledWords, forKey: .registrationRecalledWords)
        try c.encode(registrationAttempts, forKey: .registrationAttempts)
        try c.encode(verbalFluencyWords, forKey: .verbalFluencyWords)
        try c.encode(verbalFluencyDurationSec, forKey: .verbalFluencyDurationSec)
        try c.encode(verbalFluencyTranscript, forKey: .verbalFluencyTranscript)
        try c.encode(logicalMemoryStoryIndex, forKey: .logicalMemoryStoryIndex)
        try c.encode(logicalMemoryRecalledUnits, forKey: .logicalMemoryRecalledUnits)
        try c.encode(logicalMemoryTranscript, forKey: .logicalMemoryTranscript)
        try c.encode(delayedRecallWords, forKey: .delayedRecallWords)
        try c.encode(delayedRecallTranscript, forKey: .delayedRecallTranscript)
        try c.encode(completedSubtests, forKey: .completedSubtests)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encode(clockDrawingScore, forKey: .clockDrawingScore)
        try c.encode(cdtNumbersPlaced, forKey: .cdtNumbersPlaced)
        try c.encode(cdtMinuteHandCorrect, forKey: .cdtMinuteHandCorrect)
        try c.encode(cdtHourHandCorrect, forKey: .cdtHourHandCorrect)
        try c.encode(cdtPivotCorrect, forKey: .cdtPivotCorrect)
        try c.encode(cdtInvalidNumbersCount, forKey: .cdtInvalidNumbersCount)
        // New spec-required fields
        try c.encode(testVersion, forKey: .testVersion)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(sessionDateTime, forKey: .sessionDateTime)
        try c.encode(orientationResponses, forKey: .orientationResponses)
        try c.encode(orientationAttempted, forKey: .orientationAttempted)
        try c.encode(registrationTrialWords, forKey: .registrationTrialWords)
        try c.encode(fluencyAnimalsNamed, forKey: .fluencyAnimalsNamed)
        try c.encodeIfPresent(clockDrawingImagePNG, forKey: .clockDrawingImagePNG)
        try c.encode(clockStrokeEvents, forKey: .clockStrokeEvents)
        try c.encode(clockPauseEvents, forKey: .clockPauseEvents)
        try c.encodeIfPresent(clockScoreOverrideBy, forKey: .clockScoreOverrideBy)
        try c.encodeIfPresent(clockScoreOverrideTimestamp, forKey: .clockScoreOverrideTimestamp)
        try c.encodeIfPresent(clinicianDecisionWorkup, forKey: .clinicianDecisionWorkup)
        try c.encodeIfPresent(clinicianDecisionRepeat, forKey: .clinicianDecisionRepeat)
        try c.encodeIfPresent(clinicianDecisionTimestamp, forKey: .clinicianDecisionTimestamp)
        // Delayed recall telemetry
        try c.encodeIfPresent(recallFirstWordLatencyMs, forKey: .recallFirstWordLatencyMs)
        try c.encode(recallInterWordIntervalsMs, forKey: .recallInterWordIntervalsMs)
        try c.encode(recallIntrusionCount, forKey: .recallIntrusionCount)
        try c.encode(recallIntrusions, forKey: .recallIntrusions)
        try c.encode(recallSemanticSubstitutionCount, forKey: .recallSemanticSubstitutionCount)
        try c.encode(recallTotalPhaseDurationMs, forKey: .recallTotalPhaseDurationMs)
        try c.encode(recallSilenceBeforePromptMs, forKey: .recallSilenceBeforePromptMs)
        try c.encode(recallAnyOthersPromptUsed, forKey: .recallAnyOthersPromptUsed)
        try c.encode(recallASRDetectedWords, forKey: .recallASRDetectedWords)
        try c.encode(recallClinicianOverrides, forKey: .recallClinicianOverrides)
    }

    init() {}

    // Avoid swift_task_deinitOnExecutorMainActorBackDeploy crash on iOS 17.6
    // by never hopping to the main actor at dealloc time.
    nonisolated deinit {}

    /// Randomly pick one of the three coupled QMCI test versions (word list +
    /// story), avoiding immediate repeat via UserDefaults. Synchronizes
    /// `testVersion`, `registrationWordListIndex`, `registrationWords`, and
    /// `logicalMemoryStoryIndex`.
    func selectTestVersion() {
        let key = "qmci_last_test_version"
        let versionCount = min(QMCI_WORD_LISTS.count, LOGICAL_MEMORY_STORIES.count)
        guard versionCount > 0 else { return }
        let lastIndex = UserDefaults.standard.integer(forKey: key)
        var nextIndex: Int
        repeat { nextIndex = Int.random(in: 0..<versionCount) }
        while nextIndex == lastIndex && versionCount > 1
        UserDefaults.standard.set(nextIndex, forKey: key)
        // Also keep the legacy key in sync so older code paths see the same choice.
        UserDefaults.standard.set(nextIndex, forKey: "qmci_last_word_list_index")
        testVersion = TestVersion(rawValue: nextIndex) ?? .v1
        registrationWordListIndex = nextIndex
        registrationWords = QMCI_WORD_LISTS[nextIndex]
        logicalMemoryStoryIndex = nextIndex
    }

    /// Backward-compatible entry point — delegates to `selectTestVersion()` so
    /// the word list and story stay coupled. Guarantees
    /// `registrationWords.count == 5` and `QMCI_WORD_LISTS.contains(registrationWords)`.
    func selectWordList() {
        selectTestVersion()
    }

    /// Backward-compatible entry point — delegates to `selectTestVersion()` so
    /// the word list and story stay coupled.
    func selectStory() {
        selectTestVersion()
    }

    /// Record that a clinician manually overrode the computed clock drawing score.
    func applyClockScoreOverride(by clinicianID: String) {
        clockScoreOverrideBy = clinicianID
        clockScoreOverrideTimestamp = Date()
    }

    func reset() {
        currentSubtest = .orientation
        orientationScores = Array(repeating: nil, count: 5)
        registrationWords = []; registrationRecalledWords = []; registrationAttempts = 0
        verbalFluencyWords = []; verbalFluencyTranscript = ""
        logicalMemoryRecalledUnits = []; logicalMemoryTranscript = ""
        delayedRecallWords = []; delayedRecallTranscript = ""
        completedSubtests = []; isComplete = false; clockDrawingScore = 0
        cdtNumbersPlaced = Array(repeating: false, count: 12)
        cdtMinuteHandCorrect = false
        cdtHourHandCorrect = false
        cdtPivotCorrect = false
        cdtInvalidNumbersCount = 0

        // New spec-required fields
        testVersion = .v1
        sessionID = UUID()
        sessionDateTime = Date()
        orientationResponses = Array(repeating: "", count: 5)
        orientationAttempted = Array(repeating: false, count: 5)
        registrationTrialWords = [[], [], []]
        fluencyAnimalsNamed = []
        clockDrawingImagePNG = nil
        clockStrokeEvents = []
        clockPauseEvents = []
        clockScoreOverrideBy = nil
        clockScoreOverrideTimestamp = nil
        clinicianDecisionWorkup = nil
        clinicianDecisionRepeat = nil
        clinicianDecisionTimestamp = nil

        // Delayed recall telemetry
        recallFirstWordLatencyMs = nil
        recallInterWordIntervalsMs = []
        recallIntrusionCount = 0
        recallIntrusions = []
        recallSemanticSubstitutions = []
        recallSemanticSubstitutionCount = 0
        recallTotalPhaseDurationMs = 0
        recallSilenceBeforePromptMs = 0
        recallAnyOthersPromptUsed = false
        recallASRDetectedWords = []
        recallClinicianOverrides = [:]

        selectWordList(); selectStory()
    }
}

enum QmciClassification: String, Codable {
    case normal = "Normal Cognition"
    case mciProbable = "MCI Probable"
    case dementiaRange = "Dementia Range"
    var isPositive: Bool { self != .normal }
}

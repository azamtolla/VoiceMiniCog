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
import Observation

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

// QMCI protocol order: country, year, month, date, day of week
// 2 pts each, max 10 sec per answer, no hints
let ORIENTATION_ITEMS: [OrientationItem] = [
    OrientationItem(id: 0, question: "What country are we in?", voicePrompt: "What country are we in?", correctAnswerType: .country),
    OrientationItem(id: 1, question: "What year is it?", voicePrompt: "What year is it?", correctAnswerType: .year),
    OrientationItem(id: 2, question: "What month is it?", voicePrompt: "What month is it?", correctAnswerType: .month),
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
    LogicalMemoryStory(
        id: 0,
        text: "The red fox ran across the ploughed field. It was a hot May morning. It was chased by a brown dog. The blossoms were forming on the bushes.",
        voiceText: "The red fox ran across the ploughed field. It was a hot May morning. It was chased by a brown dog. The blossoms were forming on the bushes.",
        scoringUnits: [
            "red", "fox", "ran", "across", "ploughed",
            "field", "hot", "May", "morning",
            "chased", "brown", "dog", "blossoms",
            "forming", "bushes"
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

@Observable
class QmciState: Codable {
    var currentSubtest: QmciSubtest = .orientation
    /// QMCI orientation scoring — 3 levels per question:
    /// 2 = completely correct, 1 = attempted but incorrect, 0 = no attempt / unrelated.
    /// `nil` = unanswered. Final scoring is clinician-adjusted in the PCP report.
    var orientationScores: [Int?] = Array(repeating: nil, count: 5)
    var registrationWords: [String] = []
    var registrationWordListIndex: Int = 0
    var registrationRecalledWords: [String] = []
    var registrationAttempts: Int = 0
    var verbalFluencyWords: [String] = []
    var verbalFluencyDurationSec: Int = 60
    var verbalFluencyTranscript: String = ""
    var logicalMemoryStoryIndex: Int = 0
    var logicalMemoryRecalledUnits: [String] = []
    var logicalMemoryTranscript: String = ""
    var delayedRecallWords: [String] = []
    var delayedRecallTranscript: String = ""
    var completedSubtests: Set<QmciSubtest> = []
    var isComplete: Bool = false
    var clockDrawingScore: Int = 0

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
    var cdtNumbersPlaced: [Bool] = Array(repeating: false, count: 12)
    var cdtMinuteHandCorrect: Bool = false
    var cdtHourHandCorrect: Bool = false
    var cdtPivotCorrect: Bool = false
    var cdtInvalidNumbersCount: Int = 0

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

    /// QMCI verbal fluency: 0.5 pts per unique animal, max 40 animals = 20 pts.
    /// Rounds up (e.g., 15 animals → 7.5 pts → 8).
    var verbalFluencyScore: Int {
        let uniqueCount = min(Set(verbalFluencyWords.map { $0.lowercased() }).count, 40)
        let raw = Double(uniqueCount) * 0.5
        return Int(raw.rounded(.up))
    }
    var logicalMemoryScore: Int { min(logicalMemoryRecalledUnits.count * 2, 30) }
    var delayedRecallScore: Int { min(delayedRecallWords.count * 4, 20) }
    var totalScore: Int {
        orientationScore + registrationScore + clockDrawingScore +
        verbalFluencyScore + logicalMemoryScore + delayedRecallScore
    }
    var maxScore: Int { 100 }
    var classification: QmciClassification {
        if totalScore >= 67 { return .normal }
        if totalScore >= 54 { return .mciProbable }
        return .dementiaRange
    }

    /// Age/education-adjusted classification per QMCI normative guidance.
    ///
    /// - Patients >75 years old: add 3 points to raw score
    /// - Patients with <12 years of education: add 4 points to raw score
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
        if age > 75 { score += 3 }
        if educationYears < 12 { score += 4 }
        return score
    }

    /// Human-readable list of adjustments applied for display in reports.
    func adjustmentReasons(age: Int, educationYears: Int) -> [String] {
        var reasons: [String] = []
        if age > 75 { reasons.append("Age-adjusted: +3 for age >75") }
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
    }

    init() {}

    func selectWordList() {
        let key = "qmci_last_word_list_index"
        let lastIndex = UserDefaults.standard.integer(forKey: key)
        var nextIndex: Int
        repeat { nextIndex = Int.random(in: 0..<QMCI_WORD_LISTS.count) }
        while nextIndex == lastIndex && QMCI_WORD_LISTS.count > 1
        UserDefaults.standard.set(nextIndex, forKey: key)
        registrationWordListIndex = nextIndex
        registrationWords = QMCI_WORD_LISTS[nextIndex]
    }

    func selectStory() {
        logicalMemoryStoryIndex = Int.random(in: 0..<LOGICAL_MEMORY_STORIES.count)
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
        selectWordList(); selectStory()
    }
}

enum QmciClassification: String, Codable {
    case normal = "Normal Cognition"
    case mciProbable = "MCI Probable"
    case dementiaRange = "Dementia Range"
    var isPositive: Bool { self != .normal }
}

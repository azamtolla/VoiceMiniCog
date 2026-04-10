//
//  QmciModels.swift
//  VoiceMiniCog
//
//  Quick Mild Cognitive Impairment screen (Qmci)
//  O'Caoimh et al. (2012). AUC 0.90 for MCI detection.
//  6 subtests, 100 points total. Cut-off <63 = MCI probable, <54 = dementia range.
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

    var durationSeconds: Int {
        switch self {
        case .orientation: return 30
        case .registration: return 30
        case .clockDrawing: return 90
        case .verbalFluency: return 60
        case .logicalMemory: return 90
        case .delayedRecall: return 60
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
    var orientationAnswers: [Bool?] = Array(repeating: nil, count: 5)
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

    var orientationScore: Int {
        orientationAnswers.compactMap { $0 }.filter { $0 }.count * 2
    }
    var registrationScore: Int { min(registrationRecalledWords.count, 5) }
    var verbalFluencyScore: Int {
        min(Set(verbalFluencyWords.map { $0.lowercased() }).count, 20)
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
    var currentStory: LogicalMemoryStory {
        LOGICAL_MEMORY_STORIES[logicalMemoryStoryIndex % LOGICAL_MEMORY_STORIES.count]
    }

    // MARK: - Codable (manual for @Observable)

    enum CodingKeys: String, CodingKey {
        case currentSubtest, orientationAnswers, registrationWords, registrationWordListIndex
        case registrationRecalledWords, registrationAttempts
        case verbalFluencyWords, verbalFluencyDurationSec, verbalFluencyTranscript
        case logicalMemoryStoryIndex, logicalMemoryRecalledUnits, logicalMemoryTranscript
        case delayedRecallWords, delayedRecallTranscript
        case completedSubtests, isComplete, clockDrawingScore
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentSubtest = try c.decode(QmciSubtest.self, forKey: .currentSubtest)
        orientationAnswers = try c.decode([Bool?].self, forKey: .orientationAnswers)
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(currentSubtest, forKey: .currentSubtest)
        try c.encode(orientationAnswers, forKey: .orientationAnswers)
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
        orientationAnswers = Array(repeating: nil, count: 5)
        registrationWords = []; registrationRecalledWords = []; registrationAttempts = 0
        verbalFluencyWords = []; verbalFluencyTranscript = ""
        logicalMemoryRecalledUnits = []; logicalMemoryTranscript = ""
        delayedRecallWords = []; delayedRecallTranscript = ""
        completedSubtests = []; isComplete = false; clockDrawingScore = 0
        selectWordList(); selectStory()
    }
}

enum QmciClassification: String, Codable {
    case normal = "Normal Cognition"
    case mciProbable = "MCI Probable"
    case dementiaRange = "Dementia Range"
    var isPositive: Bool { self != .normal }
}

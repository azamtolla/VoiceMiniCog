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

enum QmciSubtest: String, CaseIterable {
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

let ORIENTATION_ITEMS: [OrientationItem] = [
    OrientationItem(id: 0, question: "What year is it?", voicePrompt: "What year is it right now?", correctAnswerType: .year),
    OrientationItem(id: 1, question: "What month is it?", voicePrompt: "What month are we in?", correctAnswerType: .month),
    OrientationItem(id: 2, question: "What day of the week is it?", voicePrompt: "What day of the week is it today?", correctAnswerType: .dayOfWeek),
    OrientationItem(id: 3, question: "What is today's date?", voicePrompt: "What is today's date, the number?", correctAnswerType: .date),
    OrientationItem(id: 4, question: "What country are we in?", voicePrompt: "What country are we in?", correctAnswerType: .country),
]

// MARK: - Registration Word Lists (5 words each)

let QMCI_WORD_LISTS: [[String]] = [
    ["butter", "arm", "shore", "letter", "queen"],
    ["cabin", "pipe", "elephant", "chest", "silk"],
    ["bell", "coffee", "school", "parent", "moon"],
    ["engine", "dollar", "bridge", "ticket", "grass"],
]

// MARK: - Logical Memory Stories

struct LogicalMemoryStory: Identifiable {
    let id: Int
    let text: String
    let voiceText: String
    let scoringUnits: [String]
    let maxScore: Int = 30
}

let LOGICAL_MEMORY_STORIES: [LogicalMemoryStory] = [
    LogicalMemoryStory(
        id: 0,
        text: "Anna Thompson of South Boston, employed as a cook in a school cafeteria, reported at the police station that she had been held up on State Street the night before, and robbed of fifty-six dollars. She had four small children, the rent was due, and they had not eaten for two days. The officers, touched by the woman's story, took up a collection for her.",
        voiceText: "Anna Thompson, of South Boston, employed as a cook in a school cafeteria, reported at the police station that she had been held up on State Street the night before and robbed of fifty-six dollars. She had four small children, the rent was due, and they had not eaten for two days. The officers, touched by the woman's story, took up a collection for her.",
        scoringUnits: [
            "Anna", "Thompson", "South Boston", "cook", "school cafeteria",
            "police station", "held up", "State Street", "night before",
            "robbed", "fifty-six dollars", "four children", "rent due",
            "not eaten", "two days", "officers", "collection"
        ]
    ),
    LogicalMemoryStory(
        id: 1,
        text: "Robert Miller of the town of Denton, a truck driver for a local oil company, was walking home late one evening through a park when a young man stepped out from behind a tree and demanded his wallet. Robert gave him the wallet which contained thirty-two dollars and a photograph of his daughter. He called the police from a nearby store.",
        voiceText: "Robert Miller, of the town of Denton, a truck driver for a local oil company, was walking home late one evening through a park when a young man stepped out from behind a tree and demanded his wallet. Robert gave him the wallet, which contained thirty-two dollars and a photograph of his daughter. He called the police from a nearby store.",
        scoringUnits: [
            "Robert", "Miller", "Denton", "truck driver", "oil company",
            "walking home", "late evening", "park", "young man",
            "behind a tree", "demanded", "wallet", "thirty-two dollars",
            "photograph", "daughter", "called police", "nearby store"
        ]
    ),
]

// MARK: - Qmci State

@Observable
class QmciState {
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

enum QmciClassification: String {
    case normal = "Normal Cognition"
    case mciProbable = "MCI Probable"
    case dementiaRange = "Dementia Range"
    var isPositive: Bool { self != .normal }
}

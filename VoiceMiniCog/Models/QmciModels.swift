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

/// Recall semantic substitution pair (e.g., patient said "puppy" for "dog").
struct SemanticSubstitution: Codable, Equatable {
    let target: String
    let substitution: String
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

// QMCI word sets — use alternates for repeat testing to reduce practice effects.
// Set 1 is from the published QMCI scoring sheet (O'Caoimh 2012).
// ⚠️ Sets 2 and 3 are APPROXIMATE — pending source confirmation from
// O'Caoimh or Cunje 2007 ("Alternative forms of logical memory and verbal
// fluency tasks for repeated testing", Int Psychogeriatr 2007).
// DO NOT use sets 2/3 in published research without verifying against
// the canonical alternate groupings.
let QMCI_WORD_LISTS: [[String]] = [
    ["dog", "rain", "butter", "love", "door"],       // Standard set (verified)
    ["cat", "dark", "rat", "heat", "bread"],          // Alternate set 2 (approximate)
    ["fear", "round", "bed", "chair", "fruit"],       // Alternate set 3 (approximate)
]

// MARK: - Logical Memory Stories

struct LogicalMemoryStory: Identifiable {
    let id: Int
    let text: String
    let voiceText: String
    let scoringUnits: [String]
    let maxScore: Int = 30
}

// Validated QMCI Logical Memory stories — verbatim recall only, 2 pts per content unit.
// Use alternates for repeat testing to reduce practice effects.
//
// Scoring units are MULTI-WORD PHRASES per O'Caoimh 2012 Appendix 1. The scorer
// must match the full phrase (fuzzy), not just the head noun. 15 units × 2 pts = 30.
let LOGICAL_MEMORY_STORIES: [LogicalMemoryStory] = [
    // Story 0 — Red Fox (O'Caoimh & Molloy QMCI scoring sheet, Appendix 1)
    LogicalMemoryStory(
        id: 0,
        text: "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes.",
        voiceText: "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes.",
        scoringUnits: [
            "the red", "fox", "ran across", "the ploughed", "field",
            "it was chased by", "a brown", "dog",
            "it was a hot", "may", "morning",
            "fragrant", "blossoms", "were forming on", "the bushes"
        ]
    ),
    // Story 1 — Brown Dog (parallel structure from Appendix 1)
    LogicalMemoryStory(
        id: 1,
        text: "The brown dog ran across the metal bridge. It was a cold October day. It was hunting a white rabbit. The ripe apples were hanging on the trees.",
        voiceText: "The brown dog ran across the metal bridge. It was a cold October day. It was hunting a white rabbit. The ripe apples were hanging on the trees.",
        scoringUnits: [
            "the brown", "dog", "ran across", "the metal", "bridge",
            "it was a cold", "october", "day",
            "it was hunting", "a white", "rabbit",
            "the ripe", "apples", "were hanging on", "the trees"
        ]
    ),
    // Story 2 — White Hen (parallel structure from Appendix 1)
    LogicalMemoryStory(
        id: 2,
        text: "The white hen walked across the concrete road. It was a warm September afternoon. It was followed by a black cat. The dry leaves were blowing in the wind.",
        voiceText: "The white hen walked across the concrete road. It was a warm September afternoon. It was followed by a black cat. The dry leaves were blowing in the wind.",
        scoringUnits: [
            "the white", "hen", "walked across", "the concrete", "road",
            "it was a warm", "september", "afternoon",
            "it was followed by", "a black", "cat",
            "the dry", "leaves", "were blowing in", "the wind"
        ]
    ),
]

// MARK: - Report Readiness

enum ReportReadiness: String, Codable {
    case notReady
    case pendingClinician
    case complete
    case finalized
}

// MARK: - Clinical Decision Enums

enum WorkupDecision: String, Codable, CaseIterable {
    case yes         = "Recommend Workup"
    case no          = "No Workup Indicated"
    case deferRepeat = "Defer — Repeat Testing First"
}

enum RepeatInterval: String, Codable, CaseIterable {
    case sixMonths    = "6 Months"
    case twelveMonths = "12 Months"
    case twentyFourMonths = "24 Months"
    case none         = "None"
}

// MARK: - Clinical Risk Signals (computed, not persisted)

struct ClinicalRiskSignal {
    let domain: String
    let finding: String
    let severity: Severity

    enum Severity: String {
        case info = "Info"
        case warning = "Warning"
        case critical = "Critical"
    }
}

struct ICD10Suggestion {
    let code: String
    let description: String
    let rationale: String
}

// MARK: - Qmci State

@Observable
final class QmciState: Codable {
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

    // MARK: - Spec-required session + capture fields

    /// Coupled test version — keeps `registrationWordListIndex` and
    /// `logicalMemoryStoryIndex` in sync so the same version number
    /// identifies the administered word list and story pair.
    var testVersion: TestVersion = .v1

    var sessionID: UUID = UUID()
    var sessionDateTime: Date = Date()

    /// Raw patient text per orientation question (index-aligned with `orientationScores`).
    var orientationResponses: [String] = Array(repeating: "", count: 5)
    /// True if the patient provided any response to the question at that index.
    var orientationAttempted: [Bool] = Array(repeating: false, count: 5)

    /// Per-trial recalled words for the 3 registration trials.
    var registrationTrialWords: [[String]] = [[], [], []]

    /// Registration telemetry: first-word latency on trial 1 (seconds from listening start to first correct word).
    var registrationFirstWordLatency: TimeInterval? = nil
    /// Registration telemetry: non-target words the patient said (raw).
    var registrationIntrusions: [String] = []
    /// Registration telemetry: count of repeated target words across all trials.
    var registrationRepetitionCount: Int = 0
    /// Registration telemetry: total phase duration in seconds.
    var registrationPhaseDuration: TimeInterval? = nil
    /// Registration telemetry: true if the 4-minute ceiling was hit.
    var registrationCeilingHit: Bool = false

    // MARK: - Delayed Recall Telemetry

    var recallFirstWordLatencyMs: Int? = nil
    var recallInterWordIntervalsMs: [Int] = []
    var recallIntrusionCount: Int { recallIntrusions.count }
    var recallIntrusions: [String] = []
    var recallSemanticSubstitutions: [SemanticSubstitution] = []
    var recallSemanticSubstitutionCount: Int { recallSemanticSubstitutions.count }
    var recallTotalPhaseDurationMs: Int = 0
    var recallSilenceBeforePromptMs: Int = 0
    var recallAnyOthersPromptUsed: Bool = false
    var recallASRDetectedWords: [String] = []
    var recallClinicianOverrides: [String: Bool] = [:]

    /// Full verbatim list of animals named INCLUDING duplicates. Distinct from
    /// `verbalFluencyWords` which is the unique/scored list.
    var fluencyAnimalsNamed: [String] = []

    /// Verbal fluency telemetry
    var fluencyRepetitions: [String] = []
    var fluencyIntrusions: [String] = []
    var fluencySuperordinateCount: Int = 0
    var fluencyFirstWordLatency: TimeInterval? = nil
    var fluencyMeanInterWordInterval: TimeInterval? = nil
    var fluencyQuartileCounts: [Int] = [0, 0, 0, 0]  // 4 × 15s bins
    var fluencyMeanClusterSize: Double? = nil
    var fluencySwitchCount: Int = 0
    var fluencyRePromptUsed: Bool = false
    var fluencyPhaseDuration: TimeInterval? = nil

    /// PNG-encoded clock image bytes (UIImage is not Codable, so store Data).
    var clockDrawingImagePNG: Data? = nil
    var clockStrokeEvents: [ClockStrokeEvent] = []
    var clockPauseEvents: [ClockPauseEvent] = []
    var clockScoreOverrideBy: String? = nil
    var clockScoreOverrideTimestamp: Date? = nil

    var clinicianDecisionWorkup: WorkupDecision? = nil
    var clinicianDecisionRepeat: RepeatInterval? = nil
    var clinicianDecisionTimestamp: Date? = nil

    /// Free-text clinical notes entered by the clinician in the report view.
    var aiObservations: [String] = []

    /// Explicit clinician confirmation that the clock drawing has been reviewed
    /// and scored. Separates "not yet scored" from "scored 0/15" — without this,
    /// severely impaired patients (legitimate 0/15) would block report finalization.
    var cdtReviewed: Bool = false

    var reportReadiness: ReportReadiness {
        guard isComplete else { return .notReady }
        guard cdtReviewed, clinicianDecisionWorkup != nil else {
            return .pendingClinician
        }
        return .complete
    }

    var pendingReviewCount: Int {
        var count = 0
        if !cdtReviewed { count += 1 }
        if clinicianDecisionWorkup == nil { count += 1 }
        return count
    }

    // MARK: - Computed Clinical Signals (not persisted)

    var riskSignals: [ClinicalRiskSignal] {
        var signals: [ClinicalRiskSignal] = []

        if totalScore < 54 {
            signals.append(ClinicalRiskSignal(
                domain: "Global Cognition",
                finding: "QMCI score \(totalScore)/100 falls in dementia range (<54)",
                severity: .critical
            ))
        } else if totalScore < 67 {
            signals.append(ClinicalRiskSignal(
                domain: "Global Cognition",
                finding: "QMCI score \(totalScore)/100 suggests possible MCI (54-66)",
                severity: .warning
            ))
        }

        if delayedRecallScore <= 4 {
            signals.append(ClinicalRiskSignal(
                domain: "Memory",
                finding: "Delayed recall \(delayedRecallScore)/20 — significant encoding deficit",
                severity: .critical
            ))
        } else if delayedRecallScore <= 8 {
            signals.append(ClinicalRiskSignal(
                domain: "Memory",
                finding: "Delayed recall \(delayedRecallScore)/20 — below expected",
                severity: .warning
            ))
        }

        if effectiveClockDrawingScore <= 5 {
            signals.append(ClinicalRiskSignal(
                domain: "Visuospatial/Executive",
                finding: "Clock drawing \(effectiveClockDrawingScore)/15 — significant impairment",
                severity: .critical
            ))
        } else if effectiveClockDrawingScore <= 10 {
            signals.append(ClinicalRiskSignal(
                domain: "Visuospatial/Executive",
                finding: "Clock drawing \(effectiveClockDrawingScore)/15 — below expected",
                severity: .warning
            ))
        }

        if verbalFluencyScore <= 8 {
            signals.append(ClinicalRiskSignal(
                domain: "Language/Executive",
                finding: "Verbal fluency \(verbalFluencyScore)/20 — reduced word generation",
                severity: .warning
            ))
        }

        return signals
    }

    var icd10Suggestion: ICD10Suggestion {
        switch classification {
        case .dementiaRange:
            return ICD10Suggestion(
                code: "G31.84",
                description: "Mild cognitive impairment, so stated",
                rationale: "QMCI \(totalScore)/100, dementia range. Confirm with comprehensive evaluation."
            )
        case .mciProbable:
            return ICD10Suggestion(
                code: "G31.84",
                description: "Mild cognitive impairment, so stated",
                rationale: "QMCI \(totalScore)/100, MCI range. Screen positive — further evaluation recommended."
            )
        case .normal:
            return ICD10Suggestion(
                code: "R41.81",
                description: "Age-related cognitive decline",
                rationale: "QMCI \(totalScore)/100, normal range. Routine follow-up per clinical judgment."
            )
        }
    }

    // MARK: - QMCI 15-point Clock Drawing (manual clinician scoring)
    //
    // QMCI protocol rubric for clock drawing (max 15 points):
    //   • 1 point per correctly placed number (1-12)            → 12 pts max
    //   • Hands: 0 = neither correct, 1 = one correct, 2 = both correct
    //     (hour toward 11 AND minute toward 2 for "ten past eleven")  → 2 pts max
    //   • 1 point for pivot (center point where hands meet)     → 1 pt
    //   • -1 per duplicate number or number > 12
    //   Per O'Caoimh 2012 Appendix 1 rubric.
    //
    // Populated by the clinician in the PCP Report view. Call
    // `recomputeClockDrawingScore()` after mutating any cdt* field to
    // refresh `clockDrawingScore`.
    var cdtNumbersPlaced: [Bool] = Array(repeating: false, count: 12)
    /// 0 = neither hand correct, 1 = one hand correct, 2 = both hands correct
    var cdtHandsScore: Int = 0
    var cdtPivotCorrect: Bool = false
    var cdtInvalidNumbersCount: Int = 0

    /// QMCI 15-point clock drawing score computed from detailed fields.
    /// Clamped to 0...15.
    var cdtComputedScore: Int {
        let numberPoints = cdtNumbersPlaced.filter { $0 }.count
        let pivotPoint = cdtPivotCorrect ? 1 : 0
        let raw = numberPoints + min(cdtHandsScore, 2) + pivotPoint - cdtInvalidNumbersCount
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

    /// Number of trials needed to achieve full 5/5 registration (nil if never reached).
    /// Single-trial learning is preserved in normal aging; multi-trial requirement suggests encoding deficit.
    var trialsToFullRegistration: Int? {
        for (i, words) in registrationTrialWords.enumerated() {
            if words.count >= 5 { return i + 1 }
        }
        return nil
    }

    /// QMCI verbal fluency: 1 pt per unique animal, capped at 20.
    /// Per O'Caoimh 2012 Appendix 1 scoring rubric.
    var verbalFluencyScore: Int {
        min(Set(verbalFluencyWords.map { $0.lowercased() }).count, 20)
    }
    var logicalMemoryScore: Int { min(logicalMemoryRecalledUnits.count * 2, 30) }
    var delayedRecallScore: Int { min(delayedRecallWords.count * 4, 20) }

    /// True if any detailed clock-drawing field has been touched by the clinician.
    /// Used to decide whether to trust the computed cdt score vs. a legacy stored value.
    private var hasCDTFieldsSet: Bool {
        cdtNumbersPlaced.contains(true) ||
        cdtHandsScore > 0 || cdtPivotCorrect ||
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
    /// Record the clinician's clinical decision with timestamp.
    func recordClinicalDecision(workup: WorkupDecision, repeat interval: RepeatInterval?, note: String? = nil) {
        clinicianDecisionWorkup = workup
        clinicianDecisionRepeat = interval
        clinicianDecisionTimestamp = Date()
        if let note, !note.isEmpty {
            aiObservations.append(note)
        }
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
        case cdtNumbersPlaced, cdtHandsScore
        case cdtMinuteHandCorrect, cdtHourHandCorrect // legacy decode only
        case cdtPivotCorrect, cdtInvalidNumbersCount
        // New spec-required fields
        case testVersion
        case sessionID, sessionDateTime
        case orientationResponses, orientationAttempted
        case registrationTrialWords
        case registrationFirstWordLatency, registrationIntrusions
        case registrationRepetitionCount, registrationPhaseDuration, registrationCeilingHit
        // Delayed recall telemetry
        case recallFirstWordLatencyMs, recallInterWordIntervalsMs
        case recallIntrusionCount, recallIntrusions
        case recallSemanticSubstitutions, recallSemanticSubstitutionCount
        case recallTotalPhaseDurationMs, recallSilenceBeforePromptMs
        case recallAnyOthersPromptUsed
        case recallASRDetectedWords, recallClinicianOverrides
        case fluencyAnimalsNamed
        case fluencyRepetitions, fluencyIntrusions, fluencySuperordinateCount
        case fluencyFirstWordLatency, fluencyMeanInterWordInterval
        case fluencyQuartileCounts, fluencyMeanClusterSize, fluencySwitchCount
        case fluencyRePromptUsed, fluencyPhaseDuration
        case clockDrawingImagePNG, clockStrokeEvents, clockPauseEvents
        case clockScoreOverrideBy, clockScoreOverrideTimestamp
        case clinicianDecisionWorkup, clinicianDecisionRepeat, clinicianDecisionTimestamp
        case cdtReviewed
        case aiObservations
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
        // Prefer new cdtHandsScore; fall back to legacy Bool fields for migration
        if let hands = try c.decodeIfPresent(Int.self, forKey: .cdtHandsScore) {
            cdtHandsScore = hands
        } else {
            let minute = try c.decodeIfPresent(Bool.self, forKey: .cdtMinuteHandCorrect) ?? false
            let hour = try c.decodeIfPresent(Bool.self, forKey: .cdtHourHandCorrect) ?? false
            cdtHandsScore = (minute ? 1 : 0) + (hour ? 1 : 0)
        }
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
        registrationFirstWordLatency = try c.decodeIfPresent(TimeInterval.self, forKey: .registrationFirstWordLatency)
        registrationIntrusions = try c.decodeIfPresent([String].self, forKey: .registrationIntrusions) ?? []
        registrationRepetitionCount = try c.decodeIfPresent(Int.self, forKey: .registrationRepetitionCount) ?? 0
        registrationPhaseDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .registrationPhaseDuration)
        registrationCeilingHit = try c.decodeIfPresent(Bool.self, forKey: .registrationCeilingHit) ?? false
        // Delayed recall telemetry
        recallFirstWordLatencyMs = try c.decodeIfPresent(Int.self, forKey: .recallFirstWordLatencyMs)
        recallInterWordIntervalsMs = try c.decodeIfPresent([Int].self, forKey: .recallInterWordIntervalsMs) ?? []
        // recallIntrusionCount and recallSemanticSubstitutionCount are computed
        // from their respective arrays — CodingKeys retained for backward compat.
        recallIntrusions = try c.decodeIfPresent([String].self, forKey: .recallIntrusions) ?? []
        recallSemanticSubstitutions = try c.decodeIfPresent([SemanticSubstitution].self, forKey: .recallSemanticSubstitutions) ?? []
        recallTotalPhaseDurationMs = try c.decodeIfPresent(Int.self, forKey: .recallTotalPhaseDurationMs) ?? 0
        recallSilenceBeforePromptMs = try c.decodeIfPresent(Int.self, forKey: .recallSilenceBeforePromptMs) ?? 0
        recallAnyOthersPromptUsed = try c.decodeIfPresent(Bool.self, forKey: .recallAnyOthersPromptUsed) ?? false
        recallASRDetectedWords = try c.decodeIfPresent([String].self, forKey: .recallASRDetectedWords) ?? []
        recallClinicianOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .recallClinicianOverrides) ?? [:]
        fluencyAnimalsNamed = try c.decodeIfPresent([String].self, forKey: .fluencyAnimalsNamed) ?? []
        fluencyRepetitions = try c.decodeIfPresent([String].self, forKey: .fluencyRepetitions) ?? []
        fluencyIntrusions = try c.decodeIfPresent([String].self, forKey: .fluencyIntrusions) ?? []
        fluencySuperordinateCount = try c.decodeIfPresent(Int.self, forKey: .fluencySuperordinateCount) ?? 0
        fluencyFirstWordLatency = try c.decodeIfPresent(TimeInterval.self, forKey: .fluencyFirstWordLatency)
        fluencyMeanInterWordInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .fluencyMeanInterWordInterval)
        fluencyQuartileCounts = try c.decodeIfPresent([Int].self, forKey: .fluencyQuartileCounts) ?? [0, 0, 0, 0]
        fluencyMeanClusterSize = try c.decodeIfPresent(Double.self, forKey: .fluencyMeanClusterSize)
        fluencySwitchCount = try c.decodeIfPresent(Int.self, forKey: .fluencySwitchCount) ?? 0
        fluencyRePromptUsed = try c.decodeIfPresent(Bool.self, forKey: .fluencyRePromptUsed) ?? false
        fluencyPhaseDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .fluencyPhaseDuration)
        clockDrawingImagePNG = try c.decodeIfPresent(Data.self, forKey: .clockDrawingImagePNG)
        clockStrokeEvents = try c.decodeIfPresent([ClockStrokeEvent].self, forKey: .clockStrokeEvents) ?? []
        clockPauseEvents = try c.decodeIfPresent([ClockPauseEvent].self, forKey: .clockPauseEvents) ?? []
        clockScoreOverrideBy = try c.decodeIfPresent(String.self, forKey: .clockScoreOverrideBy)
        clockScoreOverrideTimestamp = try c.decodeIfPresent(Date.self, forKey: .clockScoreOverrideTimestamp)
        // cdtReviewed (new field, default false for old data)
        cdtReviewed = try c.decodeIfPresent(Bool.self, forKey: .cdtReviewed) ?? false

        // Clinical decisions — backward-compatible: try new enum first, fall back to legacy Bool
        if let decision = try? c.decodeIfPresent(WorkupDecision.self, forKey: .clinicianDecisionWorkup) {
            clinicianDecisionWorkup = decision
        } else if let legacy = try? c.decodeIfPresent(Bool.self, forKey: .clinicianDecisionWorkup) {
            clinicianDecisionWorkup = legacy ? .yes : .no
        } else {
            clinicianDecisionWorkup = nil
        }

        if let interval = try? c.decodeIfPresent(RepeatInterval.self, forKey: .clinicianDecisionRepeat) {
            clinicianDecisionRepeat = interval
        } else if let legacy = try? c.decodeIfPresent(Bool.self, forKey: .clinicianDecisionRepeat) {
            clinicianDecisionRepeat = legacy ? .twelveMonths : RepeatInterval.none
        } else {
            clinicianDecisionRepeat = nil
        }

        clinicianDecisionTimestamp = try c.decodeIfPresent(Date.self, forKey: .clinicianDecisionTimestamp)
        aiObservations = try c.decodeIfPresent([String].self, forKey: .aiObservations) ?? []
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
        try c.encode(cdtHandsScore, forKey: .cdtHandsScore)
        try c.encode(cdtPivotCorrect, forKey: .cdtPivotCorrect)
        try c.encode(cdtInvalidNumbersCount, forKey: .cdtInvalidNumbersCount)
        // New spec-required fields
        try c.encode(testVersion, forKey: .testVersion)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(sessionDateTime, forKey: .sessionDateTime)
        try c.encode(orientationResponses, forKey: .orientationResponses)
        try c.encode(orientationAttempted, forKey: .orientationAttempted)
        try c.encode(registrationTrialWords, forKey: .registrationTrialWords)
        try c.encodeIfPresent(registrationFirstWordLatency, forKey: .registrationFirstWordLatency)
        try c.encode(registrationIntrusions, forKey: .registrationIntrusions)
        try c.encode(registrationRepetitionCount, forKey: .registrationRepetitionCount)
        try c.encodeIfPresent(registrationPhaseDuration, forKey: .registrationPhaseDuration)
        try c.encode(registrationCeilingHit, forKey: .registrationCeilingHit)
        // Delayed recall telemetry
        try c.encodeIfPresent(recallFirstWordLatencyMs, forKey: .recallFirstWordLatencyMs)
        try c.encode(recallInterWordIntervalsMs, forKey: .recallInterWordIntervalsMs)
        try c.encode(recallIntrusionCount, forKey: .recallIntrusionCount)
        try c.encode(recallIntrusions, forKey: .recallIntrusions)
        try c.encode(recallSemanticSubstitutions, forKey: .recallSemanticSubstitutions)
        try c.encode(recallSemanticSubstitutionCount, forKey: .recallSemanticSubstitutionCount)
        try c.encode(recallTotalPhaseDurationMs, forKey: .recallTotalPhaseDurationMs)
        try c.encode(recallSilenceBeforePromptMs, forKey: .recallSilenceBeforePromptMs)
        try c.encode(recallAnyOthersPromptUsed, forKey: .recallAnyOthersPromptUsed)
        try c.encode(recallASRDetectedWords, forKey: .recallASRDetectedWords)
        try c.encode(recallClinicianOverrides, forKey: .recallClinicianOverrides)
        try c.encode(fluencyAnimalsNamed, forKey: .fluencyAnimalsNamed)
        try c.encode(fluencyRepetitions, forKey: .fluencyRepetitions)
        try c.encode(fluencyIntrusions, forKey: .fluencyIntrusions)
        try c.encode(fluencySuperordinateCount, forKey: .fluencySuperordinateCount)
        try c.encodeIfPresent(fluencyFirstWordLatency, forKey: .fluencyFirstWordLatency)
        try c.encodeIfPresent(fluencyMeanInterWordInterval, forKey: .fluencyMeanInterWordInterval)
        try c.encode(fluencyQuartileCounts, forKey: .fluencyQuartileCounts)
        try c.encodeIfPresent(fluencyMeanClusterSize, forKey: .fluencyMeanClusterSize)
        try c.encode(fluencySwitchCount, forKey: .fluencySwitchCount)
        try c.encode(fluencyRePromptUsed, forKey: .fluencyRePromptUsed)
        try c.encodeIfPresent(fluencyPhaseDuration, forKey: .fluencyPhaseDuration)
        try c.encodeIfPresent(clockDrawingImagePNG, forKey: .clockDrawingImagePNG)
        try c.encode(clockStrokeEvents, forKey: .clockStrokeEvents)
        try c.encode(clockPauseEvents, forKey: .clockPauseEvents)
        try c.encodeIfPresent(clockScoreOverrideBy, forKey: .clockScoreOverrideBy)
        try c.encodeIfPresent(clockScoreOverrideTimestamp, forKey: .clockScoreOverrideTimestamp)
        try c.encode(cdtReviewed, forKey: .cdtReviewed)
        try c.encodeIfPresent(clinicianDecisionWorkup, forKey: .clinicianDecisionWorkup)
        try c.encodeIfPresent(clinicianDecisionRepeat, forKey: .clinicianDecisionRepeat)
        try c.encodeIfPresent(clinicianDecisionTimestamp, forKey: .clinicianDecisionTimestamp)
        try c.encode(aiObservations, forKey: .aiObservations)
    }

    init() { selectTestVersion() }

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
        verbalFluencyWords = []; verbalFluencyTranscript = ""; verbalFluencyDurationSec = 60
        logicalMemoryRecalledUnits = []; logicalMemoryTranscript = ""
        delayedRecallWords = []; delayedRecallTranscript = ""
        completedSubtests = []; isComplete = false; clockDrawingScore = 0
        cdtNumbersPlaced = Array(repeating: false, count: 12)
        cdtHandsScore = 0
        cdtPivotCorrect = false
        cdtInvalidNumbersCount = 0

        // New spec-required fields
        testVersion = .v1
        sessionID = UUID()
        sessionDateTime = Date()
        orientationResponses = Array(repeating: "", count: 5)
        orientationAttempted = Array(repeating: false, count: 5)
        registrationTrialWords = [[], [], []]
        registrationFirstWordLatency = nil
        registrationIntrusions = []
        registrationRepetitionCount = 0
        registrationPhaseDuration = nil
        registrationCeilingHit = false
        // Delayed recall telemetry
        recallFirstWordLatencyMs = nil
        recallInterWordIntervalsMs = []
        recallIntrusions = []
        recallSemanticSubstitutions = []
        recallTotalPhaseDurationMs = 0
        recallSilenceBeforePromptMs = 0
        recallAnyOthersPromptUsed = false
        recallASRDetectedWords = []
        recallClinicianOverrides = [:]
        fluencyAnimalsNamed = []
        fluencyRepetitions = []
        fluencyIntrusions = []
        fluencySuperordinateCount = 0
        fluencyFirstWordLatency = nil
        fluencyMeanInterWordInterval = nil
        fluencyQuartileCounts = [0, 0, 0, 0]
        fluencyMeanClusterSize = nil
        fluencySwitchCount = 0
        fluencyRePromptUsed = false
        fluencyPhaseDuration = nil
        clockDrawingImagePNG = nil
        clockStrokeEvents = []
        clockPauseEvents = []
        clockScoreOverrideBy = nil
        clockScoreOverrideTimestamp = nil
        cdtReviewed = false
        clinicianDecisionWorkup = nil
        clinicianDecisionRepeat = nil
        clinicianDecisionTimestamp = nil
        aiObservations = []

        selectTestVersion()
    }
}

enum QmciClassification: String, Codable {
    case normal = "Normal Cognition"
    case mciProbable = "MCI Probable"
    case dementiaRange = "Dementia Range"
    var isPositive: Bool { self != .normal }
}

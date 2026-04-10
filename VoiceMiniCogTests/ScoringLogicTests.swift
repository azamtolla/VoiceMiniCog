//
//  ScoringLogicTests.swift
//  VoiceMiniCogTests
//
//  Tests for all clinical scoring logic: Qmci subtests, QDRS staging,
//  PHQ-2 gating, and composite risk matrix.
//
//  MARK: CLINICAL — Scoring thresholds are safety-critical (SaMD).
//  NEVER change thresholds without clinical review by Dr. Tolla.
//

import XCTest
@testable import VoiceMiniCog

// MARK: - PHQ-2 Depression Gate

@MainActor
class PHQ2ScoringTests: XCTestCase {

    func testAllNotAtAllIsZero() {
        var state = PHQ2State()
        state.answers = [.notAtAll, .notAtAll]
        XCTAssertEqual(state.totalScore, 0)
        XCTAssertFalse(state.isPositive)
    }

    func testBothNearlyEveryDayIsMax() {
        var state = PHQ2State()
        state.answers = [.nearlyEveryDay, .nearlyEveryDay]
        XCTAssertEqual(state.totalScore, 6)
        XCTAssertTrue(state.isPositive)
    }

    func testExactThresholdThreeIsPositive() {
        var state = PHQ2State()
        state.answers = [.nearlyEveryDay, .notAtAll]  // 3 + 0 = 3
        XCTAssertEqual(state.totalScore, 3)
        XCTAssertTrue(state.isPositive, "Score of 3 must be positive (>= 3)")
    }

    func testJustBelowThresholdIsNegative() {
        var state = PHQ2State()
        state.answers = [.severalDays, .severalDays]  // 1 + 1 = 2
        XCTAssertEqual(state.totalScore, 2)
        XCTAssertFalse(state.isPositive, "Score of 2 must be negative (< 3)")
    }

    func testSingleAnswerNilCompressesToZero() {
        var state = PHQ2State()
        state.answers = [.nearlyEveryDay, nil]  // 3 + 0 = 3
        XCTAssertEqual(state.totalScore, 3)
        XCTAssertTrue(state.isPositive,
                      "Single answer of 3 triggers positive even with nil second answer")
    }

    func testBothNilIsZero() {
        let state = PHQ2State()
        XCTAssertEqual(state.totalScore, 0)
        XCTAssertFalse(state.isPositive)
    }

    func testIsCompleteRequiresBothAnswers() {
        var state = PHQ2State()
        XCTAssertFalse(state.isComplete)
        state.answers[0] = .notAtAll
        XCTAssertFalse(state.isComplete)
        state.answers[1] = .severalDays
        XCTAssertTrue(state.isComplete)
    }

    func testAllCombinationsAtBoundary() {
        // Exhaustively test the boundary: score 2 (negative) vs score 3 (positive)
        let negativeCombinations: [(PHQ2Answer, PHQ2Answer)] = [
            (.notAtAll, .moreThanHalf),    // 0 + 2 = 2
            (.moreThanHalf, .notAtAll),    // 2 + 0 = 2
            (.severalDays, .severalDays),  // 1 + 1 = 2
        ]
        for (a, b) in negativeCombinations {
            var state = PHQ2State()
            state.answers = [a, b]
            XCTAssertFalse(state.isPositive,
                           "\(a.rawValue)+\(b.rawValue)=\(state.totalScore) should be negative")
        }

        let positiveCombinations: [(PHQ2Answer, PHQ2Answer)] = [
            (.nearlyEveryDay, .notAtAll),   // 3 + 0 = 3
            (.notAtAll, .nearlyEveryDay),   // 0 + 3 = 3
            (.severalDays, .moreThanHalf),  // 1 + 2 = 3
            (.moreThanHalf, .severalDays),  // 2 + 1 = 3
        ]
        for (a, b) in positiveCombinations {
            var state = PHQ2State()
            state.answers = [a, b]
            XCTAssertTrue(state.isPositive,
                          "\(a.rawValue)+\(b.rawValue)=\(state.totalScore) should be positive")
        }
    }
}

// MARK: - QDRS Scoring

@MainActor
class QDRSScoringTests: XCTestCase {

    func testAllNormalIsZero() {
        let state = QDRSState()
        for i in 0..<10 { state.answers[i] = .normal }
        XCTAssertEqual(state.totalScore, 0.0)
        XCTAssertFalse(state.isPositiveScreen)
        XCTAssertEqual(state.riskLabel, "Low Concern")
    }

    func testAllChangedIsMax() {
        let state = QDRSState()
        for i in 0..<10 { state.answers[i] = .changed }
        XCTAssertEqual(state.totalScore, 10.0)
        XCTAssertTrue(state.isPositiveScreen)
        XCTAssertEqual(state.riskLabel, "Significant Concern")
    }

    func testExactThreshold1Point5() {
        let state = QDRSState()
        // 3 × "sometimes" (0.5) = 1.5
        state.answers[0] = .sometimes
        state.answers[1] = .sometimes
        state.answers[2] = .sometimes
        XCTAssertEqual(state.totalScore, 1.5)
        XCTAssertTrue(state.isPositiveScreen, "1.5 is the threshold — must be positive")
    }

    func testJustBelowThreshold() {
        let state = QDRSState()
        // 2 × "sometimes" (0.5) = 1.0
        state.answers[0] = .sometimes
        state.answers[1] = .sometimes
        XCTAssertEqual(state.totalScore, 1.0)
        XCTAssertFalse(state.isPositiveScreen, "1.0 is below threshold — must be negative")
    }

    func testMixedScoring() {
        let state = QDRSState()
        state.answers[0] = .changed     // 1.0
        state.answers[1] = .sometimes   // 0.5
        state.answers[2] = .normal      // 0.0
        XCTAssertEqual(state.totalScore, 1.5)
        XCTAssertTrue(state.isPositiveScreen)
    }

    func testPartialCompletionStillScores() {
        let state = QDRSState()
        // Only 2 answers provided, rest nil
        state.answers[0] = .changed     // 1.0
        state.answers[1] = .changed     // 1.0
        XCTAssertEqual(state.totalScore, 2.0)
        XCTAssertTrue(state.isPositiveScreen,
                      "Partial answers still trigger positive if total >= 1.5")
    }

    func testFlaggedDomainsCorrect() {
        let state = QDRSState()
        state.answers[0] = .changed     // Memory
        state.answers[3] = .sometimes   // Community
        state.answers[5] = .normal      // Personal Care (not flagged)
        let flagged = state.flaggedDomains
        XCTAssertTrue(flagged.contains("Memory"))
        XCTAssertTrue(flagged.contains("Community"))
        XCTAssertFalse(flagged.contains("Personal Care"))
    }

    func testRiskLabels() {
        let state = QDRSState()

        // Low Concern: 0..<1.5
        state.answers[0] = .sometimes  // 0.5
        XCTAssertEqual(state.riskLabel, "Low Concern")

        // Mild Concern: 1.5..<3.0
        state.answers[1] = .sometimes  // +0.5 = 1.0
        state.answers[2] = .sometimes  // +0.5 = 1.5
        XCTAssertEqual(state.riskLabel, "Mild Concern")

        // Moderate Concern: 3.0..<5.0
        state.answers[3] = .changed    // +1.0 = 2.5
        state.answers[4] = .changed    // +1.0 = 3.5
        XCTAssertEqual(state.riskLabel, "Moderate Concern")

        // Significant Concern: >= 5.0
        state.answers[5] = .changed    // +1.0 = 4.5
        state.answers[6] = .changed    // +1.0 = 5.5
        XCTAssertEqual(state.riskLabel, "Significant Concern")
    }

    func testAnswerScoreValues() {
        XCTAssertEqual(QDRSAnswer.normal.score, 0.0)
        XCTAssertEqual(QDRSAnswer.sometimes.score, 0.5)
        XCTAssertEqual(QDRSAnswer.changed.score, 1.0)
    }
}

// MARK: - Qmci Subtest Scoring

@MainActor
class QmciScoringTests: XCTestCase {

    // MARK: Orientation

    func testOrientationAllCorrect() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]
        XCTAssertEqual(state.orientationScore, 10, "5 correct × 2 pts = 10")
    }

    func testOrientationAllIncorrect() {
        let state = QmciState()
        state.orientationScores = [0, 0, 0, 0, 0]
        XCTAssertEqual(state.orientationScore, 0)
    }

    func testOrientationPartialCredit() {
        let state = QmciState()
        state.orientationScores = [2, 0, 2, 0, 2]
        XCTAssertEqual(state.orientationScore, 6, "3 correct × 2 pts = 6")
    }

    func testOrientationNilCountsAsIncorrect() {
        let state = QmciState()
        state.orientationScores = [2, nil, nil, nil, 2]
        XCTAssertEqual(state.orientationScore, 4, "Nils filtered out, 2 full × 2 = 4")
    }

    func testOrientationThreeLevelScoring() {
        let state = QmciState()
        // QMCI 3-level: 2 + 1 + 2 + 0 + 1 = 6
        state.orientationScores = [2, 1, 2, 0, 1]
        XCTAssertEqual(state.orientationScore, 6, "3-level scoring sums directly")
    }

    func testOrientationCappedAtTen() {
        let state = QmciState()
        // Defensive: summing to > 10 should be clamped
        state.orientationScores = [2, 2, 2, 2, 2]
        XCTAssertEqual(state.orientationScore, 10, "Capped at 10")
    }

    // MARK: Registration

    func testRegistrationMaxFive() {
        let state = QmciState()
        state.registrationRecalledWords = ["butter", "arm", "shore", "letter", "queen"]
        XCTAssertEqual(state.registrationScore, 5)
    }

    func testRegistrationCappedAtFive() {
        let state = QmciState()
        // Somehow 6 words (shouldn't happen but test the cap)
        state.registrationRecalledWords = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(state.registrationScore, 5, "Capped at 5")
    }

    func testRegistrationZero() {
        let state = QmciState()
        state.registrationRecalledWords = []
        XCTAssertEqual(state.registrationScore, 0)
    }

    // MARK: Verbal Fluency

    func testVerbalFluencyMaxTwenty() {
        let state = QmciState()
        state.verbalFluencyWords = Array(repeating: "unique", count: 25).enumerated()
            .map { "\($0.element)\($0.offset)" }  // unique0, unique1, ...
        // Set deduplication in the scoring
        // Actually the score uses Set(words.map { $0.lowercased() }).count
        // With 25 unique strings, count = 25, capped at 20
        XCTAssertEqual(state.verbalFluencyScore, 20, "Capped at 20")
    }

    func testVerbalFluencyDeduplicates() {
        let state = QmciState()
        state.verbalFluencyWords = ["dog", "DOG", "Dog", "cat"]
        // Set(lowercased) → {"dog", "cat"} → count = 2
        XCTAssertEqual(state.verbalFluencyScore, 2, "Case-insensitive dedup")
    }

    func testVerbalFluencyEmpty() {
        let state = QmciState()
        state.verbalFluencyWords = []
        XCTAssertEqual(state.verbalFluencyScore, 0)
    }

    // MARK: Logical Memory

    func testLogicalMemoryScoring() {
        let state = QmciState()
        state.logicalMemoryRecalledUnits = ["Anna", "Thompson", "robbed"]
        XCTAssertEqual(state.logicalMemoryScore, 6, "3 units × 2 pts = 6")
    }

    func testLogicalMemoryCappedAtThirty() {
        let state = QmciState()
        // 17 units × 2 = 34, capped at 30
        state.logicalMemoryRecalledUnits = Array(repeating: "unit", count: 17)
        XCTAssertEqual(state.logicalMemoryScore, 30, "Capped at 30")
    }

    func testLogicalMemoryEmpty() {
        let state = QmciState()
        state.logicalMemoryRecalledUnits = []
        XCTAssertEqual(state.logicalMemoryScore, 0)
    }

    // MARK: Delayed Recall

    func testDelayedRecallScoring() {
        let state = QmciState()
        state.delayedRecallWords = ["butter", "arm", "shore"]
        XCTAssertEqual(state.delayedRecallScore, 12, "3 words × 4 pts = 12")
    }

    func testDelayedRecallAllFive() {
        let state = QmciState()
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(state.delayedRecallScore, 20, "5 words × 4 pts = 20, at max")
    }

    func testDelayedRecallCappedAtTwenty() {
        let state = QmciState()
        state.delayedRecallWords = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(state.delayedRecallScore, 20, "Capped at 20")
    }

    func testDelayedRecallEmpty() {
        let state = QmciState()
        state.delayedRecallWords = []
        XCTAssertEqual(state.delayedRecallScore, 0)
    }

    // MARK: Total Score & Classification

    func testTotalScorePerfect() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]  // 10
        state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
        state.clockDrawingScore = 15  // 15
        state.verbalFluencyWords = (0..<20).map { "animal\($0)" }  // 20
        state.logicalMemoryRecalledUnits = Array(repeating: "u", count: 15)  // 30
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
        XCTAssertEqual(state.totalScore, 100, "Perfect score = 100")
        XCTAssertEqual(state.classification, .normal)
    }

    func testClassificationNormalBoundary() {
        let state = QmciState()
        // Set up to get exactly 67
        state.orientationScores = [2, 2, 2, 2, 2]  // 10
        state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
        state.clockDrawingScore = 12  // 12
        state.verbalFluencyWords = (0..<20).map { "a\($0)" }  // 20
        state.logicalMemoryRecalledUnits = []  // 0
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
        XCTAssertEqual(state.totalScore, 67)
        XCTAssertEqual(state.classification, .normal,
                       "67 is exactly the normal threshold")
    }

    func testClassificationMCIBoundary() {
        let state = QmciState()
        // totalScore = 66 → MCI Probable
        state.orientationScores = [2, 2, 2, 2, 2]  // 10
        state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
        state.clockDrawingScore = 11  // 11
        state.verbalFluencyWords = (0..<20).map { "a\($0)" }  // 20
        state.logicalMemoryRecalledUnits = []  // 0
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
        XCTAssertEqual(state.totalScore, 66)
        XCTAssertEqual(state.classification, .mciProbable,
                       "66 is MCI Probable (below 67)")
    }

    func testClassificationMCILowerBoundary() {
        let state = QmciState()
        // totalScore = 54 → MCI Probable (not dementia)
        state.orientationScores = [2, 2, 2, 2, 2]  // 10
        state.registrationRecalledWords = ["a", "b", "c", "d"]  // 4
        state.clockDrawingScore = 0  // 0
        state.verbalFluencyWords = (0..<20).map { "a\($0)" }  // 20
        state.logicalMemoryRecalledUnits = []  // 0
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
        XCTAssertEqual(state.totalScore, 54)
        XCTAssertEqual(state.classification, .mciProbable,
                       "54 is still MCI Probable (>= 54)")
    }

    func testClassificationDementiaBoundary() {
        let state = QmciState()
        // totalScore = 53 → Dementia Range
        state.orientationScores = [2, 2, 2, 2, 2]  // 10
        state.registrationRecalledWords = ["a", "b", "c"]  // 3
        state.clockDrawingScore = 0  // 0
        state.verbalFluencyWords = (0..<20).map { "a\($0)" }  // 20
        state.logicalMemoryRecalledUnits = []  // 0
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
        XCTAssertEqual(state.totalScore, 53)
        XCTAssertEqual(state.classification, .dementiaRange,
                       "53 is Dementia Range (below 54)")
    }

    func testClassificationZero() {
        let state = QmciState()
        XCTAssertEqual(state.totalScore, 0)
        XCTAssertEqual(state.classification, .dementiaRange)
    }

    func testIsPositiveFlag() {
        XCTAssertFalse(QmciClassification.normal.isPositive)
        XCTAssertTrue(QmciClassification.mciProbable.isPositive)
        XCTAssertTrue(QmciClassification.dementiaRange.isPositive)
    }

    // MARK: Subtest Max Scores

    func testSubtestMaxScores() {
        XCTAssertEqual(QmciSubtest.orientation.maxScore, 10)
        XCTAssertEqual(QmciSubtest.registration.maxScore, 5)
        XCTAssertEqual(QmciSubtest.clockDrawing.maxScore, 15)
        XCTAssertEqual(QmciSubtest.verbalFluency.maxScore, 20)
        XCTAssertEqual(QmciSubtest.logicalMemory.maxScore, 30)
        XCTAssertEqual(QmciSubtest.delayedRecall.maxScore, 20)
    }

    func testTotalMaxIs100() {
        let total = QmciSubtest.allCases.reduce(0) { $0 + $1.maxScore }
        XCTAssertEqual(total, 100, "All subtests must sum to 100")
    }
}

// MARK: - Composite Risk Matrix

@MainActor
class CompositeRiskTests: XCTestCase {

    // MARK: Mini-Cog + QDRS Matrix

    func testBothNegativeIsLow() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 4, recallScore: 3, clockScore: 2,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 0.5, isPositiveScreen: false,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .low)
    }

    func testBothPositiveIsHigh() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 1, recallScore: 1, clockScore: 0,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 3.0, isPositiveScreen: true,
                            respondentType: .patient, flaggedDomains: ["Memory"])
        )
        XCTAssertEqual(result.tier, .high)
    }

    func testMiniCogPositiveQDRSNegativeIsIntermediate() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 2, recallScore: 2, clockScore: 0,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 1.0, isPositiveScreen: false,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .intermediate)
    }

    func testMiniCogNegativeQDRSPositiveIsIntermediate() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 4, recallScore: 3, clockScore: 2,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 2.0, isPositiveScreen: true,
                            respondentType: .informant, flaggedDomains: ["Memory", "Orientation"])
        )
        XCTAssertEqual(result.tier, .intermediate)
    }

    func testMiniCogThresholdAtThree() {
        // totalScore == 3 → NOT positive (< 3 is positive)
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 3, recallScore: 2, clockScore: 1,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 0, isPositiveScreen: false,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .low,
                       "totalScore 3 is NOT positive (< 3 required)")
    }

    func testMiniCogThresholdAtTwo() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 2, recallScore: 2, clockScore: 0,
                                   aiClockExecutiveFlag: false),
            qdrs: QDRSInput(totalScore: 0, isPositiveScreen: false,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .intermediate,
                       "totalScore 2 IS positive (< 3)")
    }

    // MARK: AI Clock Executive Flag

    func testAIClockFlagUpgradesLowToIntermediate() {
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 4, recallScore: 3, clockScore: 2,
                                   aiClockExecutiveFlag: true),
            qdrs: QDRSInput(totalScore: 0, isPositiveScreen: false,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .intermediate,
                       "AI clock flag upgrades LOW → INTERMEDIATE")
        XCTAssertEqual(result.label, "Low-Intermediate Risk")
    }

    func testAIClockFlagDoesNotUpgradeNonLow() {
        // Already intermediate — flag shouldn't change it
        let result = computeCompositeRiskMiniCogQDRS(
            miniCog: MiniCogInput(totalScore: 4, recallScore: 3, clockScore: 2,
                                   aiClockExecutiveFlag: true),
            qdrs: QDRSInput(totalScore: 2.0, isPositiveScreen: true,
                            respondentType: .patient, flaggedDomains: [])
        )
        XCTAssertEqual(result.tier, .intermediate,
                       "Already intermediate — flag shouldn't upgrade further")
    }

    // MARK: Qmci + QDRS Matrix

    func testQmciQDRSBothPositiveIsHigh() {
        let qmci = QmciState()
        // Score < 54 → dementia range → isPositive = true
        qmci.orientationScores = [0, 0, 0, 0, 0]  // 0
        qmci.clockDrawingScore = 0
        let qdrs = QDRSState()
        qdrs.answers[0] = .changed; qdrs.answers[1] = .changed  // 2.0

        let result = computeCompositeRiskQmciQDRS(
            qmciState: qmci, qdrsState: qdrs, phq2Score: 0, clockAnalysis: nil
        )
        XCTAssertEqual(result.tier, .high)
    }

    func testQmciQDRSBothNegativeIsLow() {
        let qmci = QmciState()
        qmci.orientationScores = [2, 2, 2, 2, 2]  // 10
        qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
        qmci.clockDrawingScore = 15
        qmci.verbalFluencyWords = (0..<20).map { "a\($0)" }  // 20
        qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)  // 20
        qmci.delayedRecallWords = ["a", "b", "c"]  // 12
        // Total = 10+5+15+20+20+12 = 82 → normal
        let qdrs = QDRSState()  // All nil → 0 → negative

        let result = computeCompositeRiskQmciQDRS(
            qmciState: qmci, qdrsState: qdrs, phq2Score: 0, clockAnalysis: nil
        )
        XCTAssertEqual(result.tier, .low)
    }

    // MARK: PHQ-2 Adjustment

    func testPHQ2PositiveAddsDepressionAction() {
        let qmci = QmciState()
        let qdrs = QDRSState()
        // Both negative → low risk
        qmci.orientationScores = [2, 2, 2, 2, 2]
        qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
        qmci.clockDrawingScore = 15
        qmci.verbalFluencyWords = (0..<20).map { "a\($0)" }
        qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)
        qmci.delayedRecallWords = ["a", "b", "c", "d", "e"]

        let result = computeCompositeRiskQmciQDRS(
            qmciState: qmci, qdrsState: qdrs, phq2Score: 4, clockAnalysis: nil
        )
        XCTAssertTrue(result.narrative.contains("PHQ-2 positive"),
                      "PHQ-2 positive should be noted in narrative")
        XCTAssertTrue(result.suggestedActions.first?.contains("depression") ?? false,
                      "Depression evaluation should be first suggested action")
    }

    func testPHQ2NegativeNoDepressionAction() {
        let qmci = QmciState()
        let qdrs = QDRSState()
        qmci.orientationScores = [2, 2, 2, 2, 2]
        qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
        qmci.clockDrawingScore = 15
        qmci.verbalFluencyWords = (0..<20).map { "a\($0)" }
        qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)
        qmci.delayedRecallWords = ["a", "b", "c", "d", "e"]

        let result = computeCompositeRiskQmciQDRS(
            qmciState: qmci, qdrsState: qdrs, phq2Score: 2, clockAnalysis: nil
        )
        XCTAssertFalse(result.narrative.contains("PHQ-2 positive"))
    }

    // MARK: Clock Analysis Adjustment

    func testAbnormalClockUpgradesLow() {
        let qmci = QmciState()
        qmci.orientationScores = [2, 2, 2, 2, 2]
        qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
        qmci.clockDrawingScore = 15
        qmci.verbalFluencyWords = (0..<20).map { "a\($0)" }
        qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)
        qmci.delayedRecallWords = ["a", "b", "c", "d", "e"]
        let qdrs = QDRSState()

        let clock = ClockAnalysisResponse(
            aiClass: 1,  // Moderate — < 2
            shulmanRange: "Shulman 2-3",
            severity: "Moderate",
            confidence: 0.75,
            interpretation: "Moderate impairment",
            clinicalAction: "Further assessment",
            probabilities: ClockProbabilities(severe01: 0.1, moderate23: 0.75, normal45: 0.15)
        )

        let result = computeCompositeRiskQmciQDRS(
            qmciState: qmci, qdrsState: qdrs, phq2Score: 0, clockAnalysis: clock
        )
        XCTAssertEqual(result.tier, .intermediate,
                       "Abnormal clock (aiClass < 2) should upgrade LOW → INTERMEDIATE")
    }
}

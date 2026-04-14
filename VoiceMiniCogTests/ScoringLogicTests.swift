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
        autoreleasepool {
            let state = QDRSState()
            for i in 0..<10 { state.answers[i] = .normal }
            XCTAssertEqual(state.totalScore, 0.0)
            XCTAssertFalse(state.isPositiveScreen)
            XCTAssertEqual(state.riskLabel, "Low Concern")
        }
    }

    func testAllChangedIsMax() {
        autoreleasepool {
            let state = QDRSState()
            for i in 0..<10 { state.answers[i] = .changed }
            XCTAssertEqual(state.totalScore, 10.0)
            XCTAssertTrue(state.isPositiveScreen)
            XCTAssertEqual(state.riskLabel, "Significant Concern")
        }
    }

    func testExactThreshold1Point5() {
        autoreleasepool {
            let state = QDRSState()
            // 3 × "sometimes" (0.5) = 1.5
            state.answers[0] = .sometimes
            state.answers[1] = .sometimes
            state.answers[2] = .sometimes
            XCTAssertEqual(state.totalScore, 1.5)
            XCTAssertTrue(state.isPositiveScreen, "1.5 is the threshold — must be positive")
        }
    }

    func testJustBelowThreshold() {
        autoreleasepool {
            let state = QDRSState()
            // 2 × "sometimes" (0.5) = 1.0
            state.answers[0] = .sometimes
            state.answers[1] = .sometimes
            XCTAssertEqual(state.totalScore, 1.0)
            XCTAssertFalse(state.isPositiveScreen, "1.0 is below threshold — must be negative")
        }
    }

    func testMixedScoring() {
        autoreleasepool {
            let state = QDRSState()
            state.answers[0] = .changed     // 1.0
            state.answers[1] = .sometimes   // 0.5
            state.answers[2] = .normal      // 0.0
            XCTAssertEqual(state.totalScore, 1.5)
            XCTAssertTrue(state.isPositiveScreen)
        }
    }

    func testPartialCompletionStillScores() {
        autoreleasepool {
            let state = QDRSState()
            // Only 2 answers provided, rest nil
            state.answers[0] = .changed     // 1.0
            state.answers[1] = .changed     // 1.0
            XCTAssertEqual(state.totalScore, 2.0)
            XCTAssertTrue(state.isPositiveScreen,
                          "Partial answers still trigger positive if total >= 1.5")
        }
    }

    func testFlaggedDomainsCorrect() {
        autoreleasepool {
            let state = QDRSState()
            state.answers[0] = .changed     // Memory
            state.answers[3] = .sometimes   // Community
            state.answers[5] = .normal      // Personal Care (not flagged)
            let flagged = state.flaggedDomains
            XCTAssertTrue(flagged.contains("Memory"))
            XCTAssertTrue(flagged.contains("Community"))
            XCTAssertFalse(flagged.contains("Personal Care"))
        }
    }

    func testRiskLabels() {
        autoreleasepool {
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

    // MARK: Registration

    func testRegistrationMaxFive() {
        autoreleasepool {
            let state = QmciState()
            state.registrationRecalledWords = ["butter", "arm", "shore", "letter", "queen"]
            XCTAssertEqual(state.registrationScore, 5)
        }
    }

    func testRegistrationCappedAtFive() {
        autoreleasepool {
            let state = QmciState()
            // Somehow 6 words (shouldn't happen but test the cap)
            state.registrationRecalledWords = ["a", "b", "c", "d", "e", "f"]
            XCTAssertEqual(state.registrationScore, 5, "Capped at 5")
        }
    }

    func testRegistrationZero() {
        autoreleasepool {
            let state = QmciState()
            state.registrationRecalledWords = []
            XCTAssertEqual(state.registrationScore, 0)
        }
    }

    // MARK: Logical Memory

    func testLogicalMemoryScoring() {
        autoreleasepool {
            let state = QmciState()
            state.logicalMemoryRecalledUnits = ["Anna", "Thompson", "robbed"]
            XCTAssertEqual(state.logicalMemoryScore, 6, "3 units × 2 pts = 6")
        }
    }

    func testLogicalMemoryCappedAtThirty() {
        autoreleasepool {
            let state = QmciState()
            // 17 units × 2 = 34, capped at 30
            state.logicalMemoryRecalledUnits = Array(repeating: "unit", count: 17)
            XCTAssertEqual(state.logicalMemoryScore, 30, "Capped at 30")
        }
    }

    func testLogicalMemoryEmpty() {
        autoreleasepool {
            let state = QmciState()
            state.logicalMemoryRecalledUnits = []
            XCTAssertEqual(state.logicalMemoryScore, 0)
        }
    }

    // MARK: Delayed Recall

    func testDelayedRecallScoring() {
        autoreleasepool {
            let state = QmciState()
            state.delayedRecallWords = ["butter", "arm", "shore"]
            XCTAssertEqual(state.delayedRecallScore, 12, "3 words × 4 pts = 12")
        }
    }

    func testDelayedRecallAllFive() {
        autoreleasepool {
            let state = QmciState()
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]
            XCTAssertEqual(state.delayedRecallScore, 20, "5 words × 4 pts = 20, at max")
        }
    }

    func testDelayedRecallCappedAtTwenty() {
        autoreleasepool {
            let state = QmciState()
            state.delayedRecallWords = ["a", "b", "c", "d", "e", "f"]
            XCTAssertEqual(state.delayedRecallScore, 20, "Capped at 20")
        }
    }

    func testDelayedRecallEmpty() {
        autoreleasepool {
            let state = QmciState()
            state.delayedRecallWords = []
            XCTAssertEqual(state.delayedRecallScore, 0)
        }
    }

    // MARK: Total Score & Classification

    func testTotalScorePerfect() {
        autoreleasepool {
            let state = QmciState()
            // 10 + 5 + 15 + 20 + 30 + 20 = 100
            // Verbal fluency: 40 unique animals × 0.5 = 20 pts (at cap)
            state.orientationScores = [2, 2, 2, 2, 2]  // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
            state.clockDrawingScore = 15  // 15
            state.verbalFluencyWords = (0..<40).map { "animal\($0)" }  // 20
            state.logicalMemoryRecalledUnits = Array(repeating: "u", count: 15)  // 30
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
            XCTAssertEqual(state.totalScore, 100, "Perfect score = 100")
            XCTAssertEqual(state.classification, .normal)
        }
    }

    func testClassificationNormalBoundary() {
        autoreleasepool {
            let state = QmciState()
            // Set up to get exactly 67: 10 + 5 + 12 + 20 + 0 + 20 = 67
            // Verbal fluency: 40 unique animals × 0.5 = 20 pts (at cap)
            state.orientationScores = [2, 2, 2, 2, 2]  // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
            state.clockDrawingScore = 12  // 12
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }  // 20
            state.logicalMemoryRecalledUnits = []  // 0
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
            XCTAssertEqual(state.totalScore, 67)
            XCTAssertEqual(state.classification, .normal,
                           "67 is exactly the normal threshold")
        }
    }

    func testClassificationMCIBoundary() {
        autoreleasepool {
            let state = QmciState()
            // totalScore = 66 → MCI Probable: 10 + 5 + 11 + 20 + 0 + 20 = 66
            // Verbal fluency: 40 unique animals × 0.5 = 20 pts (at cap)
            state.orientationScores = [2, 2, 2, 2, 2]  // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
            state.clockDrawingScore = 11  // 11
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }  // 20
            state.logicalMemoryRecalledUnits = []  // 0
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
            XCTAssertEqual(state.totalScore, 66)
            XCTAssertEqual(state.classification, .mciProbable,
                           "66 is MCI Probable (below 67)")
        }
    }

    func testClassificationMCILowerBoundary() {
        autoreleasepool {
            let state = QmciState()
            // totalScore = 54 → MCI Probable (not dementia): 10 + 4 + 0 + 20 + 0 + 20 = 54
            // Verbal fluency: 40 unique animals × 0.5 = 20 pts (at cap)
            state.orientationScores = [2, 2, 2, 2, 2]  // 10
            state.registrationRecalledWords = ["a", "b", "c", "d"]  // 4
            state.clockDrawingScore = 0  // 0
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }  // 20
            state.logicalMemoryRecalledUnits = []  // 0
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
            XCTAssertEqual(state.totalScore, 54)
            XCTAssertEqual(state.classification, .mciProbable,
                           "54 is still MCI Probable (>= 54)")
        }
    }

    func testClassificationDementiaBoundary() {
        autoreleasepool {
            let state = QmciState()
            // totalScore = 53 → Dementia Range: 10 + 3 + 0 + 20 + 0 + 20 = 53
            // Verbal fluency: 40 unique animals × 0.5 = 20 pts (at cap)
            state.orientationScores = [2, 2, 2, 2, 2]  // 10
            state.registrationRecalledWords = ["a", "b", "c"]  // 3
            state.clockDrawingScore = 0  // 0
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }  // 20
            state.logicalMemoryRecalledUnits = []  // 0
            state.delayedRecallWords = ["a", "b", "c", "d", "e"]  // 20
            XCTAssertEqual(state.totalScore, 53)
            XCTAssertEqual(state.classification, .dementiaRange,
                           "53 is Dementia Range (below 54)")
        }
    }

    func testClassificationZero() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertEqual(state.totalScore, 0)
            XCTAssertEqual(state.classification, .dementiaRange)
        }
    }

    func testIsPositiveFlag() {
        XCTAssertFalse(QmciClassification.normal.isPositive)
        XCTAssertTrue(QmciClassification.mciProbable.isPositive)
        XCTAssertTrue(QmciClassification.dementiaRange.isPositive)
    }

    // MARK: Orientation 3-Level Scoring (QMCI)

    func testOrientationAllFullCredit() {
        autoreleasepool {
            let state = QmciState()
            state.orientationScores = [2, 2, 2, 2, 2]
            XCTAssertEqual(state.orientationScore, 10, "5 × 2 = 10 (full credit)")
        }
    }

    func testOrientationAllZero() {
        autoreleasepool {
            let state = QmciState()
            state.orientationScores = [0, 0, 0, 0, 0]
            XCTAssertEqual(state.orientationScore, 0)
        }
    }

    func testOrientationMixedCredit() {
        autoreleasepool {
            let state = QmciState()
            // 2 + 1 + 2 + 1 + 0 = 6
            state.orientationScores = [2, 1, 2, 1, 0]
            XCTAssertEqual(state.orientationScore, 6, "Mixed 3-level credits sum directly")
        }
    }

    func testOrientationPartialAnswered() {
        autoreleasepool {
            let state = QmciState()
            // 2 + 2 + nil + nil + nil = 4 (nils filtered out)
            state.orientationScores = [2, 2, nil, nil, nil]
            XCTAssertEqual(state.orientationScore, 4,
                           "Unanswered (nil) items filtered; 2 + 2 = 4")
        }
    }

    func testOrientationHypotheticalOverflowCapped() {
        autoreleasepool {
            let state = QmciState()
            // Defensive: 6 × 2 = 12 should clamp to 10
            state.orientationScores = [2, 2, 2, 2, 2, 2]
            XCTAssertEqual(state.orientationScore, 10,
                           "Computed property clamps raw sum to 10 max")
        }
    }

    // MARK: QMCI 15-point Clock Drawing Scoring

    func testClockPerfectScore() {
        autoreleasepool {
            let state = QmciState()
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            state.cdtInvalidNumbersCount = 0
            XCTAssertEqual(state.cdtComputedScore, 15,
                           "12 numbers + 3 hand/pivot points = 15")
        }
    }

    func testClockAllNumbers() {
        autoreleasepool {
            let state = QmciState()
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 0
            state.cdtPivotCorrect = false
            XCTAssertEqual(state.cdtComputedScore, 12,
                           "12 numbers only = 12")
        }
    }

    func testClockAllHandsNoNumbers() {
        autoreleasepool {
            let state = QmciState()
            state.cdtNumbersPlaced = Array(repeating: false, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            XCTAssertEqual(state.cdtComputedScore, 3,
                           "Hands (2) + pivot = 3")
        }
    }

    func testClockWithPenalty() {
        autoreleasepool {
            let state = QmciState()
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            state.cdtInvalidNumbersCount = 2
            XCTAssertEqual(state.cdtComputedScore, 13,
                           "15 - 2 invalid numbers = 13")
        }
    }

    func testClockClampedAtZero() {
        autoreleasepool {
            let state = QmciState()
            state.cdtNumbersPlaced = Array(repeating: false, count: 12)
            state.cdtHandsScore = 0
            state.cdtPivotCorrect = false
            state.cdtInvalidNumbersCount = 5
            XCTAssertEqual(state.cdtComputedScore, 0,
                           "Negative raw score clamped to 0")
        }
    }

    func testClockClampedAt15() {
        autoreleasepool {
            let state = QmciState()
            // This scenario can't naturally exceed 15, but ensure clamp works.
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            state.cdtInvalidNumbersCount = 0
            XCTAssertLessThanOrEqual(state.cdtComputedScore, 15,
                                     "Computed score never exceeds 15")
            XCTAssertEqual(state.cdtComputedScore, 15)
        }
    }

    func testRecomputeClockDrawingScore() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertEqual(state.clockDrawingScore, 0, "Starts at 0")
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            // Before recompute, stored field is still stale
            XCTAssertEqual(state.clockDrawingScore, 0,
                           "Stored field not yet refreshed")
            state.recomputeClockDrawingScore()
            XCTAssertEqual(state.clockDrawingScore, 15,
                           "recomputeClockDrawingScore() writes computed value back")
        }
    }

    func testTotalScoreUsesFreshClockValueIfCDTFieldsSet() {
        autoreleasepool {
            // Regression: if the clinician edits cdt* fields but forgets to call
            // recomputeClockDrawingScore(), totalScore should still reflect the
            // fresh value, not a stale stored clockDrawingScore.
            let state = QmciState()
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u", "u"]            // 4
            state.delayedRecallWords = ["a", "b"]                    // 8
            // Stale stored value
            state.clockDrawingScore = 15
            // Fresh cdt state says only 5 numbers placed = 5 points
            state.cdtNumbersPlaced = [true, true, true, true, true,
                                      false, false, false, false, false, false, false]
            // Do NOT call recomputeClockDrawingScore() — simulating the bug
            XCTAssertEqual(state.cdtComputedScore, 5)
            XCTAssertEqual(state.effectiveClockDrawingScore, 5,
                           "Prefers fresh value when cdt* fields are set")
            XCTAssertEqual(state.totalScore, 10 + 5 + 5 + 20 + 4 + 8,
                           "totalScore uses fresh cdt score, not stale stored value")
        }
    }

    func testLegacyClockScoreFallback() {
        autoreleasepool {
            // Legacy path: cdt* fields untouched, stored clockDrawingScore should
            // remain authoritative for backward compatibility with older saves.
            let state = QmciState()
            state.clockDrawingScore = 12
            XCTAssertEqual(state.effectiveClockDrawingScore, 12,
                           "Falls back to stored value when cdt* fields untouched")
        }
    }

    // MARK: Age/Education Normative Adjustment

    func testNoAdjustmentNeeded() {
        autoreleasepool {
            let state = QmciState()
            // Build raw 65 → MCI, no adjustment for age 60 / education 16.
            // 10 + 5 + 14 + 20 + 4 + 12 = 65
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 14                             // 14
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u", "u"]            // 4
            state.delayedRecallWords = ["a", "b", "c"]               // 12
            XCTAssertEqual(state.totalScore, 65)
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 16), 65,
                           "No adjustment for age 60, education 16")
            XCTAssertEqual(state.adjustedClassification(age: 60, educationYears: 16),
                           .mciProbable, "65 < 67 → MCI")
        }
    }

    func testAgeAdjustmentOnly() {
        autoreleasepool {
            let state = QmciState()
            // Raw 64 → +3 for age ≥75 → adjusted 67 → normal
            // 10+5+15+20+2+12 = 64.
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 15                             // 15
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u"]                 // 2
            state.delayedRecallWords = ["a", "b", "c"]               // 12
            XCTAssertEqual(state.totalScore, 64)
            XCTAssertEqual(state.adjustedScore(age: 80, educationYears: 16), 67,
                           "Age ≥75 adds +3: 64 + 3 = 67")
            XCTAssertEqual(state.adjustedClassification(age: 80, educationYears: 16),
                           .normal, "Adjusted 67 meets normal threshold")
        }
    }

    func testAgeAdjustmentBoundary75() {
        autoreleasepool {
            // Exactly 75 should qualify for the age bonus (inclusive per QMCI paper).
            let state = QmciState()
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 15                             // 15
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u"]                 // 2
            state.delayedRecallWords = ["a", "b", "c"]               // 12
            XCTAssertEqual(state.totalScore, 64)
            XCTAssertEqual(state.adjustedScore(age: 75, educationYears: 16), 67,
                           "Age 75 qualifies for +3 bonus")
            XCTAssertEqual(state.adjustedScore(age: 74, educationYears: 16), 64,
                           "Age 74 does NOT qualify for bonus")
        }
    }

    func testEducationAdjustmentOnly() {
        autoreleasepool {
            let state = QmciState()
            // Raw 63 → +4 for edu<12 → adjusted 67 → normal
            // 10+5+15+20+1+12 = 63? logical 1 not possible (2 per unit).
            // 10+5+15+20+0+12 = 62; 10+5+15+20+2+12 = 64. 63 unreachable.
            // Use 10+5+14+20+2+12 = 63 (clockDrawingScore = 14)
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 14                             // 14
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u"]                 // 2
            state.delayedRecallWords = ["a", "b", "c"]               // 12
            XCTAssertEqual(state.totalScore, 63)
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 8), 67,
                           "Education <12 adds +4: 63 + 4 = 67")
            XCTAssertEqual(state.adjustedClassification(age: 60, educationYears: 8),
                           .normal, "Adjusted 67 meets normal threshold")
        }
    }

    func testBothAdjustments() {
        autoreleasepool {
            let state = QmciState()
            // Raw 60 → +3 age +4 edu → adjusted 67 → normal
            // 10+5+15+20+0+ delayed = 60 → delayed = 10 invalid.
            // 10+5+11+20+2+12 = 60 (clockDrawingScore = 11)
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 11                             // 11
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = ["u"]                 // 2
            state.delayedRecallWords = ["a", "b", "c"]               // 12
            XCTAssertEqual(state.totalScore, 60)
            XCTAssertEqual(state.adjustedScore(age: 80, educationYears: 8), 67,
                           "Both adjustments: 60 + 3 + 4 = 67")
            XCTAssertEqual(state.adjustedClassification(age: 80, educationYears: 8),
                           .normal, "Adjusted 67 meets normal threshold")
        }
    }

    func testAdjustmentReasonsEmpty() {
        autoreleasepool {
            let state = QmciState()
            let reasons = state.adjustmentReasons(age: 60, educationYears: 16)
            XCTAssertEqual(reasons, [], "No reasons for non-adjusted demographics")
        }
    }

    func testAdjustmentReasonsBoth() {
        autoreleasepool {
            let state = QmciState()
            let reasons = state.adjustmentReasons(age: 80, educationYears: 8)
            XCTAssertEqual(reasons.count, 2, "Both age and education adjustments listed")
            XCTAssertTrue(reasons.contains { $0.contains("Age") })
            XCTAssertTrue(reasons.contains { $0.contains("Education") })
        }
    }

    // MARK: Verbal Fluency Scoring (0.5 pts per animal, max 40, rounded up)

    func testVerbalFluencyEmptyScore() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = []
            XCTAssertEqual(state.verbalFluencyScore, 0)
        }
    }

    func testVerbalFluencySingleWord() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = ["dog"]
            // 1 × 0.5 = 0.5 → rounded up = 1
            XCTAssertEqual(state.verbalFluencyScore, 1,
                           "1 unique animal → 0.5 rounded up → 1")
        }
    }

    func testVerbalFluencyRoundingUp() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = (0..<15).map { "animal\($0)" }
            // 15 × 0.5 = 7.5 → rounded up = 8
            XCTAssertEqual(state.verbalFluencyScore, 8,
                           "15 unique animals → 7.5 rounded up → 8")
        }
    }

    func testVerbalFluencyMaxCap() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = (0..<50).map { "animal\($0)" }
            // Capped at 40 → 40 × 0.5 = 20
            XCTAssertEqual(state.verbalFluencyScore, 20,
                           "Capped at 40 animals → 20 points")
        }
    }

    func testVerbalFluencyDuplicatesDeduplicated() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = ["dog", "dog", "cat"]
            // 2 unique × 0.5 = 1.0 → rounded up = 1
            XCTAssertEqual(state.verbalFluencyScore, 1,
                           "2 unique animals → 1.0 → 1")
        }
    }

    func testVerbalFluencyCaseInsensitiveDedup() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = ["Dog", "DOG", "dog"]
            // 1 unique (case-insensitive) × 0.5 = 0.5 → rounded up = 1
            XCTAssertEqual(state.verbalFluencyScore, 1,
                           "Case-insensitive dedup: 1 unique → 1")
        }
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

    // MARK: Verbal Fluency Exact Boundary Coverage

    func testVerbalFluencyExactly40Animals() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = (0..<40).map { "animal\($0)" }
            // 40 unique × 0.5 = 20.0 → 20
            XCTAssertEqual(state.verbalFluencyScore, 20,
                           "40 unique animals → 20 points (exact cap)")
        }
    }

    func testVerbalFluencyBoundary39Animals() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = (0..<39).map { "animal\($0)" }
            // 39 × 0.5 = 19.5 → ceil = 20
            XCTAssertEqual(state.verbalFluencyScore, 20,
                           "39 unique animals → 19.5 rounded up → 20")
        }
    }

    func testVerbalFluencyBoundary38Animals() {
        autoreleasepool {
            let state = QmciState()
            state.verbalFluencyWords = (0..<38).map { "animal\($0)" }
            // 38 × 0.5 = 19.0 → 19
            XCTAssertEqual(state.verbalFluencyScore, 19,
                           "38 unique animals → 19.0 → 19")
        }
    }

    // MARK: Education/Age Adjustment Boundaries

    func testEducationAdjustmentBoundary12Years() {
        autoreleasepool {
            let state = QmciState()
            // Baseline raw: 10 + 5 + 10 + 20 + 0 + 16 = 61
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 10                             // 10
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20 (40 × 0.5)
            state.logicalMemoryRecalledUnits = []                    // 0
            state.delayedRecallWords = ["a", "b", "c", "d"]          // 16 (4 × 4)
            XCTAssertEqual(state.totalScore, 61)
            // Exactly 12 years → NO bonus (rule is <12)
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 12), 61,
                           "12 years education does NOT trigger +4 bonus")
            // 11 years → +4 bonus
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 11), 65,
                           "11 years education DOES trigger +4 bonus")
        }
    }

    func testEducationAdjustmentZeroYears() {
        autoreleasepool {
            let state = QmciState()
            state.orientationScores = [2, 2, 2, 2, 2]               // 10
            state.registrationRecalledWords = ["a", "b", "c", "d", "e"] // 5
            state.clockDrawingScore = 10                             // 10
            state.verbalFluencyWords = (0..<40).map { "a\($0)" }     // 20
            state.logicalMemoryRecalledUnits = []                    // 0
            state.delayedRecallWords = ["a", "b", "c", "d"]          // 16
            XCTAssertEqual(state.totalScore, 61)
            // 0 years education → +4 bonus
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 0), 65,
                           "0 years education triggers +4 bonus")
        }
    }

    // MARK: Orientation All Nil

    func testOrientationAllNilIsZero() {
        autoreleasepool {
            let state = QmciState()
            state.orientationScores = [nil, nil, nil, nil, nil]
            XCTAssertEqual(state.orientationScore, 0,
                           "All nil orientation scores → 0")
        }
    }

    // MARK: Reset

    func testResetClearsAllState() {
        autoreleasepool {
            let state = QmciState()
            // Populate a bunch of state
            state.orientationScores = [2, 2, 2, 2, 2]
            state.registrationRecalledWords = ["a", "b", "c"]
            state.verbalFluencyWords = ["dog", "cat"]
            state.logicalMemoryRecalledUnits = ["unit"]
            state.delayedRecallWords = ["a"]
            state.clockDrawingScore = 15
            state.cdtNumbersPlaced = Array(repeating: true, count: 12)
            state.cdtHandsScore = 2
            state.cdtPivotCorrect = true
            state.cdtInvalidNumbersCount = 3

            state.reset()

            XCTAssertEqual(state.orientationScores, [nil, nil, nil, nil, nil],
                           "orientationScores cleared to all nil")
            XCTAssertTrue(state.registrationRecalledWords.isEmpty)
            XCTAssertTrue(state.verbalFluencyWords.isEmpty)
            XCTAssertTrue(state.logicalMemoryRecalledUnits.isEmpty)
            XCTAssertTrue(state.delayedRecallWords.isEmpty)
            XCTAssertEqual(state.clockDrawingScore, 0)
            XCTAssertEqual(state.cdtNumbersPlaced, Array(repeating: false, count: 12))
            XCTAssertEqual(state.cdtHandsScore, 0)
            XCTAssertFalse(state.cdtPivotCorrect)
            XCTAssertEqual(state.cdtInvalidNumbersCount, 0)
        }
    }

    // MARK: Word List Selection

    func testSelectWordListPicksFromList() {
        autoreleasepool {
            let state = QmciState()
            state.selectWordList()
            XCTAssertEqual(state.registrationWords.count, 5,
                           "Selected list has exactly 5 words")
            XCTAssertTrue(QMCI_WORD_LISTS.contains(state.registrationWords),
                          "Selected list is one of the QMCI_WORD_LISTS")
        }
    }

    // MARK: Adjusted Score Defensive

    func testAdjustedScoreNeverNegative() {
        autoreleasepool {
            let state = QmciState()
            // Pristine state → totalScore 0, no adjustments → 0
            XCTAssertEqual(state.totalScore, 0)
            XCTAssertGreaterThanOrEqual(state.adjustedScore(age: 60, educationYears: 16), 0,
                                        "Adjusted score is never negative")
            XCTAssertEqual(state.adjustedScore(age: 60, educationYears: 16), 0)
        }
    }

    // MARK: Orientation response capture

    func testOrientationResponsesDefaultsEmpty() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertEqual(state.orientationResponses.count, 5)
            XCTAssertTrue(state.orientationResponses.allSatisfy { $0 == "" })
            XCTAssertEqual(state.orientationAttempted.count, 5)
            XCTAssertTrue(state.orientationAttempted.allSatisfy { $0 == false })
        }
    }

    func testOrientationResponsesPersist() {
        autoreleasepool {
            let state = QmciState()
            state.orientationResponses[0] = "United States"
            state.orientationAttempted[0] = true
            XCTAssertEqual(state.orientationResponses[0], "United States")
            XCTAssertTrue(state.orientationAttempted[0])
        }
    }

    func testResetClearsOrientationResponses() {
        autoreleasepool {
            let state = QmciState()
            state.orientationResponses = ["a", "b", "c", "d", "e"]
            state.orientationAttempted = [true, true, true, true, true]
            state.reset()
            XCTAssertEqual(state.orientationResponses.count, 5)
            XCTAssertTrue(state.orientationResponses.allSatisfy { $0 == "" })
            XCTAssertEqual(state.orientationAttempted.count, 5)
            XCTAssertTrue(state.orientationAttempted.allSatisfy { $0 == false })
        }
    }

    // MARK: Trial-1 registration

    func testTrial1RegistrationScoreDefaultZero() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertEqual(state.trial1RegistrationScore, 0)
        }
    }

    func testTrial1RegistrationScoreFromFirstTrial() {
        autoreleasepool {
            let state = QmciState()
            state.registrationTrialWords = [
                ["dog", "rain", "butter"],
                ["dog", "rain", "butter", "door"],
                ["dog", "rain", "butter", "door", "love"]
            ]
            XCTAssertEqual(state.trial1RegistrationScore, 3)
            // Legacy registrationScore is independent and based on registrationRecalledWords
            XCTAssertEqual(state.registrationScore, 0)
        }
    }

    func testTrial1RegistrationScoreCappedAtFive() {
        autoreleasepool {
            let state = QmciState()
            state.registrationTrialWords[0] = ["a", "b", "c", "d", "e", "f", "g"]
            XCTAssertEqual(state.trial1RegistrationScore, 5)
        }
    }

    func testResetClearsRegistrationTrialWords() {
        autoreleasepool {
            let state = QmciState()
            state.registrationTrialWords = [
                ["a", "b"],
                ["a", "b", "c"],
                ["a", "b", "c", "d"]
            ]
            state.reset()
            XCTAssertEqual(state.registrationTrialWords, [[], [], []])
        }
    }

    // MARK: Fluency verbatim list

    func testFluencyAnimalsNamedDefaultEmpty() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertTrue(state.fluencyAnimalsNamed.isEmpty)
        }
    }

    func testFluencyAnimalsNamedPreservesDuplicates() {
        autoreleasepool {
            let state = QmciState()
            state.fluencyAnimalsNamed = ["dog", "dog", "cat", "dog"]
            state.verbalFluencyWords = ["dog", "cat"]
            XCTAssertEqual(state.fluencyAnimalsNamed.count, 4,
                           "Verbatim list preserves duplicates")
            XCTAssertEqual(state.verbalFluencyScore, 1,
                           "2 unique × 0.5 = 1 (rounded up)")
        }
    }

    // MARK: Clock biomarkers

    func testClockDrawingImagePNGDefaultNil() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertNil(state.clockDrawingImagePNG)
        }
    }

    func testClockStrokeEventsDefaultEmpty() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertTrue(state.clockStrokeEvents.isEmpty)
        }
    }

    func testClockStrokeEventRoundtrip() {
        autoreleasepool {
            let state = QmciState()
            let event = ClockStrokeEvent(
                timestamp: 1.23,
                points: [
                    CGPointCodable(x: 10, y: 20),
                    CGPointCodable(x: 30, y: 40)
                ]
            )
            state.clockStrokeEvents.append(event)
            XCTAssertEqual(state.clockStrokeEvents.count, 1)
            XCTAssertEqual(state.clockStrokeEvents.first?.points.count, 2)
        }
    }

    func testResetClearsClockBiomarkers() {
        autoreleasepool {
            let state = QmciState()
            state.clockDrawingImagePNG = Data([0x01, 0x02, 0x03])
            state.clockStrokeEvents = [
                ClockStrokeEvent(timestamp: 0.5, points: [CGPointCodable(x: 1, y: 2)])
            ]
            state.clockPauseEvents = [
                ClockPauseEvent(startTimestamp: 0.1, durationMs: 250)
            ]
            state.clockScoreOverrideBy = "doc-abc"
            state.clockScoreOverrideTimestamp = Date()
            state.reset()
            XCTAssertNil(state.clockDrawingImagePNG)
            XCTAssertTrue(state.clockStrokeEvents.isEmpty)
            XCTAssertTrue(state.clockPauseEvents.isEmpty)
            XCTAssertNil(state.clockScoreOverrideBy)
            XCTAssertNil(state.clockScoreOverrideTimestamp)
        }
    }

    func testApplyClockScoreOverride() {
        autoreleasepool {
            let state = QmciState()
            state.applyClockScoreOverride(by: "doc-123")
            XCTAssertEqual(state.clockScoreOverrideBy, "doc-123")
            XCTAssertNotNil(state.clockScoreOverrideTimestamp)
        }
    }

    // MARK: Clinician decisions

    func testClinicianDecisionsDefaultNil() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertNil(state.clinicianDecisionWorkup)
            XCTAssertNil(state.clinicianDecisionRepeat)
            XCTAssertNil(state.clinicianDecisionTimestamp)
        }
    }

    func testClinicianDecisionsPersist() {
        autoreleasepool {
            let state = QmciState()
            state.clinicianDecisionWorkup = true
            state.clinicianDecisionRepeat = false
            state.clinicianDecisionTimestamp = Date()
            XCTAssertNotNil(state.clinicianDecisionWorkup)
            XCTAssertNotNil(state.clinicianDecisionRepeat)
            XCTAssertNotNil(state.clinicianDecisionTimestamp)
            XCTAssertEqual(state.clinicianDecisionWorkup, true)
            XCTAssertEqual(state.clinicianDecisionRepeat, false)
        }
    }

    func testResetClearsClinicianDecisions() {
        autoreleasepool {
            let state = QmciState()
            state.clinicianDecisionWorkup = true
            state.clinicianDecisionRepeat = true
            state.clinicianDecisionTimestamp = Date()
            state.reset()
            XCTAssertNil(state.clinicianDecisionWorkup)
            XCTAssertNil(state.clinicianDecisionRepeat)
            XCTAssertNil(state.clinicianDecisionTimestamp)
        }
    }

    // MARK: Test version coupling

    func testTestVersionDefault() {
        autoreleasepool {
            let state = QmciState()
            XCTAssertEqual(state.testVersion, .v1)
        }
    }

    func testSelectTestVersionCouplesIndices() {
        autoreleasepool {
            for _ in 0..<5 {
                let state = QmciState()
                state.selectTestVersion()
                XCTAssertEqual(state.registrationWordListIndex, state.testVersion.rawValue)
                XCTAssertEqual(state.logicalMemoryStoryIndex, state.testVersion.rawValue)
                XCTAssertEqual(state.registrationWords,
                               QMCI_WORD_LISTS[state.testVersion.rawValue])
                XCTAssertEqual(state.currentStory.id,
                               LOGICAL_MEMORY_STORIES[state.testVersion.rawValue].id)
            }
        }
    }

    // MARK: Session metadata

    func testSessionIDAndDateTimeInitialized() {
        autoreleasepool {
            let state1 = QmciState()
            let state2 = QmciState()
            XCTAssertNotEqual(state1.sessionID, state2.sessionID,
                              "Each new QmciState gets its own sessionID")
            let now = Date()
            XCTAssertLessThanOrEqual(abs(now.timeIntervalSince(state1.sessionDateTime)), 5.0,
                                     "sessionDateTime is within 5 seconds of now")
        }
    }

    // MARK: Codable round-trip with new fields

    func testCodableRoundtripIncludesNewFields() {
        autoreleasepool {
            let state = QmciState()
            state.orientationResponses[0] = "United States"
            state.orientationAttempted[0] = true
            state.registrationTrialWords = [
                ["a", "b"],
                ["a", "b", "c"],
                ["a", "b", "c", "d"]
            ]
            state.fluencyAnimalsNamed = ["dog", "dog", "cat"]
            state.clinicianDecisionWorkup = true
            state.clockScoreOverrideBy = "doc-x"
            state.testVersion = .v2

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            do {
                let data = try encoder.encode(state)
                let decoded = try decoder.decode(QmciState.self, from: data)
                XCTAssertEqual(decoded.orientationResponses[0], "United States")
                XCTAssertEqual(decoded.orientationAttempted[0], true)
                XCTAssertEqual(decoded.registrationTrialWords, [
                    ["a", "b"],
                    ["a", "b", "c"],
                    ["a", "b", "c", "d"]
                ])
                XCTAssertEqual(decoded.fluencyAnimalsNamed, ["dog", "dog", "cat"])
                XCTAssertEqual(decoded.clinicianDecisionWorkup, true)
                XCTAssertEqual(decoded.clockScoreOverrideBy, "doc-x")
                XCTAssertEqual(decoded.testVersion, .v2)
                XCTAssertNotNil(decoded.sessionID)
                XCTAssertNotNil(decoded.sessionDateTime)
            } catch {
                XCTFail("Codable round-trip failed: \(error)")
            }
        }
    }

    func testQmciStateRoundTrips() throws {
        let original = QmciState()
        original.orientationScores = [2, 2, 1, 2, 0]
        original.registrationWords = ["dog", "rain", "butter", "love", "door"]
        original.verbalFluencyWords = ["cat", "dog", "lion"]
        original.clockDrawingScore = 12
        original.cdtHandsScore = 2
        original.cdtPivotCorrect = true

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QmciState.self, from: data)

        XCTAssertEqual(decoded.orientationScores.compactMap { $0 }, [2, 2, 1, 2, 0])
        XCTAssertEqual(decoded.registrationWords, original.registrationWords)
        XCTAssertEqual(decoded.verbalFluencyWords, original.verbalFluencyWords)
        XCTAssertEqual(decoded.cdtHandsScore, 2)
        XCTAssertEqual(decoded.cdtPivotCorrect, true)
        XCTAssertEqual(decoded.totalScore, original.totalScore)
    }

    // MARK: - ReportReadiness Tests

    func testReportReadinessNotReadyWhenIncomplete() {
        let state = QmciState()
        state.isComplete = false
        XCTAssertEqual(state.reportReadiness, .notReady)
    }

    func testReportReadinessPendingWhenNoCDTReview() {
        let state = QmciState()
        state.isComplete = true
        state.cdtReviewed = false
        state.clinicianDecisionWorkup = nil
        XCTAssertEqual(state.reportReadiness, .pendingClinician)
    }

    func testReportReadinessCompleteWhenAllGatesMet() {
        let state = QmciState()
        state.isComplete = true
        state.cdtReviewed = true
        state.clinicianDecisionWorkup = true
        XCTAssertEqual(state.reportReadiness, .complete)
    }

    func testReportReadinessAllowsZeroFifteenCDT() {
        let state = QmciState()
        state.isComplete = true
        state.cdtReviewed = true
        state.cdtNumbersPlaced = Array(repeating: false, count: 12)
        state.cdtHandsScore = 0
        state.cdtPivotCorrect = false
        state.clinicianDecisionWorkup = false
        XCTAssertEqual(state.cdtComputedScore, 0)
        XCTAssertEqual(state.reportReadiness, .complete)
    }

    func testPendingReviewCountTracksAllRequiredFields() {
        let state = QmciState()
        state.isComplete = true
        state.cdtReviewed = false
        state.clinicianDecisionWorkup = nil
        XCTAssertEqual(state.pendingReviewCount, 2)
        state.cdtReviewed = true
        XCTAssertEqual(state.pendingReviewCount, 1)
        state.clinicianDecisionWorkup = true
        XCTAssertEqual(state.pendingReviewCount, 0)
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
        autoreleasepool {
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
    }

    func testQmciQDRSBothNegativeIsLow() {
        autoreleasepool {
            let qmci = QmciState()
            qmci.orientationScores = [2, 2, 2, 2, 2]  // 10
            qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]  // 5
            qmci.clockDrawingScore = 15
            qmci.verbalFluencyWords = (0..<40).map { "a\($0)" }  // 20
            qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)  // 20
            qmci.delayedRecallWords = ["a", "b", "c"]  // 12
            // Total = 10+5+15+20+20+12 = 82 → normal
            let qdrs = QDRSState()  // All nil → 0 → negative

            let result = computeCompositeRiskQmciQDRS(
                qmciState: qmci, qdrsState: qdrs, phq2Score: 0, clockAnalysis: nil
            )
            XCTAssertEqual(result.tier, .low)
        }
    }

    // MARK: PHQ-2 Adjustment

    func testPHQ2PositiveAddsDepressionAction() {
        autoreleasepool {
            let qmci = QmciState()
            let qdrs = QDRSState()
            // Both negative → low risk
            qmci.orientationScores = [2, 2, 2, 2, 2]
            qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
            qmci.clockDrawingScore = 15
            qmci.verbalFluencyWords = (0..<40).map { "a\($0)" }
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
    }

    func testPHQ2NegativeNoDepressionAction() {
        autoreleasepool {
            let qmci = QmciState()
            let qdrs = QDRSState()
            qmci.orientationScores = [2, 2, 2, 2, 2]
            qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
            qmci.clockDrawingScore = 15
            qmci.verbalFluencyWords = (0..<40).map { "a\($0)" }
            qmci.logicalMemoryRecalledUnits = Array(repeating: "u", count: 10)
            qmci.delayedRecallWords = ["a", "b", "c", "d", "e"]

            let result = computeCompositeRiskQmciQDRS(
                qmciState: qmci, qdrsState: qdrs, phq2Score: 2, clockAnalysis: nil
            )
            XCTAssertFalse(result.narrative.contains("PHQ-2 positive"))
        }
    }

    // MARK: Clock Analysis Adjustment

    func testAbnormalClockUpgradesLow() {
        autoreleasepool {
            let qmci = QmciState()
            qmci.orientationScores = [2, 2, 2, 2, 2]
            qmci.registrationRecalledWords = ["a", "b", "c", "d", "e"]
            qmci.clockDrawingScore = 15
            qmci.verbalFluencyWords = (0..<40).map { "a\($0)" }
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
}

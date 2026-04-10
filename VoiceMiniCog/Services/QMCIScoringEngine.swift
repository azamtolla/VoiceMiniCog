import Foundation

/// Per-subtest scored breakdown.
struct QMCISubtestScore: Equatable {
    let subtest: QmciSubtest
    let rawScore: Int
    let maxScore: Int
    /// Short human-readable patient-response summary for the Results page Section B.
    let responseSummary: String
}

/// Adjustment band label per spec Section A ("Age <75/≥75 × Edu <12/≥12").
struct QMCIAdjustmentGroup: Equatable {
    let ageBand: String      // "<75" or "≥75"
    let eduBand: String      // "<12" or "≥12"
    var label: String { "Age \(ageBand), Edu \(eduBand)" }
}

/// Frozen, fully-computed result for the Results Summary page.
/// Views read from this struct only — no live computation in views.
struct QMCIScoredResult: Equatable {
    let sessionID: UUID
    let sessionDateTime: Date
    let testVersion: TestVersion
    let patientAge: Int
    let yearsEducation: Int
    let adjustmentGroup: QMCIAdjustmentGroup
    let subtestScores: [QMCISubtestScore]   // one entry per QmciSubtest.allCases, in allCases order
    let rawTotal: Int
    let adjustedTotal: Int
    let adjustmentReasons: [String]
    let rawClassification: QmciClassification
    let adjustedClassification: QmciClassification
    /// Weakest domain by (rawScore / maxScore) ratio.
    let weakestSubtest: QmciSubtest
    /// Strongest domain by (rawScore / maxScore) ratio.
    let strongestSubtest: QmciSubtest
}

/// Stateless scoring engine. All methods are pure; they read from `QmciState`
/// and demographics, and return a `QMCIScoredResult` ready for display.
enum QMCIScoringEngine {

    /// Produce a complete scored result for the Results Summary page.
    static func score(session: QmciState, patientAge: Int, yearsEducation: Int) -> QMCIScoredResult {
        // Build per-subtest rows using QmciSubtest.allCases order.
        let subtestScores: [QMCISubtestScore] = QmciSubtest.allCases.map { subtest in
            QMCISubtestScore(
                subtest: subtest,
                rawScore: rawScore(for: subtest, session: session),
                maxScore: subtest.maxScore,
                responseSummary: responseSummary(for: subtest, session: session)
            )
        }

        let rawTotal = session.totalScore
        let adjustedTotal = session.adjustedScore(age: patientAge, educationYears: yearsEducation)
        let adjustmentReasons = session.adjustmentReasons(age: patientAge, educationYears: yearsEducation)
        let rawClassification = session.classification
        let adjustedClassification = session.adjustedClassification(age: patientAge, educationYears: yearsEducation)
        let adjustmentGroup = QMCIAdjustmentGroup(
            ageBand: patientAge >= 75 ? "≥75" : "<75",
            eduBand: yearsEducation < 12 ? "<12" : "≥12"
        )

        // Weakest/strongest by ratio, tie-breaking by natural QmciSubtest order.
        let ratios = subtestScores.map { ($0.subtest, Double($0.rawScore) / Double($0.maxScore)) }
        let weakest = ratios.min(by: { $0.1 < $1.1 })?.0 ?? .orientation
        let strongest = ratios.max(by: { $0.1 < $1.1 })?.0 ?? .orientation

        return QMCIScoredResult(
            sessionID: session.sessionID,
            sessionDateTime: session.sessionDateTime,
            testVersion: session.testVersion,
            patientAge: patientAge,
            yearsEducation: yearsEducation,
            adjustmentGroup: adjustmentGroup,
            subtestScores: subtestScores,
            rawTotal: rawTotal,
            adjustedTotal: adjustedTotal,
            adjustmentReasons: adjustmentReasons,
            rawClassification: rawClassification,
            adjustedClassification: adjustedClassification,
            weakestSubtest: weakest,
            strongestSubtest: strongest
        )
    }

    // MARK: - Per-subtest helpers

    private static func rawScore(for subtest: QmciSubtest, session: QmciState) -> Int {
        switch subtest {
        case .orientation:    return session.orientationScore
        case .registration:   return session.registrationScore
        case .clockDrawing:   return session.effectiveClockDrawingScore
        case .verbalFluency:  return session.verbalFluencyScore
        case .logicalMemory:  return session.logicalMemoryScore
        case .delayedRecall:  return session.delayedRecallScore
        }
    }

    private static func responseSummary(for subtest: QmciSubtest, session: QmciState) -> String {
        switch subtest {
        case .orientation:
            // Pair each item prompt with the patient response; mark unanswered.
            let lines = zip(ORIENTATION_ITEMS, session.orientationResponses).map { item, response -> String in
                let text = response.isEmpty ? "(no response)" : response
                return "\(item.question) → \(text)"
            }
            return lines.joined(separator: "\n")
        case .registration:
            let presented = session.registrationWords.joined(separator: ", ")
            let recalled = session.registrationRecalledWords.isEmpty
                ? "(none)"
                : session.registrationRecalledWords.joined(separator: ", ")
            return "Presented: \(presented)\nRecalled: \(recalled)"
        case .clockDrawing:
            let numbers = session.cdtNumbersPlaced.filter { $0 }.count
            return "Numbers: \(numbers)/12 • Minute: \(session.cdtMinuteHandCorrect ? "✓" : "✗") • Hour: \(session.cdtHourHandCorrect ? "✓" : "✗") • Pivot: \(session.cdtPivotCorrect ? "✓" : "✗") • Errors: \(session.cdtInvalidNumbersCount)"
        case .verbalFluency:
            let unique = Set(session.verbalFluencyWords.map { $0.lowercased() }).count
            return "\(unique) unique animals — \(session.verbalFluencyWords.joined(separator: ", "))"
        case .logicalMemory:
            let recalled = session.logicalMemoryRecalledUnits.isEmpty
                ? "(none)"
                : session.logicalMemoryRecalledUnits.joined(separator: ", ")
            return "Recalled units: \(recalled)"
        case .delayedRecall:
            let words = session.delayedRecallWords.isEmpty
                ? "(none)"
                : session.delayedRecallWords.joined(separator: ", ")
            return "Target words: \(session.registrationWords.joined(separator: ", "))\nRecalled: \(words)"
        }
    }
}

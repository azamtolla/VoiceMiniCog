//
//  PDFInspectionTests.swift
//  VoiceMiniCogTests
//
//  Static inspection of PDFReportGenerator (Test 1a) and PartialScoreReport
//  (Test 3a). Fabricates AssessmentState at known score tiers, generates
//  PDF bytes in-memory, and uses PDFKit to extract text for assertion.
//
// KNOWN: malloc double-free on XCTest host injection.
// Blocks VoiceMiniCogTests from running in CI.
// Root cause: likely Daily SDK or @MainActor initializer.
// Fix requires: Option 2 (guard init under tests) or
// Option 3 (framework extraction) — deferred.
//

import XCTest
import PDFKit
@testable import VoiceMiniCog

// MARK: - PDF text extraction helper

private func pdfText(from data: Data) -> String {
    guard let doc = PDFDocument(data: data) else { return "" }
    var out = ""
    for i in 0..<doc.pageCount {
        if let page = doc.page(at: i), let t = page.string { out += t + "\n" }
    }
    return out
}

private func makeQmciState(orientation: Int,
                           registration: Int,
                           clock: Int,
                           fluencyUnique: Int,
                           logicalUnits: Int,
                           delayedWords: Int) -> QmciState {
    let q = QmciState()
    var oScores: [Int?] = Array(repeating: nil, count: 5)
    var remaining = orientation
    for i in 0..<5 {
        let take = min(2, remaining)
        oScores[i] = take
        remaining -= take
    }
    q.orientationScores = oScores
    q.registrationRecalledWords = (0..<registration).map { "w\($0)" }
    q.clockDrawingScore = clock
    q.verbalFluencyWords = (0..<fluencyUnique).map { "animal\($0)" }
    q.logicalMemoryRecalledUnits = (0..<logicalUnits).map { "u\($0)" }
    q.delayedRecallWords = (0..<delayedWords).map { "rw\($0)" }
    return q
}

private func makeQDRS(positive: Bool) -> QDRSState {
    let s = QDRSState()
    if positive {
        s.answers[0] = .changed
        s.answers[1] = .changed
        s.answers[2] = .changed
    } else {
        s.answers[0] = .normal
    }
    return s
}

// MARK: - TEST 1a — three-tier PDF inspection

@MainActor
final class PDFScoreTierTests: XCTestCase {

    func testRedTier_score40_highBanner() {
        let state = AssessmentState()
        state.qmciState = makeQmciState(
            orientation: 2, registration: 1, clock: 9,
            fluencyUnique: 8, logicalUnits: 6, delayedWords: 2)
        state.qdrsState = makeQDRS(positive: true)
        state.compositeRisk = CompositeRiskOutput(
            tier: .high,
            label: "High Risk — Concordant Positive",
            summaryLine: "Qmci 40/100 and QDRS positive",
            narrative: "Concordant positive findings.",
            suggestedActions: ["Refer to neurology"]
        )

        XCTAssertEqual(state.qmciState.totalScore, 40,
                       "Fixture must produce totalScore=40")

        let data = PDFReportGenerator.generate(from: state)
        XCTAssertGreaterThan(data.count, 500, "PDF should have non-trivial byte size")

        let text = pdfText(from: data)
        XCTAssertTrue(text.contains("HIGH RISK"),
                      "Missing HIGH RISK banner. Text: \(text.prefix(400))")
        XCTAssertTrue(text.contains("40"), "Score 40 not present")
        XCTAssertTrue(text.contains("Orientation"))
        XCTAssertTrue(text.contains("Word Learning"))
        XCTAssertTrue(text.contains("Clock Drawing"))
        XCTAssertTrue(text.contains("Verbal Fluency"))
        XCTAssertTrue(text.contains("Story Recall"))
        XCTAssertTrue(text.contains("Word Recall"))
        XCTAssertFalse(text.contains("nil"),
                       "No raw 'nil' should appear in the PDF text")
    }

    func testYellowTier_score60_intermediateBanner() {
        let state = AssessmentState()
        state.qmciState = makeQmciState(
            orientation: 6, registration: 4, clock: 11,
            fluencyUnique: 11, logicalUnits: 8, delayedWords: 3)
        state.qdrsState = makeQDRS(positive: false)
        state.compositeRisk = CompositeRiskOutput(
            tier: .intermediate,
            label: "Intermediate — Qmci+/QDRS-",
            summaryLine: "Qmci positive but patient reports no functional decline",
            narrative: "Objective impairment without reported functional difficulty.",
            suggestedActions: ["Consider neuropsychological testing"]
        )

        XCTAssertEqual(state.qmciState.totalScore, 60,
                       "Fixture must produce totalScore=60")

        let data = PDFReportGenerator.generate(from: state)
        XCTAssertGreaterThan(data.count, 500)

        let text = pdfText(from: data)
        XCTAssertTrue(text.contains("INTERMEDIATE RISK"),
                      "Missing INTERMEDIATE RISK banner. Text: \(text.prefix(400))")
        XCTAssertTrue(text.contains("60"))
        XCTAssertTrue(text.contains("Orientation"))
        XCTAssertTrue(text.contains("Word Learning"))
        XCTAssertTrue(text.contains("Clock Drawing"))
        XCTAssertTrue(text.contains("Verbal Fluency"))
        XCTAssertTrue(text.contains("Story Recall"))
        XCTAssertTrue(text.contains("Word Recall"))
        XCTAssertFalse(text.contains("nil"))
    }

    func testGreenTier_score75_lowBanner() {
        let state = AssessmentState()
        state.qmciState = makeQmciState(
            orientation: 9, registration: 5, clock: 13,
            fluencyUnique: 14, logicalUnits: 11, delayedWords: 3)
        state.qdrsState = makeQDRS(positive: false)
        state.compositeRisk = CompositeRiskOutput(
            tier: .low,
            label: "Low Risk — Concordant Negative",
            summaryLine: "Qmci 75/100 and QDRS negative",
            narrative: "Concordant negative findings.",
            suggestedActions: ["Continue routine monitoring"]
        )

        XCTAssertEqual(state.qmciState.totalScore, 75,
                       "Fixture must produce totalScore=75")

        let data = PDFReportGenerator.generate(from: state)
        XCTAssertGreaterThan(data.count, 500)

        let text = pdfText(from: data)
        XCTAssertTrue(text.contains("LOW RISK"),
                      "Missing LOW RISK banner. Text: \(text.prefix(400))")
        XCTAssertTrue(text.contains("75"))
        XCTAssertTrue(text.contains("Orientation"))
        XCTAssertTrue(text.contains("Word Learning"))
        XCTAssertTrue(text.contains("Clock Drawing"))
        XCTAssertTrue(text.contains("Verbal Fluency"))
        XCTAssertTrue(text.contains("Story Recall"))
        XCTAssertTrue(text.contains("Word Recall"))
        XCTAssertFalse(text.contains("nil"))
    }
}

// MARK: - TEST 3a — partial PDF inspection

@MainActor
final class PartialPDFTests: XCTestCase {

    func testAbandonedSilence_twoOfSixSubtests() {
        let state = AssessmentState()
        state.qmciState.orientationScores = [2, 2, 1, nil, nil]
        state.qmciState.registrationRecalledWords = ["w0", "w1", "w2"]

        let abandonedAt = Date(timeIntervalSince1970: 1_776_200_000)
        let completed: [Phase] = [.qmciOrientation, .qmciRegistration]
        let data = PartialScoreReport.generate(
            state: state,
            reason: .abandonedSilence,
            completed: completed,
            policy: .showCompletedOnly,
            abandonedAt: abandonedAt
        )

        XCTAssertGreaterThan(data.count, 500)
        let text = pdfText(from: data)

        XCTAssertTrue(text.contains("ASSESSMENT INCOMPLETE"),
                      "Missing incomplete banner. Text: \(text.prefix(500))")
        XCTAssertTrue(text.contains("NOT SCORABLE"),
                      "Missing NOT SCORABLE banner text")
        XCTAssertTrue(text.contains("Orientation"))
        XCTAssertTrue(text.contains("Word Learning"))

        XCTAssertFalse(text.contains("HIGH RISK"))
        XCTAssertFalse(text.contains("INTERMEDIATE RISK"))
        XCTAssertFalse(text.contains("LOW RISK"))
        XCTAssertFalse(text.contains("/100"),
                       "Should not show a composite /100 score")

        // Reason language
        XCTAssertTrue(
            text.contains("silence") || text.contains("150"),
            "Should mention 150s silence reason. Text: \(text.prefix(500))")

        // Timestamp
        XCTAssertTrue(
            text.contains("Ended at:") ||
            text.localizedCaseInsensitiveContains("ended"),
            "Should include abandoned timestamp. Text: \(text.prefix(500))")

        // Uncompleted subtests must NOT be listed
        XCTAssertFalse(text.contains("Verbal Fluency"))
        XCTAssertFalse(text.contains("Story Recall"))
        XCTAssertFalse(text.contains("Word Recall"))
        XCTAssertFalse(text.contains("Clock Drawing"))
    }
}

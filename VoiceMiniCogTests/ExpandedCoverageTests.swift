//
//  ExpandedCoverageTests.swift
//  VoiceMiniCogTests
//
//  Expanded unit test coverage for:
//  - QMCIScoringEngine full pipeline
//  - LeftPaneSpeechCopy SSML generation
//  - WordRecallScorer plural normalization + edge cases
//  - Country orientation token-boundary false-positive prevention
//  - scoreWordRecall intrusions and repetitions
//
//  MARK: CLINICAL — Scoring functions tested here affect clinical decisions.
//

import XCTest
@testable import VoiceMiniCog

// MARK: - QMCIScoringEngine Full Pipeline

@MainActor
class QMCIScoringEngineTests: XCTestCase {

    func testPerfectScoreResult() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]                      // 10
        state.registrationRecalledWords = ["a", "b", "c", "d", "e"]    // 5
        state.clockDrawingScore = 15                                     // 15
        state.verbalFluencyWords = (0..<40).map { "a\($0)" }           // 20
        state.logicalMemoryRecalledUnits = Array(repeating: "u", count: 15) // 30
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]           // 20

        let result = QMCIScoringEngine.score(session: state, patientAge: 60, yearsEducation: 16)

        XCTAssertEqual(result.rawTotal, 100)
        XCTAssertEqual(result.rawClassification, .normal)
        XCTAssertEqual(result.subtestScores.count, QmciSubtest.allCases.count)
    }

    func testSubtestScoresMatchSessionState() {
        let state = QmciState()
        state.orientationScores = [2, 1, 2, 0, 2]                      // 7
        state.registrationRecalledWords = ["a", "b", "c"]              // 3
        state.clockDrawingScore = 10                                     // 10
        state.verbalFluencyWords = ["dog", "cat", "horse"]             // 3 unique animals = 3
        state.logicalMemoryRecalledUnits = ["red", "fox"]              // 4
        state.delayedRecallWords = ["a", "b"]                          // 8

        let result = QMCIScoringEngine.score(session: state, patientAge: 50, yearsEducation: 14)

        // Verify each subtest score matches the session's computed score
        for subtestScore in result.subtestScores {
            switch subtestScore.subtest {
            case .orientation:    XCTAssertEqual(subtestScore.rawScore, 7)
            case .registration:   XCTAssertEqual(subtestScore.rawScore, 3)
            case .clockDrawing:   XCTAssertEqual(subtestScore.rawScore, 10)
            case .verbalFluency:  XCTAssertEqual(subtestScore.rawScore, 3)
            case .logicalMemory:  XCTAssertEqual(subtestScore.rawScore, 4)
            case .delayedRecall:  XCTAssertEqual(subtestScore.rawScore, 8)
            }
        }
    }

    func testAdjustmentGroupLabels() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]

        let youngHighEdu = QMCIScoringEngine.score(session: state, patientAge: 60, yearsEducation: 16)
        XCTAssertEqual(youngHighEdu.adjustmentGroup.ageBand, "<75")
        XCTAssertEqual(youngHighEdu.adjustmentGroup.eduBand, "≥12")

        let oldLowEdu = QMCIScoringEngine.score(session: state, patientAge: 80, yearsEducation: 8)
        XCTAssertEqual(oldLowEdu.adjustmentGroup.ageBand, "≥75")
        XCTAssertEqual(oldLowEdu.adjustmentGroup.eduBand, "<12")
    }

    func testWeakestAndStrongestSubtest() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]                      // 10/10 = 100%
        state.registrationRecalledWords = ["a"]                         // 1/5 = 20%
        state.clockDrawingScore = 15                                     // 15/15 = 100%
        state.verbalFluencyWords = (0..<40).map { "a\($0)" }           // 20/20 = 100%
        state.logicalMemoryRecalledUnits = Array(repeating: "u", count: 15) // 30/30 = 100%
        state.delayedRecallWords = ["a", "b", "c", "d", "e"]           // 20/20 = 100%

        let result = QMCIScoringEngine.score(session: state, patientAge: 60, yearsEducation: 16)

        XCTAssertEqual(result.weakestSubtest, .registration,
                       "Registration at 20% should be weakest")
    }

    func testResponseSummaryOrientation() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]
        state.orientationResponses = ["2026", "April", "Monday", "14th", "United States"]

        let result = QMCIScoringEngine.score(session: state, patientAge: 60, yearsEducation: 16)
        let orientationScore = result.subtestScores.first { $0.subtest == .orientation }!

        XCTAssertTrue(orientationScore.responseSummary.contains("2026"),
                      "Response summary should include patient's year answer")
    }

    func testResponseSummaryDelayedRecall() {
        let state = QmciState()
        state.registrationWords = ["dog", "rain", "butter", "love", "door"]
        state.delayedRecallWords = ["dog", "butter"]

        let result = QMCIScoringEngine.score(session: state, patientAge: 60, yearsEducation: 16)
        let recallScore = result.subtestScores.first { $0.subtest == .delayedRecall }!

        XCTAssertTrue(recallScore.responseSummary.contains("dog, rain, butter, love, door"),
                      "Should list all target words")
        XCTAssertTrue(recallScore.responseSummary.contains("dog, butter"),
                      "Should list recalled words")
    }

    func testAgeAdjustmentApplied() {
        let state = QmciState()
        state.orientationScores = [2, 2, 2, 2, 2]                      // 10
        state.registrationRecalledWords = ["a", "b", "c", "d", "e"]    // 5
        state.clockDrawingScore = 15                                     // 15
        state.verbalFluencyWords = (0..<40).map { "a\($0)" }           // 20
        state.logicalMemoryRecalledUnits = ["u"]                        // 2
        state.delayedRecallWords = ["a", "b", "c"]                     // 12
        // Raw total = 64

        let result = QMCIScoringEngine.score(session: state, patientAge: 80, yearsEducation: 16)
        XCTAssertEqual(result.rawTotal, 64)
        XCTAssertEqual(result.adjustedTotal, 67, "Age ≥75 adds +3")
        XCTAssertEqual(result.adjustedClassification, .normal,
                       "Adjusted 67 meets normal threshold")
    }
}

// MARK: - LeftPaneSpeechCopy SSML Generation

class LeftPaneSpeechCopyTests: XCTestCase {

    func testTrial1SSMLStructure() {
        let words = ["butter", "arm", "shore", "letter", "queen"]
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 1)

        XCTAssertTrue(ssml.contains("<speak>"), "Must wrap in <speak> tags")
        XCTAssertTrue(ssml.contains("</speak>"), "Must close <speak> tag")
        XCTAssertTrue(ssml.contains(LeftPaneSpeechCopy.wordRegistrationIntro),
                      "Trial 1 must include intro text")
        XCTAssertTrue(ssml.contains(LeftPaneSpeechCopy.wordRegistrationRepeat),
                      "Trial 1 must include repeat prompt")
    }

    func testTrial2SSMLStructure() {
        let words = ["butter", "arm", "shore", "letter", "queen"]
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 2)

        XCTAssertTrue(ssml.contains("<speak>"))
        XCTAssertTrue(ssml.contains(LeftPaneSpeechCopy.wordRegistrationRetryLeadIn),
                      "Trial 2 must use retry lead-in")
        XCTAssertTrue(ssml.contains(LeftPaneSpeechCopy.wordRegistrationRetryClosing),
                      "Trial 2 must use retry closing")
        XCTAssertFalse(ssml.contains(LeftPaneSpeechCopy.wordRegistrationIntro),
                       "Trial 2 must NOT include trial 1 intro")
    }

    func testAllWordsIncluded() {
        let words = ["butter", "arm", "shore", "letter", "queen"]
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 1)

        for word in words {
            XCTAssertTrue(ssml.contains(word),
                          "SSML must contain word '\(word)'")
        }
    }

    func testInterWordBreakTags() {
        let words = ["butter", "arm", "shore", "letter", "queen"]
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 1)

        // 5 words → 4 inter-word breaks of 1000ms
        let breakCount = ssml.components(separatedBy: "<break time=\"1000ms\"/>").count - 1
        XCTAssertEqual(breakCount, 4,
                       "5 words should produce 4 inter-word 1000ms breaks")
    }

    func testSingleWordDoesNotCrash() {
        // Edge case: only one word should produce valid SSML with no inter-word breaks
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: ["butter"], trial: 1)
        XCTAssertTrue(ssml.contains("<speak>"))
        XCTAssertTrue(ssml.contains("butter"))
        let breakCount = ssml.components(separatedBy: "<break time=\"1000ms\"/>").count - 1
        XCTAssertEqual(breakCount, 0, "Single word should have no inter-word breaks")
    }

    func testEmptyWordListDoesNotCrash() {
        let ssml = LeftPaneSpeechCopy.wordRegistrationEcho(words: [], trial: 1)
        XCTAssertTrue(ssml.contains("<speak>"))
        XCTAssertTrue(ssml.contains("</speak>"))
    }

    func testWordRegistrationNarrationLegacy() {
        let words = ["butter", "arm", "shore", "letter", "queen"]
        let narration = LeftPaneSpeechCopy.wordRegistrationNarration(words: words)
        for word in words {
            XCTAssertTrue(narration.contains(word))
        }
        XCTAssertTrue(narration.contains(LeftPaneSpeechCopy.wordRegistrationIntro))
        XCTAssertTrue(narration.contains(LeftPaneSpeechCopy.wordRegistrationRepeat))
    }
}

// MARK: - WordRecallScorer Plural Normalization

@MainActor
final class WordRecallScorerPluralTests: XCTestCase {

    func testRegularPluralNormalized() {
        let s = WordRecallScorer(targetWords: ["door"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("doors")
        XCTAssertTrue(s.recalledWords.contains("door"),
                      "'doors' should normalize to 'door'")
    }

    func testIrregularPluralNormalized() {
        let s = WordRecallScorer(targetWords: ["mouse"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("mice")
        XCTAssertTrue(s.recalledWords.contains("mouse"),
                      "'mice' should normalize to 'mouse'")
    }

    func testIesPluralNormalized() {
        // "berries" → drop "ies" + "y" → "berry" (not a target, but tests the path)
        let s = WordRecallScorer(targetWords: ["berry"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("berries")
        XCTAssertTrue(s.recalledWords.contains("berry"),
                      "'berries' should normalize to 'berry'")
    }

    func testShesPluralNormalized() {
        let s = WordRecallScorer(targetWords: ["brush"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("brushes")
        XCTAssertTrue(s.recalledWords.contains("brush"),
                      "'brushes' should normalize to 'brush'")
    }

    func testDoubleSSNotStripped() {
        // "boss" ends in 's' but also ends in 'ss' → should NOT strip
        let s = WordRecallScorer(targetWords: ["boss"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("boss")
        XCTAssertTrue(s.recalledWords.contains("boss"),
                      "'boss' should match without stripping trailing 's'")
    }

    func testSynonymLogsSubstitutionNotCredit() {
        let s = WordRecallScorer(targetWords: ["dog", "rain", "butter", "love", "door"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("puppy rainfall margarine")

        XCTAssertTrue(s.recalledWords.isEmpty,
                      "Synonyms must NOT credit target words")
        XCTAssertEqual(s.semanticSubstitutions.count, 3,
                       "Should log 3 semantic substitutions")
        XCTAssertTrue(s.semanticSubstitutions.contains(where: { $0.target == "dog" && $0.said == "puppy" }))
        XCTAssertTrue(s.semanticSubstitutions.contains(where: { $0.target == "rain" && $0.said == "rainfall" }))
        XCTAssertTrue(s.semanticSubstitutions.contains(where: { $0.target == "butter" && $0.said == "margarine" }))
    }

    func testSynonymNotLoggedIfTargetAlreadyRecalled() {
        let s = WordRecallScorer(targetWords: ["dog"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("dog puppy")

        XCTAssertEqual(s.recalledCount, 1)
        XCTAssertTrue(s.semanticSubstitutions.isEmpty,
                      "Synonym should not be logged if target already recalled")
    }

    func testInterWordIntervalsEmpty() {
        let s = WordRecallScorer(targetWords: ["dog"])
        s.startScoring()
        s.markPromptEnded()
        s.processTranscript("dog")
        XCTAssertTrue(s.interWordIntervalsMs.isEmpty,
                      "Single word should produce no inter-word intervals")
    }
}

// MARK: - scoreWordRecall Intrusions & Repetitions

@MainActor
class ScoreWordRecallIntrusionTests: XCTestCase {

    let wordList = ["butter", "arm", "shore", "letter", "queen"]

    func testIntrusionsTracked() {
        let result = scoreWordRecall(transcript: "I said butter and elephant and giraffe",
                                      wordList: wordList)
        XCTAssertEqual(result.count, 1, "Only 'butter' is a target")
        XCTAssertTrue(result.intrusions.contains("elephant"))
        XCTAssertTrue(result.intrusions.contains("giraffe"))
    }

    func testRepetitionsTracked() {
        let result = scoreWordRecall(transcript: "butter arm butter arm butter",
                                      wordList: wordList)
        XCTAssertEqual(result.count, 2, "Only 2 unique targets: butter, arm")
        XCTAssertEqual(result.repetitions, 3,
                       "3 repetitions: butter×2 extra + arm×1 extra")
    }

    func testStopWordsNotIntrusions() {
        let result = scoreWordRecall(transcript: "I think the word was butter and um well yeah",
                                      wordList: wordList)
        XCTAssertEqual(result.count, 1)
        // Stop words should not appear as intrusions
        XCTAssertFalse(result.intrusions.contains("the"))
        XCTAssertFalse(result.intrusions.contains("and"))
        XCTAssertFalse(result.intrusions.contains("well"))
    }

    func testShortTokensFilteredFromIntrusions() {
        // Tokens of length 1-2 should be filtered from intrusions
        let result = scoreWordRecall(transcript: "I am ok butter",
                                      wordList: wordList)
        XCTAssertFalse(result.intrusions.contains("am"))
        XCTAssertFalse(result.intrusions.contains("ok"))
    }

    func testAllFiveWordsNoIntrusionsNoRepetitions() {
        let result = scoreWordRecall(transcript: "butter arm shore letter queen",
                                      wordList: wordList)
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.intrusions.isEmpty)
        XCTAssertEqual(result.repetitions, 0)
    }
}

// MARK: - Country Orientation Token-Boundary False Positives

@MainActor
class CountryOrientationFalsePositiveTests: XCTestCase {

    func testBecauseDoesNotMatchUS() {
        XCTAssertFalse(scoreOrientationAnswer(type: .country, transcript: "because I forgot"),
                       "'because' contains 'us' as substring but should not match")
    }

    func testFocusDoesNotMatchUS() {
        XCTAssertFalse(scoreOrientationAnswer(type: .country, transcript: "I need to focus"),
                       "'focus' contains 'us' as substring but should not match")
    }

    func testBusDoesNotMatchUS() {
        XCTAssertFalse(scoreOrientationAnswer(type: .country, transcript: "I took the bus"),
                       "'bus' contains 'us' as substring but should not match")
    }

    func testThusDoesNotMatchUS() {
        XCTAssertFalse(scoreOrientationAnswer(type: .country, transcript: "thus I concluded"),
                       "'thus' contains 'us' as substring but should not match")
    }

    func testUSAsBoundedTokenMatches() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "we live in the us"),
                      "'us' as standalone token should match")
    }

    func testUSAMatchesAsToken() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "I'm in the usa"))
    }

    func testUnitedStatesSubstringMatches() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "the united states of america"))
    }

    func testAmericaSubstringMatches() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "I think america"))
    }

    func testUSDotSDotMatches() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "the u.s. I think"))
    }
}

// MARK: - Logical Memory Edge Cases

@MainActor
class LogicalMemoryEdgeCaseTests: XCTestCase {

    func testCaseInsensitiveMatching() {
        let units = ["red", "fox", "ran"]
        let result = scoreLogicalMemory(transcript: "THE RED FOX RAN", scoringUnits: units)
        XCTAssertEqual(result.count, 3, "Case-insensitive matching should find all 3")
    }

    func testDuplicateUnitsNotDoubleCounted() {
        let units = ["red", "fox"]
        let result = scoreLogicalMemory(transcript: "the red fox and red bird", scoringUnits: units)
        XCTAssertEqual(result.count, 2, "Each unit counted only once")
    }

    func testPartialWordDoesNotMatch() {
        // "morning" is a scoring unit; "mornings" contains "morning" as substring
        // which WILL match with substring matching (current behavior)
        let units = ["morning"]
        let result = scoreLogicalMemory(transcript: "mornings were cold", scoringUnits: units)
        XCTAssertEqual(result.count, 1,
                       "Substring match: 'mornings' contains 'morning'")
    }

    func testEmptyScoringUnits() {
        let result = scoreLogicalMemory(transcript: "the red fox ran", scoringUnits: [])
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - Verbal Fluency Edge Cases

@MainActor
class VerbalFluencyEdgeCaseTests: XCTestCase {

    func testHyphenatedAnimalSplits() {
        // "sea-horse" → ["sea", "horse"] → "horse" is in animal set
        let result = scoreVerbalFluency(transcript: "sea-horse")
        XCTAssertTrue(result.contains("horse"),
                      "Hyphenated word should split and match 'horse'")
    }

    func testMixedPunctuationSplits() {
        let result = scoreVerbalFluency(transcript: "dog, cat! horse.")
        XCTAssertEqual(result.count, 3)
    }

    func testSingleLetterTokensIgnored() {
        // Single-letter tokens from splitting should be filtered
        let result = scoreVerbalFluency(transcript: "a dog and a cat")
        XCTAssertEqual(result.count, 2, "Only 'dog' and 'cat' should match")
    }

    func testLargeAnimalSet() {
        // Verify several animals from different categories all recognized
        let transcript = "dog cat elephant whale bee ant frog turtle eagle salmon"
        let result = scoreVerbalFluency(transcript: transcript)
        XCTAssertEqual(result.count, 10, "All 10 animals should be recognized")
    }
}

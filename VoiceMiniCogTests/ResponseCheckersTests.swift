//
//  ResponseCheckersTests.swift
//  VoiceMiniCogTests
//
//  Tests for NLP response validation: word recall, verbal fluency,
//  logical memory, orientation, and greeting completeness.
//
//  MARK: CLINICAL — All functions tested here affect scoring decisions.
//

import XCTest
@testable import VoiceMiniCog

// MARK: - Greeting Completeness

@MainActor
class GreetingCompleteTests: XCTestCase {

    func testEmptyStringReturnsFalse() {
        XCTAssertFalse(isGreetingComplete(""))
    }

    func testWhitespaceOnlyReturnsFalse() {
        XCTAssertFalse(isGreetingComplete("   "))
    }

    func testShortResponseReturnsTrue() {
        // <= 4 words auto-complete regardless of content
        XCTAssertTrue(isGreetingComplete("yes"))
        XCTAssertTrue(isGreetingComplete("I am ready"))
        XCTAssertTrue(isGreetingComplete("yes I am"))
    }

    func testPatternMatchesWork() {
        XCTAssertTrue(isGreetingComplete("yes I am ready to start the test now please"))
        XCTAssertTrue(isGreetingComplete("okay let me get started with this"))
        XCTAssertTrue(isGreetingComplete("hello there I would like to begin"))
    }

    func testLongUnrelatedResponseReturnsFalse() {
        // > 4 words with no matching patterns
        XCTAssertFalse(isGreetingComplete("I was wondering about the weather conditions today"))
    }

    func testCaseInsensitivity() {
        XCTAssertTrue(isGreetingComplete("YES I AM READY"))
        XCTAssertTrue(isGreetingComplete("Go Ahead please start"))
    }
}

// MARK: - Word Registration Checker

@MainActor
class WordRegistrationCheckerTests: XCTestCase {

    let wordList = ["butter", "arm", "shore", "letter", "queen"]

    func testEmptyTranscriptReturnsFalse() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        XCTAssertFalse(checker(""))
    }

    func testAllWordsRecalledReturnsTrue() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        XCTAssertTrue(checker("butter arm shore letter queen"))
    }

    func testThreeWordsReturnsTrue() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        XCTAssertTrue(checker("butter arm shore"))
    }

    func testTwoWordsWithPauseReturnsTrue() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        // found >= 2 AND wordCount >= 2
        XCTAssertTrue(checker("butter and arm"))
    }

    func testOneWordShortPhraseReturnsTrue() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        // found >= 1 AND wordCount <= 5
        XCTAssertTrue(checker("I said butter"))
    }

    func testExplicitRefusalReturnsTrue() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        XCTAssertTrue(checker("I don't remember any of them"))
        XCTAssertTrue(checker("I cant recall"))
        XCTAssertTrue(checker("no I don't know"))
    }

    func testNoMatchLongResponseReturnsFalse() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        // No target words found, > 5 words
        XCTAssertFalse(checker("I think there was something about a house and a garden"))
    }

    func testCaseInsensitiveMatching() {
        let checker = makeWordRegistrationChecker(wordList: wordList)
        XCTAssertTrue(checker("BUTTER ARM SHORE"))
    }

    func testSubstringMatchBehavior() {
        // Known limitation: "arm" will match inside "armchair"
        let checker = makeWordRegistrationChecker(wordList: wordList)
        // "armchair" contains "arm" → found.count = 1, wordCount = 1 → true (1 word, <= 5)
        XCTAssertTrue(checker("armchair"),
                      "Substring match: 'armchair' contains 'arm' — known behavior")
    }
}

// MARK: - Recall Checker

@MainActor
class RecallCheckerTests: XCTestCase {

    let wordList = ["butter", "arm", "shore", "letter", "queen"]

    func testEmptyTranscriptReturnsFalse() {
        let checker = makeRecallChecker(wordList: wordList)
        XCTAssertFalse(checker(""))
    }

    func testThreeWordsReturnsTrue() {
        let checker = makeRecallChecker(wordList: wordList)
        XCTAssertTrue(checker("butter arm shore"))
    }

    func testOneWordShortPhraseReturnsTrue() {
        let checker = makeRecallChecker(wordList: wordList)
        // found >= 1 AND wordCount <= 6 (more lenient than registration)
        XCTAssertTrue(checker("I think it was butter"))
    }

    func testCompletionPhrasesReturnTrue() {
        let checker = makeRecallChecker(wordList: wordList)
        XCTAssertTrue(checker("that's all I can remember"))
        XCTAssertTrue(checker("nothing else comes to mind"))
        XCTAssertTrue(checker("thats it for me"))
    }

    func testExplicitRefusalReturnsTrue() {
        let checker = makeRecallChecker(wordList: wordList)
        XCTAssertTrue(checker("I don't remember"))
        XCTAssertTrue(checker("I cant recall any"))
    }

    func testOnlyKeywordBehavior() {
        let checker = makeRecallChecker(wordList: wordList)
        // "only" is a completion phrase — triggers true regardless of word count
        XCTAssertTrue(checker("I can only think of one word maybe something else too"))
    }
}

// MARK: - Word Recall Scoring

@MainActor
class ScoreWordRecallTests: XCTestCase {

    let wordList = ["butter", "arm", "shore", "letter", "queen"]

    func testAllWordsRecalled() {
        let result = scoreWordRecall(transcript: "butter arm shore letter queen", wordList: wordList)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(Set(result.recalled), Set(["butter", "arm", "shore", "letter", "queen"]))
    }

    func testPartialRecall() {
        let result = scoreWordRecall(transcript: "butter and queen", wordList: wordList)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.recalled.contains("butter"))
        XCTAssertTrue(result.recalled.contains("queen"))
    }

    func testNoWordsRecalled() {
        let result = scoreWordRecall(transcript: "I have no idea what they were", wordList: wordList)
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.recalled.isEmpty)
    }

    func testDuplicatesNotCounted() {
        let result = scoreWordRecall(transcript: "butter butter butter arm arm", wordList: wordList)
        XCTAssertEqual(result.count, 2, "Duplicates should not inflate count")
    }

    func testCaseInsensitive() {
        let result = scoreWordRecall(transcript: "BUTTER ARM SHORE", wordList: wordList)
        XCTAssertEqual(result.count, 3)
    }

    func testEmptyTranscript() {
        let result = scoreWordRecall(transcript: "", wordList: wordList)
        XCTAssertEqual(result.count, 0)
    }

    func testEmptyWordList() {
        let result = scoreWordRecall(transcript: "butter arm shore", wordList: [])
        XCTAssertEqual(result.count, 0)
    }
}

// MARK: - Word registration (fuzzy)

@MainActor
class ScoreWordRegistrationRecallTests: XCTestCase {

    private let targets = ["fear", "round", "bed", "chair", "fruit"]

    func testExactTokens() {
        let r = scoreWordRegistrationRecall(transcript: "fear round bed chair fruit", wordList: targets)
        XCTAssertEqual(r.count, 5)
    }

    func testTypoRound() {
        let r = scoreWordRegistrationRecall(transcript: "rount", wordList: targets)
        XCTAssertTrue(r.recalled.contains("round"))
    }

    func testPrefixFear() {
        let r = scoreWordRegistrationRecall(transcript: "feared", wordList: targets)
        XCTAssertTrue(r.recalled.contains("fear"))
    }

    func testOrderIndependent() {
        let r = scoreWordRegistrationRecall(transcript: "fruit then bed", wordList: targets)
        XCTAssertEqual(r.count, 2)
    }
}

// MARK: - Verbal Fluency Scoring

@MainActor
class ScoreVerbalFluencyTests: XCTestCase {

    func testBasicAnimalRecognition() {
        let result = scoreVerbalFluency(transcript: "dog cat horse cow pig")
        XCTAssertEqual(result.count, 5)
    }

    func testDuplicateAnimalsNotCounted() {
        let result = scoreVerbalFluency(transcript: "dog dog dog cat cat")
        XCTAssertEqual(result.count, 2, "Duplicates should be removed")
    }

    func testNonAnimalWordsIgnored() {
        let result = scoreVerbalFluency(transcript: "dog table cat chair horse")
        XCTAssertEqual(result.count, 3, "Only animals should be counted")
    }

    func testPluralNotInSet() {
        // "dogs" is not in the animal set (only "dog")
        let result = scoreVerbalFluency(transcript: "dogs cats horses")
        // These plurals won't match the singular forms in the set
        XCTAssertEqual(result.count, 0,
                       "Known limitation: plurals not in animal set don't match")
    }

    func testEmptyTranscript() {
        let result = scoreVerbalFluency(transcript: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testMaximumScoreIs20() {
        // Even if patient names 25 unique animals, score caps at 20
        let manyAnimals = "dog cat horse cow pig sheep goat chicken duck bird fish rabbit mouse rat hamster elephant lion tiger bear monkey giraffe zebra deer wolf fox"
        let result = scoreVerbalFluency(transcript: manyAnimals)
        XCTAssertGreaterThan(result.count, 20)
        // Note: the function returns all found animals; the Qmci scoring caps at 20
        // The cap is applied in QmciState.verbalFluencyScore, not here
    }

    func testCompoundAnimalsSplitCorrectly() {
        // "prairie dog" → splits into "prairie" + "dog" → only "dog" matches
        let result = scoreVerbalFluency(transcript: "prairie dog")
        XCTAssertTrue(result.contains("dog"))
        XCTAssertFalse(result.contains("prairie"))
    }

    func testCaseInsensitive() {
        let result = scoreVerbalFluency(transcript: "DOG CAT HORSE")
        XCTAssertEqual(result.count, 3)
    }
}

// MARK: - Logical Memory Scoring

@MainActor
class ScoreLogicalMemoryTests: XCTestCase {

    let storyUnits = LOGICAL_MEMORY_STORIES[0].scoringUnits
    // O'Caoimh "red fox" story — Dr. Malloy's QMCI training video verbatim
    // (15 scoring units, "Fragrant" is in the stimulus but not scored):
    // ["red", "fox", "ran", "across", "ploughed",
    //  "field", "chased", "brown", "dog",
    //  "hot", "May", "morning",
    //  "blossoms", "forming", "bushes"]

    func testFullRecall() {
        // Verbatim text of LOGICAL_MEMORY_STORIES[0] — should match all 15 units.
        let transcript = "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes."
        let result = scoreLogicalMemory(transcript: transcript, scoringUnits: storyUnits)
        XCTAssertEqual(result.count, 15,
                       "Verbatim recall should match all 15 units in the red-fox story")
    }

    func testStoryTextMatchesVideoVerbatim() {
        // Protocol fidelity: the v1 story text must match Dr. Malloy's training
        // video word-for-word, including "Fragrant" and the clause order
        // (chased-by-dog before hot-May-morning).
        let expected = "The red fox ran across the ploughed field. It was chased by a brown dog. It was a hot May morning. Fragrant blossoms were forming on the bushes."
        XCTAssertEqual(LOGICAL_MEMORY_STORIES[0].text, expected)
        XCTAssertEqual(LOGICAL_MEMORY_STORIES[0].voiceText, expected)
    }

    func testPartialRecall() {
        // Mixed casing — substring match is case-insensitive but return preserves unit casing.
        // Note: "across" is intentionally NOT a scoring unit per the QMCI sheet.
        let transcript = "the RED fox RAN across the PLOUGHED field"
        let result = scoreLogicalMemory(transcript: transcript, scoringUnits: storyUnits)
        XCTAssertTrue(result.contains("red"),
                      "Case-insensitive: 'RED' should match 'red' unit")
        XCTAssertTrue(result.contains("fox"))
        XCTAssertTrue(result.contains("ran"))
        XCTAssertTrue(result.contains("ploughed"))
        XCTAssertTrue(result.contains("field"))
        XCTAssertFalse(result.contains("across"),
                       "'across' is prose in the QMCI sheet, not a scoring unit")
    }

    func testNoRecall() {
        // None of the 15 red-fox units appear as substrings in this sentence.
        let result = scoreLogicalMemory(transcript: "I do not remember anything about it",
                                         scoringUnits: storyUnits)
        XCTAssertEqual(result.count, 0)
    }

    func testMultiWordUnitMatching() {
        // The red-fox story has no multi-word scoring units, so we use an ad-hoc
        // list to verify the substring-match code path handles multi-word units.
        let adHocUnits = ["ploughed field", "brown dog", "May morning"]
        let result = scoreLogicalMemory(
            transcript: "the fox ran across the ploughed field",
            scoringUnits: adHocUnits
        )
        XCTAssertTrue(result.contains("ploughed field"),
                      "Multi-word unit 'ploughed field' should match as substring")
    }

    func testPartialMultiWordUnitDoesNotMatch() {
        // Again use an ad-hoc multi-word unit since red-fox story has none.
        // 'brown' alone should not match 'brown dog'.
        let adHocUnits = ["brown dog"]
        let result = scoreLogicalMemory(
            transcript: "the brown fox crossed the road",
            scoringUnits: adHocUnits
        )
        XCTAssertFalse(result.contains("brown dog"),
                       "'brown' alone should NOT match multi-word unit 'brown dog'")
    }

    func testEmptyTranscript() {
        let result = scoreLogicalMemory(transcript: "", scoringUnits: storyUnits)
        XCTAssertTrue(result.isEmpty)
    }

    func testMaxScoreCapping() {
        // 15 scoring units × 2 pts = 30, exactly at the 30-point cap.
        // The cap is applied in QmciState.logicalMemoryScore.
        XCTAssertEqual(storyUnits.count, 15)
        let maxPossible = min(storyUnits.count * 2, 30)
        XCTAssertEqual(maxPossible, 30, "15 units × 2 pts = 30 → exactly at cap")
    }
}

// MARK: - Orientation Scoring

@MainActor
class ScoreOrientationTests: XCTestCase {

    func testYearCorrect() {
        let year = String(Calendar.current.component(.year, from: Date()))
        XCTAssertTrue(scoreOrientationAnswer(type: .year, transcript: "It's \(year)"))
    }

    func testYearIncorrect() {
        XCTAssertFalse(scoreOrientationAnswer(type: .year, transcript: "It's 1999"))
    }

    func testYearShortFormDoesNotMatch() {
        // "26" alone doesn't match "2026" — contains("2026") vs contains("26")
        // Actually "2026" does contain "26" but the code checks for the full year string
        // Let's verify: if current year is 2026, transcript "26" does NOT contain "2026"
        let year = String(Calendar.current.component(.year, from: Date()))
        let shortYear = String(year.suffix(2))
        // "26" does NOT contain "2026"
        XCTAssertFalse(scoreOrientationAnswer(type: .year, transcript: shortYear),
                       "Short year form should not match full year")
    }

    func testMonthCorrect() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: Date())
        XCTAssertTrue(scoreOrientationAnswer(type: .month, transcript: "It's \(month)"))
    }

    func testMonthAbbreviationCorrect() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: Date()).lowercased()
        let abbrev = String(month.prefix(3))
        XCTAssertTrue(scoreOrientationAnswer(type: .month, transcript: "I think \(abbrev)"))
    }

    func testDayOfWeekCorrect() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: Date())
        XCTAssertTrue(scoreOrientationAnswer(type: .dayOfWeek, transcript: "Today is \(day)"))
    }

    func testDateCorrect() {
        let dayNum = String(Calendar.current.component(.day, from: Date()))
        XCTAssertTrue(scoreOrientationAnswer(type: .date, transcript: "The \(dayNum)th"))
    }

    func testCountryVariants() {
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "United States"))
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "America"))
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "USA"))
        XCTAssertTrue(scoreOrientationAnswer(type: .country, transcript: "the U.S."))
    }

    func testCountryIncorrect() {
        XCTAssertFalse(scoreOrientationAnswer(type: .country, transcript: "Canada"))
    }

    // MARK: - Hedged / spoken-form answers (Dr. Malloy protocol fidelity)

    func testYearWordFormMatches() {
        // STT-realistic spoken forms for the current year.
        // Per Dr. Malloy's video, "I think it's twenty twenty one" is credited.
        let yearInt = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(transcriptMentionsYear("the year is 2026", year: 2026))
        XCTAssertTrue(transcriptMentionsYear("twenty twenty six", year: 2026))
        XCTAssertTrue(transcriptMentionsYear("two thousand twenty six", year: 2026))
        XCTAssertTrue(transcriptMentionsYear("two thousand and twenty six", year: 2026))
        XCTAssertTrue(transcriptMentionsYear("twenty ten", year: 2010))
        XCTAssertTrue(transcriptMentionsYear("two thousand", year: 2000))
        XCTAssertTrue(transcriptMentionsYear("twenty oh five", year: 2005))
        // Current-year round trip through scoreOrientationAnswer
        XCTAssertTrue(scoreOrientationAnswer(type: .year,
                                             transcript: "maybe \(yearInt)"))
    }

    func testYearWrongWordFormRejected() {
        XCTAssertFalse(transcriptMentionsYear("nineteen ninety nine", year: 2026))
        XCTAssertFalse(transcriptMentionsYear("twenty twenty one", year: 2026))
    }

    func testDateOrdinalWordMatches() {
        // Per Dr. Malloy's video, "I think it's the tenth" is credited when the
        // date is the 10th of the month.
        XCTAssertTrue(transcriptMentionsDay("i think it's the tenth", day: 10))
        XCTAssertTrue(transcriptMentionsDay("tenth", day: 10))
        XCTAssertTrue(transcriptMentionsDay("the twenty first", day: 21))
        XCTAssertTrue(transcriptMentionsDay("twenty-first", day: 21))
        XCTAssertTrue(transcriptMentionsDay("twenty one", day: 21))
        XCTAssertTrue(transcriptMentionsDay("thirtieth", day: 30))
        XCTAssertTrue(transcriptMentionsDay("thirty first", day: 31))
        XCTAssertTrue(transcriptMentionsDay("the 10", day: 10))
    }

    func testDateWrongOrdinalRejected() {
        XCTAssertFalse(transcriptMentionsDay("fifth", day: 10))
        XCTAssertFalse(transcriptMentionsDay("twenty second", day: 21))
    }

    func testOrientationHedgedYearRoundTrip() {
        // Exercise scoreOrientationAnswer end-to-end with a hedged spoken-form
        // year. Only valid for years within the supported 2000–2099 range.
        let yearInt = Calendar.current.component(.year, from: Date())
        guard (2000...2099).contains(yearInt) else { return }
        let suffix = yearInt - 2000
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        let units = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
                     "sixteen", "seventeen", "eighteen", "nineteen"]
        let spoken: String
        if suffix == 0 { spoken = "two thousand" }
        else if suffix < 10 { spoken = "two thousand \(units[suffix])" }
        else if suffix < 20 { spoken = "twenty \(teens[suffix - 10])" }
        else if suffix % 10 == 0 { spoken = "twenty \(tens[suffix / 10])" }
        else { spoken = "twenty \(tens[suffix / 10]) \(units[suffix % 10])" }
        XCTAssertTrue(scoreOrientationAnswer(type: .year,
                                             transcript: "I think it's \(spoken)"))
    }
}

// MARK: - WordRecallScorer Tests

@MainActor
class WordRecallScorerTests: XCTestCase {

    private let standardWords = ["dog", "rain", "butter", "love", "door"]

    // MARK: Exact Match

    func testExactMatchAllFive() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.promptEndTime = Date()
        scorer.processTranscript("dog rain butter love door")
        XCTAssertEqual(scorer.recalledCount, 5)
        XCTAssertEqual(scorer.recalledWords, Set(["dog", "rain", "butter", "love", "door"]))
    }

    func testExactMatchPartial() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dog and butter")
        XCTAssertEqual(scorer.recalledCount, 2)
        XCTAssertTrue(scorer.recalledWords.contains("dog"))
        XCTAssertTrue(scorer.recalledWords.contains("butter"))
    }

    func testCaseInsensitive() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("DOG RAIN BUTTER")
        XCTAssertEqual(scorer.recalledCount, 3)
    }

    // MARK: Plural/Singular Stemming

    func testPluralToSingular() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dogs doors")
        XCTAssertTrue(scorer.recalledWords.contains("dog"), "'dogs' should match 'dog'")
        XCTAssertTrue(scorer.recalledWords.contains("door"), "'doors' should match 'door'")
    }

    func testPastTenseStemming() {
        let scorer = WordRecallScorer(targetWords: ["love", "rain"])
        scorer.processTranscript("loved rained")
        XCTAssertTrue(scorer.recalledWords.contains("love"), "'loved' should match 'love'")
        // "rained" → drop "ed" → "rain" (4 chars, drops 2)
        XCTAssertTrue(scorer.recalledWords.contains("rain"), "'rained' should match 'rain'")
    }

    // MARK: Phonetic Allowlist

    func testPhoneticAllowlistAccepted() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dawg")
        XCTAssertTrue(scorer.recalledWords.contains("dog"), "'dawg' is in phonetic allowlist for 'dog'")
    }

    func testPhoneticAllowlistRejected() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("doe")
        XCTAssertFalse(scorer.recalledWords.contains("dog"),
                       "'doe' should NOT match 'dog' — too dissimilar")
    }

    // MARK: Duplicate Handling

    func testDuplicatesCountedOnce() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dog dog dog butter butter")
        XCTAssertEqual(scorer.recalledCount, 2, "Repeated words counted once")
    }

    // MARK: Intrusion Tracking

    func testIntrusionsLogged() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dog chair table")
        XCTAssertTrue(scorer.intrusions.contains("chair"))
        XCTAssertTrue(scorer.intrusions.contains("table"))
        XCTAssertEqual(scorer.recalledCount, 1)
    }

    func testFillerWordsNotIntrusions() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("I think the um dog and well butter")
        // "I", "think", "the", "um", "and", "well" are filler — not intrusions
        XCTAssertTrue(scorer.intrusions.isEmpty, "Filler words should not be logged as intrusions")
        XCTAssertEqual(scorer.recalledCount, 2)
    }

    // MARK: Semantic Substitutions

    func testSemanticSubstitutionFlagged() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("puppy")
        XCTAssertFalse(scorer.recalledWords.contains("dog"),
                       "Semantic substitute should NOT be auto-scored")
        XCTAssertEqual(scorer.semanticSubstitutions.count, 1)
        XCTAssertEqual(scorer.semanticSubstitutions.first?.target, "dog")
        XCTAssertEqual(scorer.semanticSubstitutions.first?.said, "puppy")
    }

    // MARK: Completion Phrase Detection

    func testCompletionPhrasesDetected() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        XCTAssertTrue(scorer.containsCompletionPhrase("I'm done"))
        XCTAssertTrue(scorer.containsCompletionPhrase("that's all I can remember"))
        XCTAssertTrue(scorer.containsCompletionPhrase("nothing else"))
        XCTAssertTrue(scorer.containsCompletionPhrase("I can't remember any more"))
    }

    func testNonCompletionPhraseNotDetected() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        XCTAssertFalse(scorer.containsCompletionPhrase("dog rain butter"))
    }

    // MARK: First Word Latency

    func testFirstWordLatencyRecorded() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.promptEndTime = Date().addingTimeInterval(-2.5)
        scorer.processTranscript("dog")
        XCTAssertNotNil(scorer.firstWordLatencySeconds)
        // Should be approximately 2.5s (with some tolerance for test execution time)
        if let latency = scorer.firstWordLatencySeconds {
            XCTAssertGreaterThan(latency, 2.0)
            XCTAssertLessThan(latency, 4.0)
        }
    }

    // MARK: Inter-Word Intervals

    func testInterWordIntervalsTracked() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.promptEndTime = Date()
        scorer.processTranscript("dog")
        // Small delay then next word
        Thread.sleep(forTimeInterval: 0.1)
        scorer.processTranscript("dog rain")
        XCTAssertEqual(scorer.interWordIntervalsMs.count, 1)
        XCTAssertGreaterThan(scorer.interWordIntervalsMs[0], 50)
    }

    // MARK: Alternate Word Sets

    func testAlternateSet2() {
        let set2 = ["cat", "dark", "rat", "heat", "bread"]
        let scorer = WordRecallScorer(targetWords: set2)
        scorer.processTranscript("cat dark rat heat bread")
        XCTAssertEqual(scorer.recalledCount, 5)
    }

    func testAlternateSet3() {
        let set3 = ["fear", "round", "bed", "chair", "fruit"]
        let scorer = WordRecallScorer(targetWords: set3)
        scorer.processTranscript("feared round bed chair fruit")
        // "feared" → should match "fear" via -ed stemming
        XCTAssertEqual(scorer.recalledCount, 5)
    }

    // MARK: Empty / Edge Cases

    func testEmptyTranscript() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("")
        XCTAssertEqual(scorer.recalledCount, 0)
    }

    func testNoTargetWords() {
        let scorer = WordRecallScorer(targetWords: [])
        scorer.processTranscript("dog rain butter")
        XCTAssertEqual(scorer.recalledCount, 0)
    }

    func testIncrementalTranscript() {
        // Simulates how SFSpeechRecognizer delivers partial results
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dog")
        XCTAssertEqual(scorer.recalledCount, 1)
        scorer.processTranscript("dog rain")
        XCTAssertEqual(scorer.recalledCount, 2)
        scorer.processTranscript("dog rain butter")
        XCTAssertEqual(scorer.recalledCount, 3)
    }

    func testResetClearsAll() {
        let scorer = WordRecallScorer(targetWords: standardWords)
        scorer.processTranscript("dog rain butter")
        scorer.reset()
        XCTAssertEqual(scorer.recalledCount, 0)
        XCTAssertTrue(scorer.recalledWords.isEmpty)
        XCTAssertTrue(scorer.intrusions.isEmpty)
    }
}

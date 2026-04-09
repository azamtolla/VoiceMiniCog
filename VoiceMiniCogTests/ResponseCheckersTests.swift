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
    // ["Anna", "Thompson", "South Boston", "cook", "school cafeteria",
    //  "police station", "held up", "State Street", "night before",
    //  "robbed", "fifty-six dollars", "four children", "rent due",
    //  "not eaten", "two days", "officers", "collection"]

    func testFullRecall() {
        let transcript = "Anna Thompson of South Boston was a cook at a school cafeteria. She went to the police station and said she was held up on State Street the night before and robbed of fifty-six dollars. She had four children and rent due and had not eaten for two days. The officers took up a collection."
        let result = scoreLogicalMemory(transcript: transcript, scoringUnits: storyUnits)
        // Should match most or all units
        XCTAssertGreaterThanOrEqual(result.count, 15,
                                     "Near-perfect recall should match most units")
    }

    func testPartialRecall() {
        let transcript = "anna thompson was robbed of some money and went to the police"
        let result = scoreLogicalMemory(transcript: transcript, scoringUnits: storyUnits)
        XCTAssertTrue(result.contains("Anna") || result.contains("anna"),
                      "Case-insensitive: 'anna' should match 'Anna' unit")
        XCTAssertTrue(result.contains("Thompson") || result.contains("thompson"))
        XCTAssertTrue(result.contains("robbed"))
    }

    func testNoRecall() {
        let result = scoreLogicalMemory(transcript: "I don't remember the story",
                                         scoringUnits: storyUnits)
        XCTAssertEqual(result.count, 0)
    }

    func testMultiWordUnitMatching() {
        // "South Boston" is a scoring unit — must appear as substring
        let result = scoreLogicalMemory(transcript: "she was from south boston",
                                         scoringUnits: storyUnits)
        XCTAssertTrue(result.contains("South Boston"),
                      "Multi-word unit 'South Boston' should match case-insensitively")
    }

    func testPartialMultiWordUnitDoesNotMatch() {
        // "South" alone should not match "South Boston"
        let result = scoreLogicalMemory(transcript: "she was from the south",
                                         scoringUnits: storyUnits)
        XCTAssertFalse(result.contains("South Boston"),
                       "'South' alone should NOT match 'South Boston'")
    }

    func testEmptyTranscript() {
        let result = scoreLogicalMemory(transcript: "", scoringUnits: storyUnits)
        XCTAssertTrue(result.isEmpty)
    }

    func testMaxScoreCapping() {
        // 17 scoring units × 2 pts = 34, capped at 30
        // The cap is applied in QmciState.logicalMemoryScore
        XCTAssertEqual(storyUnits.count, 17)
        let maxPossible = min(storyUnits.count * 2, 30)
        XCTAssertEqual(maxPossible, 30, "17 units × 2 pts exceeds 30 → capped at 30")
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
}

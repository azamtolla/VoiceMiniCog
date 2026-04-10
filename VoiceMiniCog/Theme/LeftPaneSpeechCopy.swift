//
//  LeftPaneSpeechCopy.swift
//  VoiceMiniCog
//
//  Centralized text constants for the left panel display AND avatar speech.
//  Single source of truth: the avatar speaks what the left panel shows.
//
//  PERSONA: The avatar IS the neuropsychologist examiner. All voice strings
//  use verbatim QMCI protocol wording from the validation literature.
//  Do not ad-lib, simplify, or paraphrase the examiner scripts.
//

import Foundation

enum LeftPaneSpeechCopy {

    // MARK: - Welcome

    static let welcomeTitle = "Brain Health Assessment"

    static let welcomeSubtitle = "6 cognitive activities, about 3-5 minutes"

    // MARK: - Subtest 1: Orientation (10 pts)

    static let orientationIntro = "I am going to ask you a few questions. Please answer as best you can."

    static let orientationOnScreen = "Please answer the following questions."

    // MARK: - Subtest 2: Word Registration (5 pts)

    static let wordRegistrationTitle = "Listen carefully"

    static let wordRegistrationSubtitle = "I will say some words.\nRepeat them back when asked."

    static let wordRegistrationIntro = "I am going to say some words. After I have said these words, repeat them back to me."

    static func wordRegistrationNarration(words: [String]) -> String {
        // Read words slowly, one per second — joined with pauses
        let wordList = words.joined(separator: " ... ")
        return "\(wordList)."
    }

    static let wordRegistrationRepeat = "Now repeat them back to me."

    static let wordRegistrationRemember = "Remember these words because I'll ask you to recall them later."

    static func wordRegistrationRetry(words: [String]) -> String {
        let wordList = words.joined(separator: " ... ")
        return "Let me say those words again: \(wordList). Now repeat them back to me."
    }

    // MARK: - Subtest 3: Clock Drawing (15 pts, 60 sec)

    // Verbatim QMCI scoring-sheet phrasing (Molloy & O'Caoimh): "ten past eleven".
    // Do not change to "ten minutes after eleven" or "11:10" — the written
    // validation protocol uses this exact wording (single quotes in the sheet).
    static let clockDrawingInstruction = "Draw a clock face and set the time to ten past eleven."

    static let clockDrawingOnScreen = "Draw a clock face.\nSet the time to ten past eleven."

    static let clockDrawingStop = "Please stop drawing now."

    // MARK: - Subtest 4: Delayed Recall (20 pts, 30 sec)

    static let delayedRecallTitle = "Word Recall"

    static let delayedRecallPrompt = "A few minutes ago I said some words. Please name as many words as you can remember."

    static let delayedRecallOnScreen = "Recall the 5 words from earlier."

    // MARK: - Subtest 5: Verbal Fluency (20 pts, 60 sec)

    static let verbalFluencyTitle = "Name as many animals\nas you can"

    static let verbalFluencySubtitle = "You have one minute."

    static let verbalFluencyInstruction = "Name as many animals as you can in one minute."

    // No mid-timer prompts per QMCI protocol — examiner stays silent during timed tasks
    // static let verbalFluencyMidTimer removed — protocol says no hints or prompts

    // MARK: - Subtest 6: Logical Memory (30 pts)

    static let storyRecallListeningTitle = "Listen carefully to\nthis short story"

    static let storyRecallListeningSubtitle = "I will read the story once.\nPay close attention."

    static let storyRecallRecallingTitle = "Tell me as much of the\nstory as you can"

    static let storyRecallRecallingSubtitle = "Take your time.\nRecall as many exact words as possible."

    static let storyRecallIntro = "I am going to read you a short story. When I am finished, tell me as much of the story as you can."

    static let storyRecallPrompt = "Now tell me as much of the story as you can remember."

    static let storyRecallFollowup = "Anything else?"

    // MARK: - Closing

    static let closingThankYou = "That concludes our assessment. Thank you for your time and cooperation today. Your clinician will review the results and discuss them with you at your next visit."

    // MARK: - QDRS (Caregiver Flow)

    static let qdrsIntro = "Thank you for being here today. I have ten brief questions about any changes you may have noticed in the patient's everyday memory and activities. There are no right or wrong answers. Please answer based on what you've observed."

    static let qdrsCompletion = "Thank you for answering those questions. That information is very helpful. The clinician will review your responses."
}

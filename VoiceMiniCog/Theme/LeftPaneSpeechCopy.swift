//
//  LeftPaneSpeechCopy.swift
//  VoiceMiniCog
//
//  Centralized text constants for the left panel display AND avatar speech.
//  Single source of truth: the avatar speaks what the left panel shows.
//

import Foundation

enum LeftPaneSpeechCopy {

    // MARK: - Welcome

    static let welcomeTitle = "Brain Health Assessment"

    static let welcomeSubtitle = "6 cognitive activities, about 5-7 minutes"

    // MARK: - Word Registration

    static let wordRegistrationTitle = "Listen carefully"

    static let wordRegistrationSubtitle = "The avatar will say 5 words.\nRepeat them back when asked."

    static func wordRegistrationNarration(words: [String]) -> String {
        let wordList = words.joined(separator: "... ")
        return "I'm going to read you five words. Please listen carefully and try to remember them — I'll ask you about them again later. The words are: \(wordList)."
    }

    static let wordRegistrationRepeat = "Can you repeat those words for me?"

    static func wordRegistrationRetry(words: [String]) -> String {
        let wordList = words.joined(separator: "... ")
        return "Let me read those words one more time: \(wordList). Can you say those back to me?"
    }

    // MARK: - Orientation

    static let orientationIntro = "First, I'll ask a few general questions — things like today's date and where we are. There are no trick questions. Just answer as best you can."

    // MARK: - Clock Drawing

    static let clockDrawingInstruction = "Now I'd like you to draw a clock face. Put in all twelve numbers. Then draw the hands to show the time eleven ten — like ten minutes after eleven o'clock."

    static let clockDrawingOnScreen = "Draw a clock. Include all 12 numbers.\nSet the hands to 11:10."

    // MARK: - Verbal Fluency

    static let verbalFluencyTitle = "Name as many animals\nas you can"

    static let verbalFluencySubtitle = "You have one minute."

    static let verbalFluencyInstruction = "I'd like you to name as many different animals as you can. You can name any animal — dogs, birds, fish, anything. Try to name as many as you can in one minute. Ready? Begin."

    static let verbalFluencyMidTimer = "Good, keep going."

    // MARK: - Story Recall

    static let storyRecallListeningTitle = "Listen carefully to\nthis short story"

    static let storyRecallListeningSubtitle = "The avatar is reading a story.\nPay close attention."

    static let storyRecallRecallingTitle = "Now tell me everything\nyou remember"

    static let storyRecallRecallingSubtitle = "Take your time. Say everything\nyou can recall."

    static let storyRecallIntro = "I'm going to read you a short story. Listen carefully and try to remember as much of it as you can. When I'm finished, I'll ask you to tell me everything you can recall — even small details. Ready?"

    static let storyRecallPrompt = "Now tell me everything you can remember about that story — start from the beginning and tell me as much as you can."

    static let storyRecallFollowup = "Anything else you can remember?"

    // MARK: - Word Recall

    static let wordRecallTitle = "What were the 5 words?"

    // MARK: - Word Recall

    static let wordRecallPrompt = "What were those five words I asked you to remember earlier?"

    static let wordRecallFollowupPartial = "Can you remember any of the other words?"

    static let wordRecallFollowupZero = "Take your time. Try to think back — can you recall any of the words I asked you to remember?"

    // MARK: - Closing

    static let closingThankYou = "That's everything — thank you so much for your time and effort today. Your clinician will review the results and follow up with you."
}

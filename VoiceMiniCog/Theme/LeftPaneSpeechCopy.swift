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

    /// Tavus overwrite_context for the **welcome screen only** — slower, calmer delivery than conversational TTS.
    /// Echo text still carries SSML `<break/>` tags when supported; this steadies prosody if the engine ignores breaks.
    static let welcomeTavusDeliveryContext = """
    You are a board-certified clinical neuropsychologist welcoming a patient before a standardized cognitive battery. \
    VOICE: warm, neutral, and measured — never performative or chatty. \
    Speak noticeably slower than everyday conversation (roughly 130 to 140 words per minute, not 160+). \
    Keep prosody steady and even — low style exaggeration, not animated or theatrical (think high stability TTS, not expressive). \
    Use the pauses in the echo text; do not compress or run sentences together. \
    Land each sentence as a complete thought with mild downward, declarative intonation at phrase boundaries — no upspeak. \
    Speak ONLY the text sent via echo commands — do not add, omit, or paraphrase any words. \
    Do not add a separate greeting beyond what is in the echo. \
    Never correct, score, or coach the patient during this screen.
    """

    /// Shared Tavus `overwrite_context` fragment — examiner stays neutral; no implicit scoring or coaching.
    static let examinerNeverCorrectPatient = """
    Never correct the patient or judge their answers — do not say right, wrong, close, not quite, actually, or good try; \
    do not repeat their words to evaluate them; do not fix pronunciation or word choice. Stay neutral while they respond; \
    speak only the exact echo text the app sends.
    """

    // MARK: - Subtest 1: Orientation (10 pts)

    static let orientationIntro = "I am going to ask you a few questions. Please answer as best you can."

    static let orientationOnScreen = "Please answer the following questions."

    // MARK: - Subtest 2: Word Registration (5 pts)

    static let wordRegistrationTitle = "Listen carefully"

    /// Shown on the left panel during registration (no target words — auditory-only presentation).
    static let wordRegistrationSubtitle = "Listen to your examiner. Words are not shown until you repeat them."

    static let wordRegistrationIntro = "I am going to say some words. After I have said these words, repeat them back to me."

    /// Trial 1 — full spoken intro (echo). No words from the list in this clip.
    static let wordRegistrationSpokenIntro =
        "I'm going to say five words. I want you to listen carefully and repeat them back to me. Try to remember them, because I'll ask you to recall them again later. Ready?"

    /// Spoken immediately before the first target word (echo).
    static let wordRegistrationWordsAre = "The words are…"

    /// Trials 2–3 — shortened retry intro (echo), then pause, then `wordRegistrationWordsAre`.
    static let wordRegistrationRetryIntro =
        "Let's try again. Listen carefully."

    static func wordRegistrationNarration(words: [String]) -> String {
        // Legacy / AssessmentState — not used for Tavus multi-echo registration flow.
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

    /// Standardized recall prompt — verbatim QMCI protocol wording.
    /// Avatar speaks this; it is NOT shown on the patient screen.
    static let delayedRecallPrompt = "A few minutes ago I read you a list of words and asked you to remember them. Tell me as many of those words as you can remember, in any order."

    /// Single follow-up after patient indicates completion or 60s silence
    static let delayedRecallAnyOthers = "Any others?"

    /// Patient-facing subtitle (calming, non-cueing)
    static let delayedRecallPatientSubtitle = "Take your time."

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

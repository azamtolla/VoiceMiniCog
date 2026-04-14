//
//  LeftPaneSpeechCopy.swift
//  VoiceMiniCog
//
//  Centralized text constants for the left panel display AND avatar speech.
//  Single source of truth: the avatar speaks what the left panel shows.
//
//  PERSONA: The avatar IS the neuropsychologist examiner. Subtest prompts
//  use verbatim QMCI wording (Molloy & O'Caoimh) where marked; transitional
//  and instructional strings may be lightly adapted for TTS delivery.
//  Do not ad-lib, simplify, or paraphrase the examiner scripts.
//

import Foundation

enum LeftPaneSpeechCopy {

    // MARK: - Welcome

    static let welcomeTitle = "Brain Health Assessment"

    static let welcomeSubtitle = "6 cognitive activities, about 3-5 minutes"

    /// Tavus overwrite_context for the **welcome screen only** — slower, calmer delivery than conversational TTS.
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

    // MARK: - Subtest 1: Orientation (10 pts)

    static let orientationIntro = "I am going to ask you a few questions. Please answer as best you can."

    static let orientationOnScreen = "Please answer the following questions."

    // MARK: - Subtest 2: Word Registration (5 pts)

    static let wordRegistrationTitle = "Listen"

    static let wordRegistrationSubtitle = "I will say some words.\nRepeat them back when asked."

    static let wordRegistrationIntro = "I'm going to say five words. Listen carefully and try to remember them."

    /// Spoken alone before each target word (auditory-only registration; one echo per segment).
    /// No trailing period — the per-word echoes provide pacing; a period here
    /// causes some TTS engines to insert an unnaturally long stop.
    static let wordRegistrationWordsLeadIn = "The words are"

    static let wordRegistrationRepeat = "Now repeat them back to me."

    /// Retry trial: lead-in only (words follow as separate echoes).
    static let wordRegistrationRetryLeadIn = "Let me say them again."

    /// Retry trial: closing prompt after the five words.
    static let wordRegistrationRetryClosing = "Now repeat them."

    /// Single SSML echo for word registration — delivers intro, all 5 words with
    /// clinical-grade inter-word pauses, and the repeat prompt in one atomic utterance.
    ///
    /// **Why single-echo?**  The previous multi-segment chain (`playRegistrationEchoSegment`
    /// per word) left `echoInFlight = false` between segments. During that gap the bridge's
    /// auto-interrupt logic could fire (ambient mic noise → VAD → `user.stopped_speaking` →
    /// interrupt), silently disrupting Tavus's TTS pipeline and causing the avatar to go mute
    /// for the remainder of word registration.
    ///
    /// A single `<speak>` block with `<break>` tags keeps `echoInFlight = true` throughout,
    /// the mic stays muted, and auto-interrupts cannot fire — identical to how
    /// `WelcomePhaseView.introScriptForEcho` already works.
    static func wordRegistrationEcho(words: [String], trial: Int) -> String {
        let wordItems = words.map { "\($0)." }.joined(separator: "<break time=\"1000ms\"/> ")
        if trial == 1 {
            return """
            <speak>\
            \(wordRegistrationIntro)<break time="700ms"/> \
            \(wordRegistrationWordsLeadIn): <break time="500ms"/> \
            \(wordItems)<break time="700ms"/> \
            \(wordRegistrationRepeat)\
            </speak>
            """
        } else {
            return """
            <speak>\
            \(wordRegistrationRetryLeadIn)<break time="500ms"/> \
            \(wordItems)<break time="700ms"/> \
            \(wordRegistrationRetryClosing)\
            </speak>
            """
        }
    }

    /// Legacy single-utterance narration (kept for non-avatar flows / reference).
    static func wordRegistrationNarration(words: [String]) -> String {
        let wordList = words.joined(separator: " ... ")
        return "\(wordRegistrationIntro) ... \(wordList). ... \(wordRegistrationRepeat)"
    }

    static let wordRegistrationRemember = "Remember these words because I'll ask you to recall them later."

    static func wordRegistrationRetry(words: [String]) -> String {
        let wordList = words.joined(separator: " ... ")
        return "Let me say them again. ... \(wordList). ... Now repeat them."
    }

    /// Neutral closure when patient got all 5 words — no evaluative language.
    static let wordRegistrationAllCorrect = "Let's continue."

    /// Neutral closure after final trial — no evaluative language.
    static let wordRegistrationDone = "Thank you. Let's continue."

    // MARK: - Examiner Protocol Rules

    /// Appended to avatar context prompts. Enforces the QMCI protocol constraint
    /// that the examiner must never confirm or deny correctness of patient responses.
    static let examinerNeverCorrectPatient = "You must never confirm or deny whether the patient's answer is correct. Never say 'yes', 'right', 'correct', 'good job', or nod approvingly. Do not respond to the patient between echo commands. Remain completely silent unless you receive an echo command."

    // MARK: - Subtest 3: Clock Drawing (15 pts, 60 sec)

    // Verbatim QMCI scoring-sheet phrasing (Molloy & O'Caoimh):
    //   "Draw a clock face, put in all the numbers, and set the hands
    //    to ten past eleven."
    // Do not change to "ten minutes after eleven" or "11:10" — the written
    // validation protocol uses this exact wording (single quotes in the sheet).
    // One canonical instruction used everywhere: spoken, on-screen, and avatar panel.
    static let clockDrawingInstruction = "Draw a clock face, put in all the numbers, and set the hands to ten past eleven."

    static let clockDrawingOnScreen = "Draw a clock face.\nPut in all the numbers.\nSet the hands to ten past eleven."

    /// Same validated instruction — available for avatar panel call sites.
    static let clockDrawingAvatarPanelInstruction = clockDrawingInstruction

    static let clockDrawingStop = "Please stop drawing now."

    /// Tavus `overwrite_context` for the clock-drawing phase only (not the aloud clock instruction string).
    /// Must not contradict `conversation.echo`: a prior version led with “remain silent / do not speak,” which
    /// caused the replica to skip scripted echoes (instruction + stop) entirely.
    static let clockDrawingTavusBehaviorContext = """
    You are administering the Clock Drawing subtest. When the app sends a conversation.echo instruction, you MUST speak that text aloud immediately, verbatim, with clear pacing — including the initial clock instruction and the stop-drawing prompt. \
    Between those scripted echoes, observe silently with a neutral expression: no coaching, no hints, no commentary on the drawing, and no back-and-forth chat. \
    Do not confirm or critique whether the clock is correct.
    """

    // MARK: - Subtest 4: Delayed Recall (20 pts, 30 sec)

    static let delayedRecallTitle = "Word Recall"

    static let delayedRecallPrompt = "Earlier, I read you some words and asked you to hold onto them. Now I'd like you to tell me as many of those words as you can remember. Take your time — just say each one when it comes to you."

    static let delayedRecallOnScreen = "Recall the 5 words from earlier."

    /// Patient-facing subtitle (calming, non-cueing)
    static let delayedRecallPatientSubtitle = "Take your time."

    /// Single follow-up after patient indicates completion or 60s silence
    static let delayedRecallAnyOthers = "Are there any other words that come to mind?"

    /// Tavus `overwrite_context` for delayed word recall (echo text remains `delayedRecallPrompt` / `delayedRecallAnyOthers`).
    static let delayedRecallTavusBehaviorContext = """
    You are administering delayed word recall. Whenever the app sends echo text, speak it aloud immediately and verbatim — main prompt, follow-up, and any other scripted echoes. \
    Do not add words before or after the echoed text. Between echoes, listen silently without coaching or feedback on word correctness.
    """

    // MARK: - Subtest 5: Verbal Fluency (20 pts, 60 sec)

    static let verbalFluencyTitle = "Animals"

    static let verbalFluencySubtitle = "You have one minute."

    /// Full avatar prompt. Timer starts when the avatar finishes saying "Go."
    static let verbalFluencyPrompt = "I'd like you to name as many animals as you can think of. Any animals at all — wild, farm, pets, birds, fish, insects, anything. You'll have one minute. Ready? Go."

    /// Legacy alias — kept for any call sites that reference the old name.
    static let verbalFluencyInstruction = verbalFluencyPrompt

    /// Neutral close after 60 seconds.
    static let verbalFluencyClose = "Thank you. That's the end of this part."

    /// Single re-prompt if patient is silent for 15 seconds. Never re-prompt twice.
    static let verbalFluencyRePrompt = "Any animals you can think of."

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

    /// Avatar context for the completion phase — no scoring or correction rules needed.
    /// Used with `avatarSetContext` (not `avatarSetAssessmentContext`) because the
    /// "never correct patient" rule is irrelevant at the terminal thank-you screen.
    static let completionContext = "The cognitive assessment is now complete. You are delivering a brief closing thank-you. Do not ask any questions or provide any feedback about performance. Simply thank the patient for their participation."

    // MARK: - QDRS (Caregiver Flow)

    static let qdrsIntro = "Thank you for being here today. I have ten brief questions about any changes you may have noticed in the patient's everyday memory and activities. There are no right or wrong answers. Please answer based on what you've observed."

    static let qdrsCompletion = "Thank you for answering those questions. That information is very helpful. The clinician will review your responses."
}

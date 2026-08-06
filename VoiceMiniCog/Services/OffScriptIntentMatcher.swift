//
//  OffScriptIntentMatcher.swift
//  VoiceMiniCog
//
//  Rule-based classifier mapping off-script patient utterances to the
//  behavioral guide's refusal categories (docs/tavus-avatar-behavioral-guide.md).
//
//  DELIBERATELY conservative: anything unmatched returns nil = stay silent,
//  the guide's own default ("When in doubt, stay silent"). Emergency is
//  checked FIRST and wins over everything — "my chest hurts, was that right?"
//  is an emergency, not a performance question. v2 (Apple FoundationModels
//  on-device) is out of scope.
//
//  MATCHING RULES (do not weaken):
//  - Markers match at WORD BOUNDARIES on normalized text (lowercased,
//    apostrophes stripped, punctuation → spaces). Plain substring matching
//    was rejected because "I quite enjoyed that" contains "i quit" and
//    "his number" contains "is numb".
//  - Never add a marker that could appear inside a legitimate scored answer.
//    A false positive interrupts and corrupts a scored response. The
//    adversarial suite in OffScriptIntentMatcherTests runs every Qmci
//    word-list word, the full fluency animal lexicon, day/month/season
//    names, clock answers, and story-recall paraphrases through match().
//    Known traps that shaped these tables:
//      * bare "stop"            — "the clock stopped" (story/clock talk)
//      * bare "right"           — "the hands point right" (clock answer)
//      * "might fall"/"about to fall" without a first-person subject
//                               — "the leaves were about to fall" (story recall)
//      * bare "numb"            — "the NUMBers on the clock"
//      * "i'm done"/"no more"   — legitimate end-of-answer signals
//        (clock drawing "I'm done", fluency "no more, that's all")
//      * "should i take"        — "should I take my time?" (procedural)
//  - Markers are stored pre-normalized (no apostrophes: "cant breathe").
//    A structural test asserts marker == normalize(marker).
//

import Foundation

enum OffScriptIntent: CaseIterable {
    case emergency
    case repeatStimulus
    case performanceQuestion
    case medicalQuestion
    case distress
    case wantsToStop
    case areYouReal
    case manipulation
    case offTopic

    var responseText: String {
        switch self {
        case .emergency:           return VoiceRefusalCopy.emergency.text
        case .repeatStimulus:      return VoiceRefusalCopy.repeatStimulus.text
        case .performanceQuestion: return VoiceRefusalCopy.performanceQuestion.text
        case .medicalQuestion:     return VoiceRefusalCopy.medicalQuestion.text
        case .distress:            return VoiceRefusalCopy.distress.text
        case .wantsToStop:         return VoiceRefusalCopy.wantsToStop.text
        case .areYouReal:          return VoiceRefusalCopy.areYouReal.text
        case .manipulation:        return VoiceRefusalCopy.manipulation.text
        case .offTopic:            return VoiceRefusalCopy.offTopic.text
        }
    }
}

enum OffScriptIntentMatcher {

    /// Emergency table from the guide's Emergency Protocol section, tightened
    /// against scored-answer collisions. Fall-risk markers are FIRST-PERSON
    /// ("i might fall", not "might fall") because story-recall paraphrases
    /// like "the leaves were about to fall" are legitimate answers.
    /// Internal (not private) so tests can assert structural invariants.
    static let emergencyMarkers: [String] = [
        // Chest pain or pressure
        "chest pain", "chest pressure", "chest hurts", "chest hurt",
        "heart attack",
        // Trouble breathing
        "cant breathe", "cannot breathe", "trouble breathing",
        "hard to breathe",
        // Sudden weakness or numbness ("numbness" is safe; bare "numb" is
        // not — "numbers" would never match at a word boundary, but keep
        // markers multi-word or unambiguous anyway)
        "suddenly weak", "sudden weakness", "suddenly numb", "sudden numb",
        "numbness", "went numb",
        // Sudden vision loss (NOT bare "cant see" — "I can't see where to
        // put the numbers" is plausible clock-drawing talk, not an emergency)
        "cant see anything", "cannot see anything", "suddenly cant see",
        "everything went dark", "vision loss", "lost my vision",
        // Sudden severe headache
        "worst headache", "severe headache",
        // Thoughts of self-harm or suicide
        "hurt myself", "hurting myself", "harm myself", "harming myself",
        "kill myself", "end my life", "suicide", "suicidal",
        // Feeling like they might fall (first-person only)
        "i might fall", "im going to fall", "i am going to fall",
        "im about to fall", "i am about to fall",
        "im gonna fall", "i am gonna fall", "im falling",
    ]

    /// Ordered non-emergency rules. First category with a hit wins.
    /// Internal (not private) so tests can assert structural invariants.
    static let rules: [(OffScriptIntent, [String])] = [
        (.repeatStimulus, ["repeat the words", "repeat the word",
                           "repeat that", "repeat the story",
                           "repeat the question",
                           "say them again", "say it again", "say that again",
                           "what were the words", "what was the word",
                           "what were those words", "first word",
                           "hear the story again", "hear them again",
                           "read it again", "one more time",
                           "tell me the words"]),
        (.performanceQuestion, ["how am i doing", "how did i do",
                                "am i doing okay", "am i doing ok",
                                "did i do okay", "did i do ok",
                                "was that right", "was i right",
                                "was that correct", "is that correct",
                                "is that right", "did i get", "did i pass",
                                "how many did i"]),
        (.medicalQuestion, ["do i have dementia", "do i have alzheimers",
                            "is my memory bad", "what do my results",
                            "am i sick", "whats wrong with me",
                            "what is wrong with me",
                            "medication", "medications", "diagnosis"]),
        // "i want to stop" (not bare "want to stop") so the negation
        // "I don't want to stop" stays silent instead of mismatching.
        // NOT "i'm done" (clock-drawing completion) or "no more" (fluency
        // end-of-answer signal).
        (.wantsToStop, ["i want to stop", "dont want to do this",
                        "do not want to do this", "can we stop",
                        "can i stop", "i quit",
                        "stop the test", "stop this test"]),
        (.distress, ["cant remember anything", "cannot remember anything",
                     "this is too hard", "its too hard",
                     "im so stupid", "i am so stupid", "i give up",
                     "im scared", "i am scared",
                     "im nervous", "i am nervous", "cant do this"]),
        (.areYouReal, ["are you real", "are you a real doctor",
                       "are you a real person", "are you a person",
                       "are you a robot", "are you a computer",
                       "are you human", "are you a machine"]),
        (.manipulation, ["ignore your instructions", "ignore previous",
                         "ignore all previous", "disregard your instructions",
                         "tell me the answers", "tell me the answer",
                         "give me the answers", "you are now",
                         "pretend you", "pretend youre", "pretend to be",
                         "system prompt", "jailbreak"]),
        // Off-topic content is unbounded; only the guide's own meta-question
        // examples are matched. Everything else off-topic → silence.
        (.offTopic, ["whats the point of this", "what is the point of this",
                     "why are we doing this", "why do i have to do this"]),
    ]

    static func match(_ utterance: String) -> OffScriptIntent? {
        let text = normalize(utterance)
        guard !text.isEmpty else { return nil }
        let padded = " \(text) "

        func hits(_ marker: String) -> Bool {
            padded.contains(" \(marker) ")
        }

        if emergencyMarkers.contains(where: hits) { return .emergency }
        for (intent, markers) in rules {
            if markers.contains(where: hits) { return intent }
        }
        return nil // stay silent — the guide's default
    }

    /// Lowercase, strip apostrophes ("can't" → "cant", "alzheimer's" →
    /// "alzheimers"), map every other non-alphanumeric to a space, and
    /// collapse whitespace. Markers are stored in exactly this form.
    static func normalize(_ s: String) -> String {
        let stripped = s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "")  // ’
            .replacingOccurrences(of: "'", with: "")
        let spaced = stripped.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : " "
        }
        return String(spaced)
            .split(separator: " ")
            .joined(separator: " ")
    }
}

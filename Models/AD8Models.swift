//
//  AD8Models.swift
//  VoiceMiniCog
//
//  AD8 Dementia Screening models matching React implementation
//

import Foundation

// AD8 Questions matching React
let AD8_QUESTIONS: [String] = [
    "First — have you noticed any changes in judgment, like making decisions or financial choices?",
    "What about hobbies or activities you used to enjoy — has your interest in those changed?",
    "Do you find yourself repeating the same questions or stories?",
    "What about learning how to use new things, like a phone, remote, or other device — has that gotten harder?",
    "Any trouble keeping track of the date, like the month or year?",
    "Has handling bills, finances, or taxes become more difficult?",
    "What about remembering appointments — has that been an issue?",
    "And overall, have you noticed ongoing problems with thinking or memory?",
]

let AD8_DOMAINS: [String] = [
    "Judgment/Decision-making",
    "Interest/Motivation",
    "Repetitive behavior",
    "Learning new tasks",
    "Temporal orientation",
    "Financial management",
    "Appointment memory",
    "Daily thinking/memory",
]

let AD8_CLARIFICATION_FIRST = "Would you say that's changed, or about the same?"
let AD8_CLARIFICATION_GIVEUP = "No problem, we'll move on."

let AD8_LISTEN_TIMEOUT = 12000
let AD8_MAX_CLARIFICATIONS = 1
let AD8_MAX_REPEATS = 2

enum AD8Answer: String, Codable {
    case yes
    case no
    case na
}

enum AD8ResponseInterpretation {
    case yes
    case no
    case na
    case clarify
    case repeatQuestion
}

enum AD8RespondentType: String, Codable {
    case informant
    case selfReport = "self"
}

struct AD8State {
    var respondentType: AD8RespondentType = .selfReport
    var answers: [AD8Answer?] = Array(repeating: nil, count: 8)
    var currentQuestion: Int = 0
    var score: Int? = nil
    var flaggedDomains: [String] = []
    var declined: Bool = false

    var isScreenPositive: Bool? {
        guard let score = score else { return nil }
        return score >= 2
    }

    mutating func computeScore() {
        let yesCount = answers.compactMap { $0 }.filter { $0 == .yes }.count
        score = yesCount
        flaggedDomains = answers.enumerated().compactMap { index, answer in
            answer == .yes ? AD8_DOMAINS[index] : nil
        }
    }
}

// Interpret AD8 voice response
func interpretAD8Response(_ raw: String) -> AD8ResponseInterpretation {
    let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return .repeatQuestion }

    // Explicit requests to repeat
    let repeatPatterns = ["repeat", "again", "what", "huh", "sorry", "pardon", "say that", "didn't hear", "didn't catch", "come again", "one more time", "say it again", "could you repeat", "can you repeat", "what was that", "wait what", "missed that", "what did you say"]
    for pattern in repeatPatterns {
        if t.contains(pattern) { return .repeatQuestion }
    }

    // Clarification requests
    let clarifyPatterns = ["what do you mean", "clarify", "explain", "don't understand", "what does that mean", "example"]
    for pattern in clarifyPatterns {
        if t.contains(pattern) { return .clarify }
    }

    // Uncertain -> N/A
    let naPatterns = ["i'm not sure", "not sure", "i don't know", "don't know", "hard to say", "maybe", "i guess", "unsure", "can't say", "n/a", "not applicable"]
    for pattern in naPatterns {
        if t.contains(pattern) { return .na }
    }

    // YES patterns
    let yesPatterns = ["yes", "yeah", "yep", "yup", "a little", "somewhat", "it has", "a bit", "gotten worse", "i think so", "sometimes", "definitely", "absolutely", "for sure", "has changed", "worse", "a change", "uh huh", "correct", "that's right", "that's true", "there has", "changed", "it's changed", "it does", "it is", "kind of", "sort of", "a lot", "much worse", "quite a bit", "i'd say so", "probably", "i have noticed"]
    for pattern in yesPatterns {
        if t.contains(pattern) { return .yes }
    }

    // NO patterns
    let noPatterns = ["no", "nope", "nah", "not really", "that's fine", "same as always", "hasn't changed", "i don't think so", "has not", "hasn't", "no change", "same", "the same", "about the same", "it's the same", "it hasn't", "not at all", "i haven't noticed", "no problems", "doing fine", "no issues", "no trouble", "still good"]
    for pattern in noPatterns {
        if t.contains(pattern) { return .no }
    }

    return .repeatQuestion
}

// Check if AD8 response is complete
func isAD8ResponseComplete(_ transcript: String) -> Bool {
    let s = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return false }

    let completionPatterns = ["yes", "yeah", "yep", "yup", "no", "nope", "nah", "not really", "a little", "somewhat", "it has", "a bit", "that's gotten worse", "i think so", "sometimes", "that's fine", "same as always", "hasn't changed", "i don't think so", "i'm not sure", "i don't know", "hard to say", "maybe", "i guess", "definitely", "hasn't", "has not", "for sure", "na", "not applicable", "changed", "about the same", "it is", "it does", "kind of", "sort of", "correct", "absolutely", "not at all", "no problems", "doing fine", "no trouble", "still good", "i have noticed", "probably", "much worse", "quite a bit", "repeat", "again", "didn't hear", "didn't catch", "what was that", "come again", "one more time", "say it again", "can you repeat", "could you repeat", "what did you say"]

    for pattern in completionPatterns {
        if s.contains(pattern) { return true }
    }
    return false
}

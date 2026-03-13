//
//  ResponseCheckers.swift
//  VoiceMiniCog
//
//  Response completeness checkers matching React implementation
//

import Foundation

// Greeting: any short acknowledgment (yes, ok, hi, sure, ready, etc.)
func isGreetingComplete(_ transcript: String) -> Bool {
    let s = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return false }

    // Short answers are almost always complete
    let wordCount = s.split(separator: " ").count
    if wordCount <= 4 { return true }

    let patterns = ["yes", "yeah", "ok", "okay", "sure", "hi", "hello", "ready", "fine", "good", "alright", "go ahead", "let's go", "let's do it"]
    for pattern in patterns {
        if s.contains(pattern) { return true }
    }
    return false
}

// Word registration: patient listing ~3 words (or saying "I don't remember")
func makeWordRegistrationChecker(wordList: [String]) -> (String) -> Bool {
    return { transcript in
        let s = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }

        // "I don't know / remember"
        if s.contains("don't") || s.contains("dont") || s.contains("can't") || s.contains("cant") || s.contains("no") {
            if s.contains("know") || s.contains("remember") || s.contains("recall") {
                return true
            }
        }

        // Count how many target words appear
        let found = wordList.filter { s.contains($0.lowercased()) }
        if found.count >= 3 { return true }

        // If they said 2+ distinct words and paused, likely done
        let wordCount = s.split(separator: " ").count
        if found.count >= 2 && wordCount >= 2 { return true }

        // Short phrase with at least one target word — probably done
        if found.count >= 1 && wordCount <= 5 { return true }

        return false
    }
}

// Recall: same as registration but a bit more lenient
func makeRecallChecker(wordList: [String]) -> (String) -> Bool {
    return { transcript in
        let s = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }

        // "I don't know / remember"
        if s.contains("don't") || s.contains("dont") || s.contains("can't") || s.contains("cant") || s.contains("no") {
            if s.contains("know") || s.contains("remember") || s.contains("recall") {
                return true
            }
        }

        // "That's all" / "Nothing else"
        if s.contains("that's all") || s.contains("thats all") || s.contains("that's it") || s.contains("nothing else") || s.contains("only") {
            return true
        }

        // Count how many target words appear
        let found = wordList.filter { s.contains($0.lowercased()) }
        if found.count >= 3 { return true }
        if found.count >= 1 && s.split(separator: " ").count <= 6 { return true }

        return false
    }
}

// Score word recall - returns count and list of recalled words
func scoreWordRecall(transcript: String, wordList: [String]) -> (count: Int, recalled: [String]) {
    let lower = transcript.lowercased()
    var found: [String] = []

    for word in wordList {
        if lower.contains(word.lowercased()) && !found.contains(word.lowercased()) {
            found.append(word.lowercased())
        }
    }

    return (count: found.count, recalled: found)
}

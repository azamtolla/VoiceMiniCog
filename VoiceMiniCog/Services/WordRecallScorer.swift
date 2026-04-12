//
//  WordRecallScorer.swift
//  VoiceMiniCog
//
//  Scores the delayed word recall subtest by matching ASR transcript
//  words against the 5 registration target words. Tracks timing biomarkers
//  (first-word latency, inter-word intervals, silence duration).
//
//  Fuzzy matching uses the same prefix-aware + Levenshtein approach as
//  scoreWordRegistrationRecall in ResponseCheckers.swift — tolerant of
//  common ASR mishearings and inflected forms ("feared" → "fear").
//

import Foundation

struct WordRecallScorer {
    let targetWords: [String]
    var promptEndTime: Date?
    var recalledWords: Set<String> = []
    var intrusions: [String] = []
    var semanticSubstitutions: [(target: String, said: String)] = []
    var anyOthersPromptUsed = false
    var silenceBeforePromptMs: Int = 0

    private var phaseStartTime = Date()
    private var firstRecallTime: Date?
    private var wordRecallTimes: [Date] = []
    private var lastProcessedLength = 0
    private var peakSilenceSeconds: TimeInterval = 0

    var recalledCount: Int { recalledWords.count }

    var firstWordLatencySeconds: Double? {
        guard let prompt = promptEndTime, let first = firstRecallTime else { return nil }
        return first.timeIntervalSince(prompt)
    }

    var interWordIntervalsMs: [Int] {
        guard wordRecallTimes.count > 1 else { return [] }
        return zip(wordRecallTimes, wordRecallTimes.dropFirst()).map { prev, next in
            Int(next.timeIntervalSince(prev) * 1000)
        }
    }

    var totalPhaseDurationMs: Int {
        Int(Date().timeIntervalSince(phaseStartTime) * 1000)
    }

    init(targetWords: [String]) {
        self.targetWords = targetWords
    }

    // MARK: - Transcript Processing

    mutating func processTranscript(_ transcript: String) {
        let tokens = tokenize(transcript)
        let newTokens = Array(tokens.dropFirst(lastProcessedLength))
        lastProcessedLength = tokens.count

        for token in newTokens {
            if let matched = matchTarget(token) {
                if recalledWords.insert(matched).inserted {
                    let now = Date()
                    wordRecallTimes.append(now)
                    if firstRecallTime == nil { firstRecallTime = now }
                }
            } else if token.count > 2 && !isCommonFiller(token) {
                intrusions.append(token)
            }
        }
    }

    func containsCompletionPhrase(_ transcript: String) -> Bool {
        let lower = transcript.lowercased()
        let phrases = ["that's all", "that's it", "i can't remember", "no more",
                       "i don't remember", "i don't know", "nothing else",
                       "i'm done", "im done", "that is all", "that is it"]
        return phrases.contains { lower.contains($0) }
    }

    mutating func markAnyOthersPromptUsed() {
        anyOthersPromptUsed = true
    }

    mutating func updateSilence(_ seconds: TimeInterval) {
        if seconds > peakSilenceSeconds { peakSilenceSeconds = seconds }
    }

    mutating func finalizePhase() {
        // Phase duration is computed dynamically via totalPhaseDurationMs
    }

    // MARK: - Fuzzy Matching (mirrors ResponseCheckers.scoreWordRegistrationRecall)

    /// Match a spoken token against target words using exact, prefix, and
    /// Levenshtein matching — tolerant of ASR variants and inflections.
    private func matchTarget(_ token: String) -> String? {
        let tok = token.lowercased()

        for word in targetWords {
            let wl = word.lowercased()
            guard !recalledWords.contains(word) else { continue }

            // Exact match
            if tok == wl { return word }

            // Prefix extensions ("buttered" → "butter", "queenly" → "queen")
            if tok.hasPrefix(wl) && tok.count <= wl.count + 3 { return word }
            if wl.hasPrefix(tok) && wl.count <= tok.count + 2 { return word }

            // Levenshtein with length-scaled threshold
            let maxDist = wl.count <= 4 ? 1 : (wl.count <= 6 ? 1 : 2)
            if levenshtein(tok, wl) <= maxDist { return word }
        }
        return nil
    }

    // MARK: - Private Helpers

    private func tokenize(_ transcript: String) -> [String] {
        transcript.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func levenshtein(_ s: String, _ t: String) -> Int {
        let a = Array(s), b = Array(t)
        var row = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, cb) in b.enumerated() {
                let insertCost = row[j + 1]
                let deleteCost = row[j]
                let replaceCost = previous + (ca == cb ? 0 : 1)
                previous = row[j + 1]
                row[j + 1] = min(insertCost + 1, deleteCost + 1, replaceCost)
            }
        }
        return row[b.count]
    }

    private func isCommonFiller(_ word: String) -> Bool {
        let fillers: Set = ["um", "uh", "the", "and", "a", "an", "oh", "hmm", "like",
                            "so", "well", "okay", "ok", "was", "it", "is", "that",
                            "i", "my", "me", "we", "you", "they", "he", "she",
                            "can", "do", "did", "have", "has", "had", "been",
                            "what", "how", "when", "where", "why", "who"]
        return fillers.contains(word.lowercased())
    }
}

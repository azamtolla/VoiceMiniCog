//
//  WordRecallScorer.swift
//  VoiceMiniCog
//
//  @Observable service for real-time delayed word recall scoring.
//  Matches ASR transcript tokens against the 5 target words from
//  the registration phase, tracking recall count, intrusions,
//  timing biomarkers, and completion detection.
//

import Foundation
import Observation

@Observable
class WordRecallScorer {

    // MARK: Configuration

    let targetWords: [String]
    private let targetSet: Set<String>

    // MARK: Outputs

    /// Unique correctly recalled words (lowercased).
    private(set) var recalledWords: Set<String> = []
    /// Non-target words the patient said (excludes stopwords and short tokens).
    private(set) var intrusions: [String] = []
    /// Semantic substitutions: (target, said) — near-misses NOT credited as correct.
    private(set) var semanticSubstitutions: [(target: String, said: String)] = []

    var recalledCount: Int { recalledWords.count }

    // MARK: Timing

    /// Set via markPromptEnded() when the avatar finishes the recall prompt.
    private(set) var promptEndTime: Date? = nil
    private var firstWordTime: Date? = nil
    private var wordTimes: [Date] = []
    private var phaseStartTime = Date()

    // MARK: Follow-Up

    var anyOthersPromptUsed: Bool = false
    var silenceBeforePromptMs: Int = 0

    // MARK: Internal

    private var processedLength: Int = 0

    private static let completionPhrases = [
        "i'm done", "im done", "that's all", "thats all",
        "that's it", "thats it", "i can't remember",
        "i cant remember", "nothing else", "no more",
        "i don't remember", "i dont remember"
    ]

    /// Synonym map: spoken word → target word. When a synonym is detected and
    /// the corresponding target has NOT already been credited, the pair is
    /// logged as a semantic substitution. Per Qmci protocol, semantic
    /// substitutions are NOT credited as correct recalls — they are recorded
    /// for clinician review only.
    private static let synonymMap: [String: String] = [
        // dog
        "puppy": "dog", "doggie": "dog", "hound": "dog", "mutt": "dog",
        // rain
        "rainfall": "rain", "raindrop": "rain", "raining": "rain",
        // butter
        "margarine": "butter",
        // love
        "loved": "love", "loving": "love",
        // door
        "doorway": "door", "gate": "door",
        // cat
        "kitten": "cat", "kitty": "cat", "feline": "cat",
        // dark
        "darkness": "dark", "night": "dark",
        // rat
        "rodent": "rat", "mouse": "rat",
        // heat
        "hot": "heat", "warmth": "heat",
        // bread
        "loaf": "bread", "bun": "bread", "toast": "bread",
        // fear
        "afraid": "fear", "scared": "fear", "fright": "fear",
        // round
        "circle": "round", "circular": "round",
        // bed
        "mattress": "bed", "bunk": "bed",
        // chair
        "seat": "chair", "stool": "chair",
        // fruit
        "produce": "fruit",
    ]

    /// Common filler/function words excluded from intrusion tracking.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "um", "uh", "well",
        "you", "know", "let", "me", "see", "think", "remember",
        "was", "those", "were", "words", "word", "that", "this",
        "these", "it", "is", "of", "to", "in", "for", "on", "with",
        "my", "his", "her", "they", "there", "what", "how", "can",
        "just", "like", "so", "yes", "no", "not", "oh", "okay",
        "yeah", "hmm", "then", "said", "some", "one", "about",
        "got", "get", "had", "have", "been", "from", "all", "do",
    ]

    // MARK: Init

    init(targetWords: [String]) {
        self.targetWords = targetWords
        self.targetSet = Set(targetWords.map { $0.lowercased() })
    }

    // MARK: Lifecycle

    /// Resets all scoring state. Call on phase entry before processing begins.
    func startScoring() {
        recalledWords = []
        intrusions = []
        semanticSubstitutions = []
        wordTimes = []
        firstWordTime = nil
        processedLength = 0
        phaseStartTime = Date()
        promptEndTime = nil
        anyOthersPromptUsed = false
        silenceBeforePromptMs = 0
    }

    /// Records the moment the avatar finishes speaking the recall prompt.
    /// Idempotent — subsequent calls are ignored so latency measurement
    /// anchors to the first prompt delivery only.
    func markPromptEnded() {
        guard promptEndTime == nil else { return }
        promptEndTime = Date()
    }

    // MARK: Processing

    func processTranscript(_ transcript: String) {
        let lower = transcript.lowercased()
        guard lower.count > processedLength else { return }
        processedLength = lower.count

        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for token in tokens {
            let normalized = normalizePlural(token)

            if targetSet.contains(normalized), !recalledWords.contains(normalized) {
                // Direct target match
                recalledWords.insert(normalized)
                let now = Date()
                if firstWordTime == nil, promptEndTime != nil {
                    firstWordTime = now
                }
                wordTimes.append(now)
            } else if let target = Self.synonymMap[normalized],
                      targetSet.contains(target),
                      !recalledWords.contains(target),
                      !semanticSubstitutions.contains(where: { $0.said == normalized }) {
                // Semantic substitution — log for clinician review, do NOT credit
                semanticSubstitutions.append((target: target, said: normalized))
            } else if !normalized.isEmpty,
                      normalized.count > 2,
                      !targetSet.contains(normalized),
                      !Self.stopwords.contains(normalized),
                      !intrusions.contains(normalized),
                      Self.synonymMap[normalized] == nil {
                // Intrusion — non-target, non-synonym, non-stopword
                intrusions.append(normalized)
            }
        }
    }

    func containsCompletionPhrase(_ transcript: String) -> Bool {
        let lower = transcript.lowercased()
        // Use word-boundary matching to prevent substring false positives
        return Self.completionPhrases.contains(where: { phrase in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
            return lower.range(of: pattern, options: .regularExpression) != nil
        })
    }

    // MARK: State Updates

    func markAnyOthersPromptUsed() { anyOthersPromptUsed = true }

    // MARK: Computed Metrics

    /// Time from prompt delivery to first recalled word.
    /// Note: latency is measured from ASR transcript-update receipt, not from
    /// the actual moment of patient utterance. Apple SFSpeechRecognizer commit
    /// latency (typically 200-800ms) is included. Values are systematically
    /// inflated by ASR processing time.
    var firstWordLatencySeconds: TimeInterval? {
        guard let prompt = promptEndTime, let first = firstWordTime else { return nil }
        let latency = first.timeIntervalSince(prompt)
        // Guard against negative latency (firstWordTime before promptEndTime
        // due to ASR delivering a buffered result from before the prompt ended)
        return latency >= 0 ? latency : nil
    }

    var interWordIntervalsMs: [Int] {
        guard wordTimes.count >= 2 else { return [] }
        return zip(wordTimes, wordTimes.dropFirst()).map {
            Int(($1.timeIntervalSince($0) * 1000).rounded())
        }
    }

    var totalPhaseDurationMs: Int {
        Int((Date().timeIntervalSince(phaseStartTime) * 1000).rounded())
    }

    // MARK: - Plural Normalization

    private static let irregularPlurals: [String: String] = [
        "mice": "mouse", "geese": "goose", "wolves": "wolf",
        "calves": "calf", "knives": "knife", "leaves": "leaf",
        "loaves": "loaf",
    ]

    private func normalizePlural(_ word: String) -> String {
        if let irregular = Self.irregularPlurals[word] { return irregular }
        if word.hasSuffix("ies") && word.count > 4 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("shes") || word.hasSuffix("ches") || word.hasSuffix("xes") || word.hasSuffix("zes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && word.count > 2 {
            return String(word.dropLast())
        }
        return word
    }
}

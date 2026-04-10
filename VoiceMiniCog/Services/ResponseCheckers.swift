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

// Word registration: patient listing ~5 words (QMCI protocol) or saying "I don't remember"
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
        if s.contains("that's all") || s.contains("thats all") || s.contains("that's it") || s.contains("thats it") || s.contains("nothing else") || s.contains("only") {
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

// MARK: - Qmci Scoring Extensions

/// Verbal fluency: extract unique animal names from transcript
func scoreVerbalFluency(transcript: String) -> [String] {
    let commonAnimals: Set<String> = [
        "dog", "cat", "horse", "cow", "pig", "sheep", "goat", "chicken",
        "duck", "bird", "fish", "rabbit", "mouse", "rat", "hamster",
        "elephant", "lion", "tiger", "bear", "monkey", "giraffe", "zebra",
        "deer", "wolf", "fox", "snake", "frog", "turtle", "whale",
        "dolphin", "shark", "eagle", "hawk", "owl", "parrot", "penguin",
        "butterfly", "bee", "ant", "spider", "crab", "lobster", "octopus",
        "camel", "donkey", "moose", "buffalo", "rhino", "hippo", "gorilla",
        "cheetah", "leopard", "panther", "jaguar", "alligator", "crocodile",
        "squirrel", "chipmunk", "raccoon", "skunk", "porcupine", "beaver",
        "otter", "seal", "walrus", "bat", "rooster", "turkey", "goose",
        "swan", "flamingo", "pelican", "stork", "heron", "robin", "crow",
        "dove", "pigeon", "sparrow", "cardinal", "bluejay", "woodpecker",
        "goldfish", "salmon", "tuna", "trout", "catfish", "bass",
        "pony", "stallion", "mare", "colt", "lamb", "ram", "bull",
        "calf", "kitten", "puppy", "chick", "cub", "koala", "kangaroo",
        "panda", "sloth", "armadillo", "hedgehog", "ferret", "gecko",
        "iguana", "chameleon", "salamander", "newt", "toad", "worm",
        "snail", "slug", "clam", "oyster", "starfish", "jellyfish",
        "scorpion", "centipede", "mosquito", "fly", "beetle", "moth",
        "dragonfly", "grasshopper", "cricket", "ladybug", "firefly",
    ]

    let words = transcript.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }

    var found: [String] = []
    for word in words {
        if commonAnimals.contains(word) && !found.contains(word) {
            found.append(word)
        }
    }
    return found
}

/// Logical memory: match recalled details against story scoring units
func scoreLogicalMemory(transcript: String, scoringUnits: [String]) -> [String] {
    let lower = transcript.lowercased()
    var matched: [String] = []
    for unit in scoringUnits {
        if lower.contains(unit.lowercased()) && !matched.contains(unit) {
            matched.append(unit)
        }
    }
    return matched
}

/// Orientation: check answer against current date/time.
///
/// STT transcripts routinely contain natural language rather than digits —
/// e.g. "I think it's the tenth" or "twenty twenty six". Per Dr. Malloy's QMCI
/// administration video, such hedged/verbalized answers are still credited if
/// the stated value is correct. This matcher accepts both digit and English
/// word forms for years (2000–2099) and dates (1–31).
func scoreOrientationAnswer(type: OrientationAnswerType, transcript: String) -> Bool {
    let t = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let calendar = Calendar.current
    let now = Date()

    switch type {
    case .year:
        let yearInt = calendar.component(.year, from: now)
        return transcriptMentionsYear(t, year: yearInt)
    case .month:
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: now).lowercased()
        let shortMonth = String(month.prefix(3))
        return t.contains(month) || t.contains(shortMonth)
    case .dayOfWeek:
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: now).lowercased()
        return t.contains(day)
    case .date:
        let dayInt = calendar.component(.day, from: now)
        return transcriptMentionsDay(t, day: dayInt)
    case .country:
        let terms = ["united states", "america", "usa", "us", "u.s."]
        return terms.contains(where: { t.contains($0) })
    }
}

/// True if `transcript` (lowercased) mentions `day` either as digits or as an
/// English cardinal/ordinal word form ("tenth", "twenty one", etc.). Supports
/// days 1–31 only.
func transcriptMentionsDay(_ transcript: String, day: Int) -> Bool {
    if transcript.contains(String(day)) { return true }
    return englishDayForms(day).contains { transcript.contains($0) }
}

/// English cardinal + ordinal forms for a day of month (1–31).
/// Returns lowercased forms suitable for substring matching.
func englishDayForms(_ day: Int) -> [String] {
    let cardinals = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                     "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                     "seventeen", "eighteen", "nineteen", "twenty"]
    let ordinals = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
                    "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth",
                    "seventeenth", "eighteenth", "nineteenth", "twentieth"]
    guard (1...31).contains(day) else { return [] }
    if day <= 20 {
        return [cardinals[day], ordinals[day]]
    }
    if day == 30 { return ["thirty", "thirtieth"] }
    if day == 31 {
        return ["thirty one", "thirty-one", "thirty first", "thirty-first"]
    }
    // 21–29
    let unit = day - 20
    let cardinal = "twenty \(cardinals[unit])"
    let cardinalHyphen = "twenty-\(cardinals[unit])"
    let ordinal = "twenty \(ordinals[unit])"
    let ordinalHyphen = "twenty-\(ordinals[unit])"
    return [cardinal, cardinalHyphen, ordinal, ordinalHyphen]
}

/// True if `transcript` (lowercased) mentions `year` as digits or as a common
/// spoken English form for years in the range 2000–2099.
/// Handles forms like: "2026", "twenty twenty six", "two thousand twenty six",
/// "two thousand and twenty six".
func transcriptMentionsYear(_ transcript: String, year: Int) -> Bool {
    if transcript.contains(String(year)) { return true }
    guard (2000...2099).contains(year) else { return false }
    let suffix = year - 2000
    let units = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
                 "sixteen", "seventeen", "eighteen", "nineteen"]
    let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    var spoken: [String] = []
    if suffix == 0 {
        spoken = ["two thousand"]
    } else if suffix < 10 {
        let u = units[suffix]
        spoken = [
            "two thousand \(u)",
            "two thousand and \(u)",
            "twenty oh \(u)",
            "twenty o \(u)",
        ]
    } else if suffix < 20 {
        let teen = teens[suffix - 10]
        spoken = [
            "two thousand \(teen)",
            "two thousand and \(teen)",
            "twenty \(teen)",
        ]
    } else {
        let tensWord = tens[suffix / 10]
        let unitIdx = suffix % 10
        if unitIdx == 0 {
            spoken = [
                "twenty \(tensWord)",
                "two thousand \(tensWord)",
                "two thousand and \(tensWord)",
            ]
        } else {
            let u = units[unitIdx]
            spoken = [
                "twenty \(tensWord) \(u)",
                "twenty \(tensWord)-\(u)",
                "two thousand \(tensWord) \(u)",
                "two thousand and \(tensWord) \(u)",
            ]
        }
    }
    return spoken.contains { transcript.contains($0) }
}

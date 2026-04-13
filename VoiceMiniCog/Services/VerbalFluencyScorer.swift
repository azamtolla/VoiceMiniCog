//
//  VerbalFluencyScorer.swift
//  VoiceMiniCog
//
//  @Observable service for real-time verbal fluency scoring.
//  Ingests a live ASR transcript, matches words against a static animal
//  lexicon (~300 entries with semantic subcategory tags), collapses plurals,
//  handles compound names, and produces clinical metrics:
//    • validAnimals (ordered, unique), repetitions, intrusions
//    • wordTimestamps for time-binned analysis
//    • Cluster/switch analysis (mean cluster size, switch count)
//    • Quartile counts (4 × 15s bins)
//    • Superordinate flagging (overuse = semantic degradation marker)
//
//  Static lexicon = fast, deterministic, defensible, reproducible.
//

import Foundation
import Observation

// MARK: - Animal Semantic Category

enum AnimalCategory: String, Codable, CaseIterable {
    case mammalWild
    case mammalFarm
    case mammalPet
    case bird
    case fish
    case reptile
    case amphibian
    case insect
    case arachnid
    case crustacean
    case mollusk
    case other

    /// True for broad superordinate terms ("bird", "fish", "insect").
    /// Overuse of superordinates is clinically meaningful — indicates
    /// semantic memory degradation in AD. Checked via
    /// VerbalFluencyScorer.superordinateTerms, not per-category.
}

// MARK: - Verbal Fluency Scorer

@Observable
class VerbalFluencyScorer {

    // MARK: Public Outputs

    /// Unique valid animals in order named.
    private(set) var validAnimals: [String] = []
    /// Words the patient repeated (already credited).
    private(set) var repetitions: [String] = []
    /// Non-animal words the patient said.
    private(set) var intrusions: [String] = []
    /// Every recognized animal-class token in spoken order (valid + repeats),
    /// preserving the verbatim sequence for clinician review.
    private(set) var allWordsInOrder: [String] = []
    /// Timestamp of each valid animal relative to timer start.
    private(set) var wordTimestamps: [(word: String, secondsFromStart: TimeInterval)] = []
    /// Category sequence for cluster/switch analysis.
    private(set) var categorySequence: [AnimalCategory] = []

    var count: Int { validAnimals.count }

    // MARK: Internal State

    private var timerStart: Date?
    private var processedTokens: Set<String> = []
    private var lastProcessedLength: Int = 0

    // MARK: Lifecycle

    func startScoring() {
        timerStart = Date()
        validAnimals = []
        repetitions = []
        intrusions = []
        allWordsInOrder = []
        wordTimestamps = []
        categorySequence = []
        processedTokens = []
        lastProcessedLength = 0
    }

    // MARK: Real-Time Transcript Processing

    /// Call whenever the ASR transcript updates. Processes only the new
    /// portion of the transcript (since last call) for efficiency.
    func processTranscript(_ transcript: String) {
        let lower = transcript.lowercased()
        guard lower.count > lastProcessedLength else { return }
        lastProcessedLength = lower.count

        let now = timerStart.map { Date().timeIntervalSince($0) } ?? 0

        // Tokenize the full transcript (re-process to catch compound names)
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // Check compound names (bigrams) first. When a compound matches,
        // mark its constituent tokens as processed so the single-token loop
        // below doesn't double-count them (e.g., "polar bear" must not also
        // credit "bear" separately).
        for i in 0..<max(0, tokens.count - 1) {
            let bigram = "\(tokens[i]) \(tokens[i + 1])"
            let normalized = normalizePlural(bigram)
            if let entry = Self.compoundLexicon[normalized], !processedTokens.contains(normalized) {
                processedTokens.insert(normalized)
                processedTokens.insert(normalizePlural(tokens[i]))
                processedTokens.insert(normalizePlural(tokens[i + 1]))
                addValidAnimal(normalized, category: entry.category, at: now)
            }
        }

        // Check single tokens
        for token in tokens {
            let normalized = normalizePlural(token)
            guard normalized.count > 1 else { continue }
            guard !processedTokens.contains(normalized) else {
                // Already counted — record as repetition (once per word) and
                // append to verbatim order list for every occurrence.
                if Self.singleLexicon[normalized] != nil {
                    allWordsInOrder.append(normalized)
                    if !repetitions.contains(normalized) {
                        repetitions.append(normalized)
                    }
                }
                continue
            }

            if let entry = Self.singleLexicon[normalized] {
                processedTokens.insert(normalized)
                addValidAnimal(normalized, category: entry.category, at: now)
            }
            // Note: we don't track intrusions from ASR since the transcript
            // contains many filler words; intrusion detection would need
            // more sophisticated NLP. Leave intrusions empty for now.
        }
    }

    private func addValidAnimal(_ name: String, category: AnimalCategory, at time: TimeInterval) {
        validAnimals.append(name)
        allWordsInOrder.append(name)
        wordTimestamps.append((word: name, secondsFromStart: time))
        categorySequence.append(category)
    }

    // MARK: Plural Normalization

    private static let irregularPlurals: [String: String] = [
        "mice": "mouse", "geese": "goose", "lice": "louse",
        "oxen": "ox", "children": "child", "teeth": "tooth",
        "feet": "foot", "wolves": "wolf", "calves": "calf",
        "halves": "half", "knives": "knife", "lives": "life",
        "leaves": "leaf", "elves": "elf", "shelves": "shelf",
        // Animals whose plurals are broken by the generic -ses rule
        "horses": "horse", "tortoises": "tortoise", "porpoises": "porpoise",
        "mongooses": "mongoose", "mooses": "moose", "basses": "bass",
    ]

    private func normalizePlural(_ word: String) -> String {
        if let irregular = Self.irregularPlurals[word] { return irregular }
        if word.hasSuffix("ies") && word.count > 4 {
            return String(word.dropLast(3)) + "y"  // butterflies → butterfly
        }
        if word.hasSuffix("shes") || word.hasSuffix("ches") || word.hasSuffix("xes") || word.hasSuffix("zes") {
            return String(word.dropLast(2))  // foxes → fox
        }
        if word.hasSuffix("ses") && word.count > 4 {
            return String(word.dropLast(2))  // mooses → moose (approximate)
        }
        if word.hasSuffix("s") && !word.hasSuffix("ss") && word.count > 2 {
            return String(word.dropLast())   // dogs → dog
        }
        return word
    }

    // MARK: - Post-Phase Metrics

    /// Superordinate count — how many broad category terms were used.
    var superordinateCount: Int {
        validAnimals.filter { Self.superordinateTerms.contains($0) }.count
    }

    /// First-word latency in seconds from timer start.
    var firstWordLatency: TimeInterval? {
        wordTimestamps.first?.secondsFromStart
    }

    /// Mean interval between consecutive valid animals.
    var meanInterWordInterval: TimeInterval? {
        guard wordTimestamps.count >= 2 else { return nil }
        let intervals = zip(wordTimestamps, wordTimestamps.dropFirst()).map { $1.secondsFromStart - $0.secondsFromStart }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    /// 4-bin quartile counts (0–15s, 15–30s, 30–45s, 45–60s).
    var quartileCounts: [Int] {
        var bins = [0, 0, 0, 0]
        for (_, time) in wordTimestamps {
            let bin = min(3, Int(time / 15.0))
            bins[bin] += 1
        }
        return bins
    }

    /// Mean cluster size — average length of runs of consecutive same-category animals.
    var meanClusterSize: Double? {
        guard !categorySequence.isEmpty else { return nil }
        var clusters: [Int] = []
        var currentSize = 1
        for i in 1..<categorySequence.count {
            if categorySequence[i] == categorySequence[i - 1] {
                currentSize += 1
            } else {
                clusters.append(currentSize)
                currentSize = 1
            }
        }
        clusters.append(currentSize)
        return Double(clusters.reduce(0, +)) / Double(clusters.count)
    }

    /// Switch count — number of transitions between semantic categories.
    var switchCount: Int {
        guard categorySequence.count >= 2 else { return 0 }
        var switches = 0
        for i in 1..<categorySequence.count {
            if categorySequence[i] != categorySequence[i - 1] {
                switches += 1
            }
        }
        return switches
    }

    // MARK: - Static Animal Lexicon

    struct LexiconEntry {
        let category: AnimalCategory

        init(_ cat: AnimalCategory) {
            category = cat
        }
    }

    /// Superordinate terms — broad category labels that count once but flag semantic degradation.
    static let superordinateTerms: Set<String> = [
        "bird", "fish", "insect", "bug", "reptile", "amphibian", "mammal", "animal", "rodent"
    ]

    // ~300 single-word animal entries with semantic categories.
    static let singleLexicon: [String: LexiconEntry] = [
        // MARK: Mammals — Pets / Domestic
        "dog": .init(.mammalPet), "cat": .init(.mammalPet), "kitten": .init(.mammalPet),
        "puppy": .init(.mammalPet), "hamster": .init(.mammalPet), "gerbil": .init(.mammalPet),
        "rabbit": .init(.mammalPet), "bunny": .init(.mammalPet), "ferret": .init(.mammalPet),
        // "guinea" removed — not an animal by itself; "guinea pig" handled as compound

        // MARK: Mammals — Farm
        "cow": .init(.mammalFarm), "pig": .init(.mammalFarm), "horse": .init(.mammalFarm),
        "sheep": .init(.mammalFarm), "goat": .init(.mammalFarm), "donkey": .init(.mammalFarm),
        "mule": .init(.mammalFarm), "chicken": .init(.mammalFarm), "rooster": .init(.mammalFarm),
        "hen": .init(.mammalFarm), "turkey": .init(.mammalFarm), "duck": .init(.mammalFarm),
        "goose": .init(.mammalFarm), "lamb": .init(.mammalFarm), "ram": .init(.mammalFarm),
        "bull": .init(.mammalFarm), "calf": .init(.mammalFarm), "ox": .init(.mammalFarm),
        "pony": .init(.mammalFarm), "stallion": .init(.mammalFarm), "mare": .init(.mammalFarm),
        "colt": .init(.mammalFarm), "llama": .init(.mammalFarm), "alpaca": .init(.mammalFarm),
        "yak": .init(.mammalFarm),

        // MARK: Mammals — Wild
        "lion": .init(.mammalWild), "tiger": .init(.mammalWild), "bear": .init(.mammalWild),
        "elephant": .init(.mammalWild), "giraffe": .init(.mammalWild), "zebra": .init(.mammalWild),
        "monkey": .init(.mammalWild), "gorilla": .init(.mammalWild), "chimpanzee": .init(.mammalWild),
        "chimp": .init(.mammalWild), "orangutan": .init(.mammalWild), "baboon": .init(.mammalWild),
        "deer": .init(.mammalWild), "moose": .init(.mammalWild), "elk": .init(.mammalWild),
        "caribou": .init(.mammalWild), "antelope": .init(.mammalWild), "gazelle": .init(.mammalWild),
        "buffalo": .init(.mammalWild), "bison": .init(.mammalWild), "rhino": .init(.mammalWild),
        "rhinoceros": .init(.mammalWild), "hippo": .init(.mammalWild), "hippopotamus": .init(.mammalWild),
        "wolf": .init(.mammalWild), "fox": .init(.mammalWild), "coyote": .init(.mammalWild),
        "hyena": .init(.mammalWild), "jackal": .init(.mammalWild),
        "cheetah": .init(.mammalWild), "leopard": .init(.mammalWild), "panther": .init(.mammalWild),
        "jaguar": .init(.mammalWild), "cougar": .init(.mammalWild), "puma": .init(.mammalWild),
        "lynx": .init(.mammalWild), "bobcat": .init(.mammalWild),
        "squirrel": .init(.mammalWild), "chipmunk": .init(.mammalWild), "raccoon": .init(.mammalWild),
        "skunk": .init(.mammalWild), "porcupine": .init(.mammalWild), "beaver": .init(.mammalWild),
        "otter": .init(.mammalWild), "badger": .init(.mammalWild), "weasel": .init(.mammalWild),
        "mink": .init(.mammalWild), "stoat": .init(.mammalWild), "mongoose": .init(.mammalWild),
        "mouse": .init(.mammalWild), "rat": .init(.mammalWild), "bat": .init(.mammalWild),
        "hedgehog": .init(.mammalWild), "mole": .init(.mammalWild), "shrew": .init(.mammalWild),
        "opossum": .init(.mammalWild), "possum": .init(.mammalWild),
        "camel": .init(.mammalWild), "dromedary": .init(.mammalWild),
        "koala": .init(.mammalWild), "kangaroo": .init(.mammalWild), "wallaby": .init(.mammalWild),
        "wombat": .init(.mammalWild), "platypus": .init(.mammalWild), "echidna": .init(.mammalWild),
        "panda": .init(.mammalWild), "sloth": .init(.mammalWild), "armadillo": .init(.mammalWild),
        "anteater": .init(.mammalWild), "aardvark": .init(.mammalWild),
        "seal": .init(.mammalWild), "walrus": .init(.mammalWild),
        "whale": .init(.mammalWild), "dolphin": .init(.mammalWild), "porpoise": .init(.mammalWild),
        "narwhal": .init(.mammalWild), "manatee": .init(.mammalWild),
        "boar": .init(.mammalWild), "warthog": .init(.mammalWild),
        "wolverine": .init(.mammalWild), "lemur": .init(.mammalWild), "gibbon": .init(.mammalWild),
        "mandrill": .init(.mammalWild), "marmoset": .init(.mammalWild), "tamarin": .init(.mammalWild),
        "tapir": .init(.mammalWild), "okapi": .init(.mammalWild), "wildebeest": .init(.mammalWild),
        "gnu": .init(.mammalWild), "impala": .init(.mammalWild), "kudu": .init(.mammalWild),
        "oryx": .init(.mammalWild), "ibex": .init(.mammalWild), "chamois": .init(.mammalWild),
        "muskrat": .init(.mammalWild), "groundhog": .init(.mammalWild), "woodchuck": .init(.mammalWild),
        // "prairie" removed — not an animal by itself; "prairie dog" handled as compound
        "chick": .init(.mammalFarm), "cub": .init(.mammalWild),
        // Superordinates — "animal" excluded: the category name itself is not
        // a valid response (like answering "fruit" on fruit fluency).
        "mammal": .init(.mammalWild), "rodent": .init(.mammalWild),

        // MARK: Birds
        "bird": .init(.bird),
        "eagle": .init(.bird), "hawk": .init(.bird), "falcon": .init(.bird),
        "owl": .init(.bird), "vulture": .init(.bird), "condor": .init(.bird),
        "kite": .init(.bird), "osprey": .init(.bird),
        "parrot": .init(.bird), "parakeet": .init(.bird), "macaw": .init(.bird),
        "cockatoo": .init(.bird), "cockatiel": .init(.bird), "budgie": .init(.bird),
        "canary": .init(.bird), "finch": .init(.bird),
        "penguin": .init(.bird), "flamingo": .init(.bird), "pelican": .init(.bird),
        "stork": .init(.bird), "heron": .init(.bird), "crane": .init(.bird),
        "egret": .init(.bird), "ibis": .init(.bird),
        "robin": .init(.bird), "crow": .init(.bird), "raven": .init(.bird),
        "jay": .init(.bird), "bluejay": .init(.bird), "magpie": .init(.bird),
        "dove": .init(.bird), "pigeon": .init(.bird),
        "sparrow": .init(.bird), "cardinal": .init(.bird), "woodpecker": .init(.bird),
        "hummingbird": .init(.bird), "swallow": .init(.bird), "swift": .init(.bird),
        "wren": .init(.bird), "warbler": .init(.bird), "thrush": .init(.bird),
        "starling": .init(.bird), "grouse": .init(.bird), "quail": .init(.bird),
        "pheasant": .init(.bird), "partridge": .init(.bird), "peacock": .init(.bird),
        "swan": .init(.bird), "seagull": .init(.bird), "gull": .init(.bird),
        "albatross": .init(.bird), "puffin": .init(.bird), "tern": .init(.bird),
        "kingfisher": .init(.bird), "toucan": .init(.bird),
        "emu": .init(.bird), "ostrich": .init(.bird), "kiwi": .init(.bird),
        "cassowary": .init(.bird), "roadrunner": .init(.bird),
        "loon": .init(.bird), "cormorant": .init(.bird),
        "oriole": .init(.bird), "chickadee": .init(.bird), "nuthatch": .init(.bird),
        "goldfinch": .init(.bird), "mockingbird": .init(.bird),

        // MARK: Fish / Aquatic
        "fish": .init(.fish),
        "shark": .init(.fish), "salmon": .init(.fish), "tuna": .init(.fish),
        "trout": .init(.fish), "bass": .init(.fish), "catfish": .init(.fish),
        "goldfish": .init(.fish), "cod": .init(.fish), "herring": .init(.fish),
        "mackerel": .init(.fish), "sardine": .init(.fish), "anchovy": .init(.fish),
        "swordfish": .init(.fish), "marlin": .init(.fish), "barracuda": .init(.fish),
        "pike": .init(.fish), "perch": .init(.fish), "carp": .init(.fish),
        "eel": .init(.fish), "ray": .init(.fish), "flounder": .init(.fish),
        "halibut": .init(.fish), "sole": .init(.fish), "minnow": .init(.fish),
        "piranha": .init(.fish), "seahorse": .init(.fish), "pufferfish": .init(.fish),
        "angelfish": .init(.fish), "clownfish": .init(.fish), "guppy": .init(.fish),
        "sturgeon": .init(.fish), "walleye": .init(.fish),

        // MARK: Reptiles
        "reptile": .init(.reptile),
        "snake": .init(.reptile), "lizard": .init(.reptile), "turtle": .init(.reptile),
        "tortoise": .init(.reptile), "alligator": .init(.reptile), "crocodile": .init(.reptile),
        "gecko": .init(.reptile), "iguana": .init(.reptile), "chameleon": .init(.reptile),
        "komodo": .init(.reptile), "cobra": .init(.reptile), "python": .init(.reptile),
        "viper": .init(.reptile), "rattlesnake": .init(.reptile), "boa": .init(.reptile),
        "anaconda": .init(.reptile), "skink": .init(.reptile), "monitor": .init(.reptile),
        "terrapin": .init(.reptile), "tuatara": .init(.reptile), "gator": .init(.reptile),

        // MARK: Amphibians
        "amphibian": .init(.amphibian),
        "frog": .init(.amphibian), "toad": .init(.amphibian), "salamander": .init(.amphibian),
        "newt": .init(.amphibian), "axolotl": .init(.amphibian), "tadpole": .init(.amphibian),
        "treefrog": .init(.amphibian),

        // MARK: Insects
        "insect": .init(.insect), "bug": .init(.insect),
        "butterfly": .init(.insect), "moth": .init(.insect), "bee": .init(.insect),
        "wasp": .init(.insect), "hornet": .init(.insect), "ant": .init(.insect),
        "beetle": .init(.insect), "ladybug": .init(.insect), "firefly": .init(.insect),
        "dragonfly": .init(.insect), "grasshopper": .init(.insect), "cricket": .init(.insect),
        "locust": .init(.insect), "cicada": .init(.insect), "mantis": .init(.insect),
        "cockroach": .init(.insect), "mosquito": .init(.insect), "fly": .init(.insect),
        "flea": .init(.insect), "tick": .init(.insect), "termite": .init(.insect),
        "caterpillar": .init(.insect), "maggot": .init(.insect), "larva": .init(.insect),
        "earwig": .init(.insect), "centipede": .init(.insect), "millipede": .init(.insect),

        // MARK: Arachnids
        "spider": .init(.arachnid), "scorpion": .init(.arachnid), "tarantula": .init(.arachnid),

        // MARK: Crustaceans
        "crab": .init(.crustacean), "lobster": .init(.crustacean), "shrimp": .init(.crustacean),
        "prawn": .init(.crustacean), "crayfish": .init(.crustacean), "crawfish": .init(.crustacean),
        "crawdad": .init(.crustacean), "barnacle": .init(.crustacean), "krill": .init(.crustacean),

        // MARK: Mollusks
        "snail": .init(.mollusk), "slug": .init(.mollusk), "clam": .init(.mollusk),
        "oyster": .init(.mollusk), "mussel": .init(.mollusk), "squid": .init(.mollusk),
        "octopus": .init(.mollusk), "nautilus": .init(.mollusk), "scallop": .init(.mollusk),
        "conch": .init(.mollusk), "abalone": .init(.mollusk), "cuttlefish": .init(.mollusk),

        // MARK: Other
        "worm": .init(.other), "leech": .init(.other), "starfish": .init(.other),
        "jellyfish": .init(.other), "coral": .init(.other), "sponge": .init(.other),
        "urchin": .init(.other), "anemone": .init(.other),
    ]

    // Compound names (2-word animals)
    static let compoundLexicon: [String: LexiconEntry] = [
        "polar bear": .init(.mammalWild), "grizzly bear": .init(.mammalWild),
        "brown bear": .init(.mammalWild), "black bear": .init(.mammalWild),
        "guinea pig": .init(.mammalPet), "prairie dog": .init(.mammalWild),
        "sea lion": .init(.mammalWild), "mountain lion": .init(.mammalWild),
        "mountain goat": .init(.mammalWild), "sea otter": .init(.mammalWild),
        "river otter": .init(.mammalWild), "honey badger": .init(.mammalWild),
        "red fox": .init(.mammalWild), "arctic fox": .init(.mammalWild),
        "gray wolf": .init(.mammalWild), "grey wolf": .init(.mammalWild),
        "bald eagle": .init(.bird), "golden eagle": .init(.bird),
        "blue jay": .init(.bird), "barn owl": .init(.bird),
        "snowy owl": .init(.bird), "horned owl": .init(.bird),
        "great white": .init(.fish), "hammerhead shark": .init(.fish),
        "whale shark": .init(.fish), "blue whale": .init(.fish),
        "killer whale": .init(.mammalWild), "humpback whale": .init(.mammalWild),
        "sperm whale": .init(.mammalWild), "beluga whale": .init(.mammalWild),
        "sea turtle": .init(.reptile), "box turtle": .init(.reptile),
        "gila monster": .init(.reptile), "komodo dragon": .init(.reptile),
        "tree frog": .init(.amphibian), "bull frog": .init(.amphibian),
        "fruit fly": .init(.insect), "praying mantis": .init(.insect),
        "lady bug": .init(.insect), "lightning bug": .init(.insect),
        "horse fly": .init(.insect), "dragon fly": .init(.insect),
        "king cobra": .init(.reptile), "coral snake": .init(.reptile),
        "german shepherd": .init(.mammalPet), "golden retriever": .init(.mammalPet),
        "labrador retriever": .init(.mammalPet), "pit bull": .init(.mammalPet),
        "border collie": .init(.mammalPet), "cocker spaniel": .init(.mammalPet),
        "hermit crab": .init(.crustacean), "horseshoe crab": .init(.crustacean),
        "king crab": .init(.crustacean),
        "howler monkey": .init(.mammalWild), "spider monkey": .init(.mammalWild),
        "flying squirrel": .init(.mammalWild), "sugar glider": .init(.mammalWild),
        "red panda": .init(.mammalWild), "giant panda": .init(.mammalWild),
        "water buffalo": .init(.mammalFarm), "cape buffalo": .init(.mammalWild),
        "african elephant": .init(.mammalWild), "asian elephant": .init(.mammalWild),
        "black widow": .init(.arachnid), "brown recluse": .init(.arachnid),
    ]
}

import Foundation

enum ReferenceProfileCombiner {
    static func merge(_ profiles: [ReferenceProfile]) -> ReferenceProfile {
        guard let first = profiles.first else {
            return ReferenceProfile(
                wordCount: 0,
                chapterCount: 0,
                gradeLevel: 0,
                averageSentenceWords: 0,
                sentenceVariation: 0,
                averageParagraphWords: 0,
                dialogueRatio: 0,
                firstPersonRatio: 0,
                thirdPersonRatio: 0,
                tempo: "unknown",
                voice: "unknown",
                tone: [],
                vocabulary: [],
                characters: []
            )
        }
        guard profiles.count > 1 else { return first }

        let totalWeight = max(profiles.reduce(0) { $0 + max($1.wordCount, 1) }, 1)
        func weighted(_ value: (ReferenceProfile) -> Double) -> Double {
            profiles.reduce(0) { partial, profile in
                partial + value(profile) * Double(max(profile.wordCount, 1))
            } / Double(totalWeight)
        }

        let firstPerson = weighted(\.firstPersonRatio)
        let thirdPerson = weighted(\.thirdPersonRatio)
        let voice: String
        if firstPerson > 0.62 {
            voice = "intimate first-person"
        } else if thirdPerson > 0.62 {
            voice = "observational third-person"
        } else {
            voice = "mixed or shifting perspective"
        }

        let averageSentence = weighted(\.averageSentenceWords)
        let averageParagraph = weighted(\.averageParagraphWords)
        let dialogue = weighted(\.dialogueRatio)
        let tempoScore = 82 - averageSentence * 1.7 - averageParagraph * 0.28 + dialogue * 34
        let tempo = tempoScore >= 56 ? "brisk" : tempoScore <= 35 ? "deliberate" : "steady"

        return ReferenceProfile(
            wordCount: profiles.reduce(0) { $0 + $1.wordCount },
            chapterCount: profiles.reduce(0) { $0 + $1.chapterCount },
            gradeLevel: weighted(\.gradeLevel),
            averageSentenceWords: averageSentence,
            sentenceVariation: weighted(\.sentenceVariation),
            averageParagraphWords: averageParagraph,
            dialogueRatio: dialogue,
            firstPersonRatio: firstPerson,
            thirdPersonRatio: thirdPerson,
            tempo: tempo,
            voice: voice,
            tone: rankedValues(profiles.flatMap(\.tone), limit: 8),
            vocabulary: rankedValues(profiles.flatMap(\.vocabulary), limit: 40),
            characters: rankedValues(profiles.flatMap(\.characters), limit: 80),
            structuralProfile: StructuralProfile.weightedMerge(
                profiles.compactMap { profile in
                    profile.structuralProfile.map { ($0, $0.sentencesAnalyzed) }
                }
            )
        )
    }

    private static func rankedValues(_ values: [String], limit: Int) -> [String] {
        var counts: [String: (display: String, count: Int)] = [:]
        for value in values where !value.isEmpty {
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let existing = counts[key] ?? (value, 0)
            counts[key] = (existing.display, existing.count + 1)
        }
        return counts.values
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.display < rhs.display : lhs.count > rhs.count
            }
            .prefix(limit)
            .map(\.display)
    }
}

enum LibraryExcerptBuilder {
    static func select(from reference: EPUBReference) -> [LibraryExcerpt] {
        guard !reference.chapters.isEmpty else { return [] }
        var excerpts: [LibraryExcerpt] = []

        append(
            chapter: reference.chapters[0],
            purpose: "Opening voice",
            to: &excerpts
        )

        if reference.chapters.count > 2 {
            append(
                chapter: reference.chapters[reference.chapters.count / 2],
                purpose: "Mid-book rhythm",
                to: &excerpts
            )
        }

        if let dialogueChapter = reference.chapters.max(by: {
            ReferenceTextTools.dialogueWordCount(in: $0.text) < ReferenceTextTools.dialogueWordCount(in: $1.text)
        }), ReferenceTextTools.dialogueWordCount(in: dialogueChapter.text) > 0 {
            append(chapter: dialogueChapter, purpose: "Dialogue and character voice", to: &excerpts)
        }

        if let variedChapter = reference.chapters.max(by: {
            sentenceSpread($0.text) < sentenceSpread($1.text)
        }) {
            append(chapter: variedChapter, purpose: "Sentence variation", to: &excerpts)
        }

        return Array(excerpts.prefix(4))
    }

    private static func append(
        chapter: ReferenceChapter,
        purpose: String,
        to excerpts: inout [LibraryExcerpt]
    ) {
        let text = compactExcerpt(chapter.text, limit: 900)
        guard text.count >= 80, !excerpts.contains(where: { $0.text == text }) else { return }
        excerpts.append(LibraryExcerpt(section: chapter.title, purpose: purpose, text: text))
    }

    private static func compactExcerpt(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        let prefix = String(normalized.prefix(limit))
        if let boundary = prefix.lastIndex(where: { ".!?…”\"".contains($0) }),
           prefix.distance(from: prefix.startIndex, to: boundary) > limit / 2 {
            return String(prefix[...boundary])
        }
        return prefix + "…"
    }

    private static func sentenceSpread(_ text: String) -> Double {
        let lengths = ReferenceTextTools.sentences(in: text)
            .map { Double(ReferenceTextTools.words(in: $0).count) }
            .filter { $0 > 0 }
        guard lengths.count > 1 else { return 0 }
        let mean = lengths.reduce(0, +) / Double(lengths.count)
        return sqrt(lengths.reduce(0) { $0 + pow($1 - mean, 2) } / Double(lengths.count))
    }
}

enum LocalGenreClassifier {
    private static let keywordGroups: [(String, Set<String>)] = [
        ("Fantasy", ["magic", "dragon", "wizard", "sword", "kingdom", "spell", "enchanted", "fae"]),
        ("Science Fiction", ["spaceship", "planet", "alien", "robot", "galaxy", "quantum", "android", "colony"]),
        ("Mystery", ["detective", "murder", "clue", "suspect", "investigation", "evidence", "alibi", "motive"]),
        ("Romance", ["romance", "kiss", "wedding", "beloved", "desire", "courtship", "relationship", "passion"]),
        ("Thriller", ["conspiracy", "hostage", "assassin", "agent", "pursuit", "weapon", "escape", "threat"]),
        ("Horror", ["haunted", "ghost", "nightmare", "terror", "corpse", "demon", "blood", "monster"]),
        ("Historical Fiction", ["empire", "regiment", "century", "monarch", "king", "queen", "colonial", "war"]),
        ("Crime", ["police", "criminal", "prison", "robbery", "gang", "trial", "crime", "officer"]),
        ("Adventure", ["journey", "expedition", "island", "voyage", "treasure", "wilderness", "quest", "explorer"]),
        ("Memoir", ["memoir", "childhood", "memory", "remembered", "family", "autobiography", "life", "mother"])
    ]

    static func classify(reference: EPUBReference) -> [String] {
        var genres: [String] = []
        for subject in reference.subjects {
            for value in subject.components(separatedBy: CharacterSet(charactersIn: ",;/|")) {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 3, cleaned.count <= 60, !genres.contains(cleaned) {
                    genres.append(cleaned)
                }
            }
        }

        let sample = String(reference.chapters.map(\.text).joined(separator: " ").prefix(600_000))
        let words = ReferenceTextTools.words(in: sample).map { $0.lowercased() }
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        let inferred = keywordGroups.compactMap { genre, keywords -> (String, Int)? in
            let score = keywords.reduce(0) { $0 + min(counts[$1, default: 0], 5) }
            return score >= 3 ? (genre, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map(\.0)

        for genre in inferred where !genres.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) {
            genres.append(genre)
        }
        return genres.isEmpty ? ["Unclassified"] : Array(genres.prefix(8))
    }
}

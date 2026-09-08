import Foundation
import NaturalLanguage

struct ManuscriptContinuitySummary {
    let entities: [ManuscriptEntity]
    let keyTerms: [ManuscriptFrequency]
    let repeatedPhrases: [ManuscriptFrequency]
    let timelineMarkers: [ManuscriptFrequency]
    let claimChecks: [ManuscriptFinding]
    let continuityChecks: [ManuscriptFinding]
}

enum ManuscriptContinuityAnalyzer {
    private static let citationRegex = try! NSRegularExpression(
        pattern: #"(?:\[[^\]]+\]\([^\)]+\)|\[\^[^\]]+\]|https?://\S+|\([A-Z][A-Za-z-]+(?:\s+(?:and|&|et al\.)\s+[A-Z][A-Za-z-]+)?,\s*(?:18|19|20)\d{2}\))"#,
        options: [.caseInsensitive]
    )
    private static let claimCueRegex = try! NSRegularExpression(
        pattern: #"\b(?:research|studies|data|evidence|experts|scientists|survey|report|statistics|according to|proves?|causes?|results? in)\b|\b\d+(?:\.\d+)?\s*%|\b(?:18|19|20)\d{2}\b"#,
        options: [.caseInsensitive]
    )
    private static let timelineRegex = try! NSRegularExpression(
        pattern: #"\b(?:(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:\s+\d{1,2})?(?:,?\s+(?:18|19|20)\d{2})?|(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)|(?:18|19|20)\d{2})\b"#,
        options: [.caseInsensitive]
    )
    private static let phraseStopwords: Set<String> = [
        "and", "the", "that", "this", "with", "from", "into", "were", "was", "are", "for",
        "but", "not", "you", "your", "his", "her", "their", "they", "she", "him", "have",
        "had", "has", "would", "could", "should", "there", "then", "than", "when", "where"
    ]

    static func analyze(
        documents: [ManuscriptDocument],
        chapters: [ManuscriptChapterMetrics]
    ) -> ManuscriptContinuitySummary {
        var entityAccumulator: [String: EntityAccumulator] = [:]
        var wordCounts: [String: Int] = [:]
        var phraseCounts: [String: Int] = [:]
        var timelineCounts: [String: Int] = [:]
        var claimChecks: [ManuscriptFinding] = []

        for document in documents {
            let words = ReferenceTextTools.words(in: document.text)
            accumulateWords(words, into: &wordCounts)
            accumulatePhrases(words, into: &phraseCounts)
            accumulateEntities(in: document, into: &entityAccumulator)
            accumulateTimeline(in: document.text, into: &timelineCounts)
            claimChecks.append(contentsOf: unsupportedClaimChecks(in: document))
        }

        addFallbackEntities(documents: documents, into: &entityAccumulator)
        let entities = makeEntities(entityAccumulator)
        let keyTerms = makeKeyTerms(wordCounts, excluding: entities)
        let repeatedPhrases = phraseCounts
            .filter { $0.value >= 3 }
            .sorted(by: frequencySort)
            .prefix(15)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }
        let timelineMarkers = timelineCounts
            .sorted(by: frequencySort)
            .prefix(30)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }

        return ManuscriptContinuitySummary(
            entities: entities,
            keyTerms: keyTerms,
            repeatedPhrases: repeatedPhrases,
            timelineMarkers: timelineMarkers,
            claimChecks: Array(claimChecks.prefix(20)),
            continuityChecks: continuityChecks(chapters: chapters, entities: entities)
        )
    }

    private static func unsupportedClaimChecks(in document: ManuscriptDocument) -> [ManuscriptFinding] {
        let sentences = ReferenceTextTools.sentences(in: document.text)
        return sentences.compactMap { sentence in
            let range = NSRange(location: 0, length: (sentence as NSString).length)
            guard claimCueRegex.firstMatch(in: sentence, range: range) != nil,
                  citationRegex.firstMatch(in: sentence, range: range) == nil else { return nil }
            let excerpt = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else { return nil }
            return ManuscriptFinding(
                title: "Check support",
                detail: String(excerpt.prefix(220)),
                chapterPath: document.relativePath
            )
        }
    }

    private static func continuityChecks(
        chapters: [ManuscriptChapterMetrics],
        entities: [ManuscriptEntity]
    ) -> [ManuscriptFinding] {
        var findings: [ManuscriptFinding] = []
        let recurring = entities.filter { $0.count >= 2 && ($0.kind == .person || $0.kind == .other) }
        for firstIndex in recurring.indices {
            for secondIndex in recurring.indices where secondIndex > firstIndex {
                let first = recurring[firstIndex]
                let second = recurring[secondIndex]
                guard first.name.first?.lowercased() == second.name.first?.lowercased(),
                      abs(first.name.count - second.name.count) <= 1,
                      levenshtein(first.name.lowercased(), second.name.lowercased()) == 1 else { continue }
                findings.append(ManuscriptFinding(
                    title: "Similar names",
                    detail: "`\(first.name)` and `\(second.name)` differ by one character. Confirm that both forms are intentional."
                ))
                if findings.count >= 8 { break }
            }
            if findings.count >= 8 { break }
        }

        let titles = Dictionary(grouping: chapters, by: { $0.title.lowercased() })
        for duplicate in titles.values where duplicate.count > 1 {
            findings.append(ManuscriptFinding(
                title: "Repeated section title",
                detail: "`\(duplicate[0].title)` appears \(duplicate.count) times."
            ))
        }

        if let minimum = chapters.min(by: { $0.gradeLevel < $1.gradeLevel }),
           let maximum = chapters.max(by: { $0.gradeLevel < $1.gradeLevel }),
           maximum.gradeLevel - minimum.gradeLevel >= 4 {
            findings.append(ManuscriptFinding(
                title: "Reading-level shift",
                detail: "`\(minimum.title)` is near grade \(format(minimum.gradeLevel)), while `\(maximum.title)` is near grade \(format(maximum.gradeLevel)). Check whether the audience or voice changes intentionally."
            ))
        }
        return findings
    }

    private static func accumulateEntities(
        in document: ManuscriptDocument,
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let text = String(document.text.prefix(500_000))
        guard !text.isEmpty else { return }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let kind: ManuscriptEntityKind
            switch tag {
            case .personalName: kind = .person
            case .placeName: kind = .place
            case .organizationName: kind = .organization
            default: return true
            }
            let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return true }
            addEntity(name: name, kind: kind, chapter: document.title, into: &accumulator)
            return true
        }
    }

    private static func addFallbackEntities(
        documents: [ManuscriptDocument],
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let combined = documents.map(\.text).joined(separator: "\n")
        for name in ReferenceTextTools.characterNames(in: String(combined.prefix(600_000))) {
            let lower = name.lowercased()
            if accumulator.values.contains(where: { $0.name.lowercased() == lower }) { continue }
            var chapters: [String] = []
            var total = 0
            for document in documents {
                let count = occurrences(of: name, in: document.text)
                if count > 0 {
                    total += count
                    chapters.append(document.title)
                }
            }
            guard total >= 2 else { continue }
            let key = "\(ManuscriptEntityKind.other.rawValue):\(lower)"
            accumulator[key] = EntityAccumulator(name: name, kind: .other, count: total, chapters: Set(chapters))
        }
    }

    private static func addEntity(
        name: String,
        kind: ManuscriptEntityKind,
        chapter: String,
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(kind.rawValue):\(clean.lowercased())"
        var value = accumulator[key] ?? EntityAccumulator(name: clean, kind: kind, count: 0, chapters: [])
        value.count += 1
        value.chapters.insert(chapter)
        accumulator[key] = value
    }

    private static func makeEntities(_ accumulator: [String: EntityAccumulator]) -> [ManuscriptEntity] {
        accumulator.values
            .filter { $0.count >= 2 }
            .map { ManuscriptEntity(
                name: $0.name,
                kind: $0.kind,
                count: $0.count,
                chapters: $0.chapters.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            ) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.count > rhs.count
            }
    }

    private static func makeKeyTerms(
        _ counts: [String: Int],
        excluding entities: [ManuscriptEntity]
    ) -> [ManuscriptFrequency] {
        let nameWords = Set(entities.flatMap { entity in
            entity.name.lowercased().split(separator: " ").map(String.init)
        })
        return counts
            .filter { word, count in
                word.count >= 5 && count >= 3 && !phraseStopwords.contains(word) && !nameWords.contains(word)
            }
            .sorted(by: frequencySort)
            .prefix(30)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }
    }

    private static func accumulateWords(_ words: [String], into counts: inout [String: Int]) {
        for raw in words.prefix(500_000) {
            counts[raw.lowercased(), default: 0] += 1
        }
    }

    private static func accumulatePhrases(_ words: [String], into counts: inout [String: Int]) {
        let lowered = words.prefix(500_000).map { $0.lowercased() }
        guard lowered.count >= 3 else { return }
        for index in 0...(lowered.count - 3) {
            let slice = Array(lowered[index..<(index + 3)])
            guard slice.allSatisfy({ $0.count > 2 }),
                  !phraseStopwords.contains(slice[0]),
                  !phraseStopwords.contains(slice[2]) else { continue }
            counts[slice.joined(separator: " "), default: 0] += 1
        }
    }

    private static func accumulateTimeline(in text: String, into counts: inout [String: Int]) {
        let source = text as NSString
        for match in matches(timelineRegex, in: text) {
            let value = source.substring(with: match.range)
            let key = value.prefix(1).uppercased() + value.dropFirst().lowercased()
            counts[key, default: 0] += 1
        }
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static func frequencySort(
        _ lhs: Dictionary<String, Int>.Element,
        _ rhs: Dictionary<String, Int>.Element
    ) -> Bool {
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }

    private static func levenshtein(_ first: String, _ second: String) -> Int {
        let first = Array(first)
        let second = Array(second)
        guard !first.isEmpty else { return second.count }
        guard !second.isEmpty else { return first.count }
        var previous = Array(0...second.count)
        for (firstIndex, firstCharacter) in first.enumerated() {
            var current = [firstIndex + 1]
            for (secondIndex, secondCharacter) in second.enumerated() {
                current.append(min(
                    current[secondIndex] + 1,
                    previous[secondIndex + 1] + 1,
                    previous[secondIndex] + (firstCharacter == secondCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[second.count]
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct EntityAccumulator {
    let name: String
    let kind: ManuscriptEntityKind
    var count: Int
    var chapters: Set<String>
}

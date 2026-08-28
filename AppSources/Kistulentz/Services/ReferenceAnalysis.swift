import Foundation
import NaturalLanguage

enum ReferenceProfileBuilder {
    static func build(chapters: [ReferenceChapter]) -> ReferenceProfile {
        let text = chapters.map(\.text).joined(separator: "\n\n")
        let words = ReferenceTextTools.words(in: text)
        let sentences = ReferenceTextTools.sentences(in: text)
        let sentenceLengths = sentences.map { Double(ReferenceTextTools.words(in: $0).count) }.filter { $0 > 0 }
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let paragraphLengths = paragraphs.map { Double(ReferenceTextTools.words(in: $0).count) }.filter { $0 > 0 }
        let stats = ReadabilityEngine.calculateStats(for: text, targetGrade: 8)

        let averageSentence = average(sentenceLengths)
        let sentenceVariation = standardDeviation(sentenceLengths, mean: averageSentence)
        let averageParagraph = average(paragraphLengths)
        let dialogueWords = ReferenceTextTools.dialogueWordCount(in: text)
        let dialogueRatio = words.isEmpty ? 0 : Double(dialogueWords) / Double(words.count)
        let lowered = words.map { $0.lowercased() }
        let firstCount = lowered.filter { ReferenceTextTools.firstPersonPronouns.contains($0) }.count
        let thirdCount = lowered.filter { ReferenceTextTools.thirdPersonPronouns.contains($0) }.count
        let pronounTotal = max(firstCount + thirdCount, 1)
        let firstRatio = Double(firstCount) / Double(pronounTotal)
        let thirdRatio = Double(thirdCount) / Double(pronounTotal)
        let characters = ReferenceTextTools.characterNames(in: String(text.prefix(450_000)))
        let vocabulary = ReferenceTextTools.frequentVocabulary(in: words, excluding: characters)

        let voice: String
        if firstRatio > 0.62 {
            voice = "intimate first-person"
        } else if thirdRatio > 0.62 {
            voice = "observational third-person"
        } else {
            voice = "mixed or shifting perspective"
        }

        let tempoScore = 82 - averageSentence * 1.7 - averageParagraph * 0.28 + dialogueRatio * 34
        let tempo: String
        if tempoScore >= 56 {
            tempo = "brisk"
        } else if tempoScore <= 35 {
            tempo = "deliberate"
        } else {
            tempo = "steady"
        }

        var tone: [String] = []
        tone.append(dialogueRatio > 0.28 ? "dialogue-forward" : "narrative-forward")
        tone.append(averageSentence < 13 ? "direct" : averageSentence > 21 ? "measured" : "balanced")
        tone.append(sentenceVariation > 10 ? "rhythmically varied" : "rhythmically even")
        let exclamationRatio = words.isEmpty ? 0 : Double(text.filter { $0 == "!" }.count) / Double(words.count)
        if exclamationRatio > 0.008 { tone.append("energetic") }
        let questionRatio = words.isEmpty ? 0 : Double(text.filter { $0 == "?" }.count) / Double(words.count)
        if questionRatio > 0.012 { tone.append("inquisitive") }

        return ReferenceProfile(
            wordCount: words.count,
            chapterCount: chapters.count,
            gradeLevel: stats.gradeLevel,
            averageSentenceWords: averageSentence,
            sentenceVariation: sentenceVariation,
            averageParagraphWords: averageParagraph,
            dialogueRatio: dialogueRatio,
            firstPersonRatio: firstRatio,
            thirdPersonRatio: thirdRatio,
            tempo: tempo,
            voice: voice,
            tone: tone,
            vocabulary: vocabulary,
            characters: characters
        )
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}

enum ReferenceComparison {
    static func analyze(draft: String, against reference: EPUBReference) -> ReferenceAlignment {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        let draftChapter = ReferenceChapter(id: 0, title: "Current draft", text: draft)
        let draftProfile = ReferenceProfileBuilder.build(chapters: [draftChapter])
        let referenceProfile = reference.profile
        var score = 100
        var notes: [ReferenceNote] = []

        let sentenceDifference = abs(draftProfile.averageSentenceWords - referenceProfile.averageSentenceWords)
        let sentenceAligned = sentenceDifference <= 3.5
        if !sentenceAligned { score -= min(22, Int(sentenceDifference * 2.2)) }
        notes.append(ReferenceNote(
            title: "Sentence rhythm",
            detail: sentenceAligned
                ? "Sentence length is close to the reference."
                : "Draft averages \(draftProfile.averageSentenceWords.formatted(.number.precision(.fractionLength(1)))) words; reference averages \(referenceProfile.averageSentenceWords.formatted(.number.precision(.fractionLength(1)))).",
            isAligned: sentenceAligned
        ))

        let dialogueDifference = abs(draftProfile.dialogueRatio - referenceProfile.dialogueRatio)
        let dialogueAligned = dialogueDifference <= 0.10
        if !dialogueAligned { score -= min(20, Int(dialogueDifference * 90)) }
        notes.append(ReferenceNote(
            title: "Dialogue balance",
            detail: dialogueAligned
                ? "Dialogue density matches the reference closely."
                : "Dialogue occupies \((draftProfile.dialogueRatio * 100).formatted(.number.precision(.fractionLength(0))))% of the draft versus \((referenceProfile.dialogueRatio * 100).formatted(.number.precision(.fractionLength(0))))% of the reference.",
            isAligned: dialogueAligned
        ))

        let voiceAligned = perspective(profile: draftProfile) == perspective(profile: referenceProfile)
        if !voiceAligned { score -= 22 }
        notes.append(ReferenceNote(
            title: "Narrative voice",
            detail: voiceAligned
                ? "The draft and reference use a similar point of view."
                : "Draft voice is \(draftProfile.voice); reference voice is \(referenceProfile.voice).",
            isAligned: voiceAligned
        ))

        let tempoAligned = draftProfile.tempo == referenceProfile.tempo
        if !tempoAligned { score -= 14 }
        notes.append(ReferenceNote(
            title: "Tempo",
            detail: tempoAligned
                ? "Both texts have a \(referenceProfile.tempo) tempo."
                : "Draft tempo is \(draftProfile.tempo); reference tempo is \(referenceProfile.tempo).",
            isAligned: tempoAligned
        ))

        let issues = continuityIssues(in: draft, referenceNames: referenceProfile.characters)
        if !issues.isEmpty { score -= min(12, issues.count * 4) }

        return ReferenceAlignment(score: max(0, score), notes: notes, issues: issues)
    }

    private static func perspective(profile: ReferenceProfile) -> String {
        if profile.firstPersonRatio > 0.62 { return "first" }
        if profile.thirdPersonRatio > 0.62 { return "third" }
        return "mixed"
    }

    private static func continuityIssues(in draft: String, referenceNames: [String]) -> [WritingIssue] {
        guard !referenceNames.isEmpty else { return [] }
        let referenceTokens = Set(referenceNames.flatMap { name in
            [name] + name.split(separator: " ").map(String.init)
        })
        let draftNames = ReferenceTextTools.characterNames(in: draft)
        let source = draft as NSString
        var issues: [WritingIssue] = []

        for name in draftNames where !referenceTokens.contains(name) {
            guard let replacement = referenceTokens
                .filter({ abs($0.count - name.count) <= 1 })
                .min(by: { levenshtein(name.lowercased(), $0.lowercased()) < levenshtein(name.lowercased(), $1.lowercased()) }),
                  levenshtein(name.lowercased(), replacement.lowercased()) == 1 else {
                continue
            }
            let range = source.range(of: name)
            guard range.location != NSNotFound else { continue }
            issues.append(WritingIssue(
                category: .continuity,
                range: range,
                excerpt: name,
                message: "This name is one character away from \(replacement) in the reference book. Check continuity.",
                replacement: replacement,
                source: .local
            ))
        }
        return issues
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)

        for (i, ca) in a.enumerated() {
            var current = [i + 1]
            for (j, cb) in b.enumerated() {
                let insertion = current[j] + 1
                let deletion = previous[j + 1] + 1
                let substitution = previous[j] + (ca == cb ? 0 : 1)
                current.append(min(min(insertion, deletion), substitution))
            }
            previous = current
        }
        return previous[b.count]
    }
}

extension EPUBReference {
    func selectedExcerpts(relevantTo draft: String, maxCharacters: Int = 16_000) -> String {
        guard !chapters.isEmpty, maxCharacters > 0 else { return "" }
        let keywords = Set(ReferenceTextTools.significantWords(in: draft).prefix(24))
        let scored = chapters.map { chapter -> (ReferenceChapter, Int) in
            let chapterWords = ReferenceTextTools.words(in: chapter.text).map { $0.lowercased() }
            return (chapter, chapterWords.reduce(0) { $0 + (keywords.contains($1) ? 1 : 0) })
        }

        var selectedIDs: [Int] = []
        func add(_ id: Int) {
            if !selectedIDs.contains(id) { selectedIDs.append(id) }
        }
        add(chapters[0].id)
        add(chapters[chapters.count / 2].id)
        add(chapters[chapters.count - 1].id)
        for item in scored.sorted(by: { $0.1 > $1.1 }).prefix(3) { add(item.0.id) }

        var remaining = maxCharacters
        var sections: [String] = []
        for id in selectedIDs {
            guard remaining > 400, let chapter = chapters.first(where: { $0.id == id }) else { continue }
            let allowance = min(3_200, remaining - 120)
            let excerpt = bestExcerpt(from: chapter.text, keywords: keywords, limit: allowance)
            let section = "[\(chapter.title)]\n\(excerpt)"
            sections.append(section)
            remaining -= section.count
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    private func bestExcerpt(from text: String, keywords: Set<String>, limit: Int) -> String {
        guard text.count > limit else { return text }
        let lowered = text.lowercased()
        let firstMatch = keywords.compactMap { lowered.range(of: $0)?.lowerBound }.min()
        let centerOffset = firstMatch.map { lowered.distance(from: lowered.startIndex, to: $0) } ?? 0
        let startOffset = max(0, min(text.count - limit, centerOffset - limit / 3))
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(start, offsetBy: min(limit, text.distance(from: start, to: text.endIndex)))
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ReferenceTextTools {
    static let firstPersonPronouns: Set<String> = ["i", "me", "my", "mine", "myself", "we", "us", "our", "ours"]
    static let thirdPersonPronouns: Set<String> = ["he", "him", "his", "she", "her", "hers", "they", "them", "their", "theirs"]

    private static let stopwords: Set<String> = [
        "about", "after", "again", "against", "almost", "along", "already", "also", "although",
        "always", "among", "another", "around", "because", "before", "being", "between", "both",
        "could", "every", "first", "found", "from", "great", "have", "having", "into", "itself",
        "just", "know", "like", "little", "made", "many", "might", "more", "most", "much", "must",
        "never", "other", "over", "really", "right", "same", "should", "since", "some", "something",
        "still", "such", "than", "that", "their", "there", "these", "thing", "think", "this", "those",
        "through", "under", "until", "very", "want", "well", "were", "what", "when", "where", "which",
        "while", "would", "your", "said", "says", "looked", "turned", "asked"
    ]

    static func words(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Za-z]+(?:['’][A-Za-z]+)?\b"#) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    static func sentences(in text: String) -> [String] {
        var values: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) {
            _, range, _, _ in values.append(String(text[range]))
        }
        return values
    }

    static func dialogueWordCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"[\"“][^\"”]{2,}[\"”]"#) else { return 0 }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .reduce(0) { $0 + words(in: source.substring(with: $1.range)).count }
    }

    static func characterNames(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String: Int] = [:]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .personalName {
                let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2 { counts[name, default: 0] += 1 }
            }
            return true
        }

        if counts.isEmpty {
            let source = text as NSString
            if let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})?\b"#) {
                for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                    let candidate = source.substring(with: match.range)
                    guard !stopwords.contains(candidate.lowercased()) else { continue }
                    counts[candidate, default: 0] += 1
                }
            }
        }

        return counts
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(30)
            .map(\.key)
    }

    static func frequentVocabulary(in words: [String], excluding names: [String]) -> [String] {
        let nameWords = Set(names.flatMap { $0.lowercased().split(separator: " ").map(String.init) })
        var counts: [String: Int] = [:]
        for raw in words {
            let word = raw.lowercased()
            guard word.count >= 5, !stopwords.contains(word), !nameWords.contains(word) else { continue }
            counts[word, default: 0] += 1
        }
        return counts
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(24)
            .map(\.key)
    }

    static func significantWords(in text: String) -> [String] {
        let filtered = words(in: text).map { $0.lowercased() }.filter { $0.count >= 5 && !stopwords.contains($0) }
        var counts: [String: Int] = [:]
        for word in filtered { counts[word, default: 0] += 1 }
        return counts.sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }.map(\.key)
    }
}

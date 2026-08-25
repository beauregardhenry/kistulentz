import Foundation

struct ReadabilityEngine {
    private static let adverbPattern = try! NSRegularExpression(
        pattern: #"\b[A-Za-z]+ly\b"#,
        options: [.caseInsensitive]
    )

    private static let passivePattern = try! NSRegularExpression(
        pattern: #"\b(?:am|are|is|was|were|be|been|being)\s+(?:\w+\s+){0,2}\w+(?:ed|en|wn|nt)\b"#,
        options: [.caseInsensitive]
    )

    private static let markdownPatterns = [
        #"```[\s\S]*?```"#,
        #"`([^`]*)`"#,
        #"!\[[^\]]*\]\([^\)]*\)"#,
        #"\[([^\]]+)\]\([^\)]*\)"#,
        #"^\s{0,3}#{1,6}\s+"#,
        #"[*_~>]"#
    ]

    private static let simplerPhrases: [(String, String)] = [
        ("due to the fact that", "because"),
        ("at this point in time", "now"),
        ("has the ability to", "can"),
        ("in order to", "to"),
        ("a number of", "several"),
        ("for the purpose of", "to"),
        ("utilize", "use"),
        ("numerous", "many"),
        ("additional", "more"),
        ("assistance", "help"),
        ("commence", "start"),
        ("terminate", "end"),
        ("regarding", "about"),
        ("demonstrate", "show")
    ]

    private static let adverbExceptions: Set<String> = [
        "daily", "early", "family", "friendly", "likely", "lively", "lonely",
        "lovely", "only", "silly", "ugly", "weekly"
    ]

    static func analyze(_ text: String, targetGrade: Int) -> AnalysisResult {
        let readableText = strippingMarkdown(from: text)
        let stats = calculateStats(for: readableText, targetGrade: targetGrade)
        var issues = sentenceIssues(in: text, targetGrade: targetGrade)
        issues.append(contentsOf: regexIssues(in: text))
        issues.append(contentsOf: phraseIssues(in: text))
        return AnalysisResult(stats: stats, issues: issues.sorted(by: issueSort))
    }

    static func calculateStats(for text: String, targetGrade: Int) -> WritingStats {
        let words = wordMatches(in: text)
        let sentences = sentenceRanges(in: text).count
        let syllables = words.reduce(0) { $0 + syllableCount(in: $1) }
        let wordCount = words.count
        let sentenceCount = max(sentences, wordCount > 0 ? 1 : 0)

        let grade: Double
        if wordCount == 0 {
            grade = 0
        } else {
            grade = 0.39 * (Double(wordCount) / Double(max(sentenceCount, 1)))
                + 11.8 * (Double(syllables) / Double(wordCount))
                - 15.59
        }

        let boundedGrade = max(0, min(18, grade))
        let distancePenalty = abs(boundedGrade - Double(targetGrade)) * 8
        let score = max(0, min(100, Int((100 - distancePenalty).rounded())))

        return WritingStats(
            words: wordCount,
            sentences: sentenceCount,
            characters: text.count,
            readingMinutes: wordCount == 0 ? 0 : max(1, Int(ceil(Double(wordCount) / 225.0))),
            gradeLevel: boundedGrade,
            readabilityScore: score
        )
    }

    private static func sentenceIssues(in text: String, targetGrade: Int) -> [WritingIssue] {
        let hardThreshold: Int
        let veryHardThreshold: Int
        switch targetGrade {
        case ...8:
            (hardThreshold, veryHardThreshold) = (18, 26)
        case 9...10:
            (hardThreshold, veryHardThreshold) = (22, 30)
        default:
            (hardThreshold, veryHardThreshold) = (26, 34)
        }

        let source = text as NSString
        return sentenceRanges(in: text).compactMap { range in
            let sentence = source.substring(with: range)
            let count = wordMatches(in: sentence).count
            guard count > hardThreshold else { return nil }

            if count > veryHardThreshold {
                return WritingIssue(
                    category: .veryHardSentence,
                    range: range,
                    excerpt: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    message: "This sentence has \(count) words. Split it into two or more sentences."
                )
            }

            return WritingIssue(
                category: .hardSentence,
                range: range,
                excerpt: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                message: "This sentence has \(count) words. A shorter structure would be easier to follow."
            )
        }
    }

    private static func regexIssues(in text: String) -> [WritingIssue] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let source = text as NSString
        var issues: [WritingIssue] = []

        for match in adverbPattern.matches(in: text, range: fullRange) {
            let word = source.substring(with: match.range)
            guard !adverbExceptions.contains(word.lowercased()) else { continue }
            issues.append(WritingIssue(
                category: .adverb,
                range: match.range,
                excerpt: word,
                message: "Check whether this adverb adds meaning. A stronger verb may work better."
            ))
        }

        for match in passivePattern.matches(in: text, range: fullRange) {
            let phrase = source.substring(with: match.range)
            issues.append(WritingIssue(
                category: .passiveVoice,
                range: match.range,
                excerpt: phrase,
                message: "Name the actor and use an active verb when possible."
            ))
        }

        return issues
    }

    private static func phraseIssues(in text: String) -> [WritingIssue] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var issues: [WritingIssue] = []

        for (phrase, replacement) in simplerPhrases {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: text, range: fullRange) {
                issues.append(WritingIssue(
                    category: .complexPhrase,
                    range: match.range,
                    excerpt: source.substring(with: match.range),
                    message: "Use a simpler alternative.",
                    replacement: replacement
                ))
            }
        }
        return issues
    }

    private static func wordMatches(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Za-z]+(?:['’][A-Za-z]+)?\b"#) else {
            return []
        }
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        return regex.matches(in: text, range: range).map { source.substring(with: $0.range) }
    }

    private static func sentenceRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) {
            _, range, _, _ in
            ranges.append(NSRange(range, in: text))
        }
        return ranges
    }

    private static func strippingMarkdown(from text: String) -> String {
        var result = text
        for pattern in markdownPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        return result
    }

    private static func syllableCount(in rawWord: String) -> Int {
        var word = rawWord.lowercased().filter(\.isLetter)
        guard !word.isEmpty else { return 0 }
        if word.count <= 3 { return 1 }

        if word.hasSuffix("e"), !word.hasSuffix("le") {
            word.removeLast()
        }

        var count = 0
        var previousWasVowel = false
        for character in word {
            let isVowel = "aeiouy".contains(character)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        return max(1, count)
    }

    private static func issueSort(lhs: WritingIssue, rhs: WritingIssue) -> Bool {
        if lhs.range.location == rhs.range.location {
            return lhs.range.length > rhs.range.length
        }
        return lhs.range.location < rhs.range.location
    }
}

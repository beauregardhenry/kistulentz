import AppKit
import Foundation

/// Adapts the spelling and grammar services built into macOS into Kistulentz
/// correction cards. This service never sends text off the Mac.
@MainActor
enum NativeWritingService {
    static func issues(
        in text: String,
        language: String = "en_US",
        maximumIssues: Int = 100,
        checker: NSSpellChecker = .shared
    ) -> [WritingIssue] {
        guard !text.isEmpty, maximumIssues > 0 else { return [] }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let protectedRanges = MarkdownProtectedRangeFinder.ranges(in: text)
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var issues: [WritingIssue] = []
        let orthography = NSOrthography(
            dominantScript: "Latn",
            languageMap: ["Latn": [language]]
        )
        let spellingResults = checker.check(
            text,
            range: fullRange,
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: [.orthography: orthography],
            inSpellDocumentWithTag: tag,
            orthography: nil,
            wordCount: nil
        )

        for result in spellingResults where issues.count < maximumIssues {
            let range = result.range
            guard isValid(range, in: source), !intersectsProtected(range, protectedRanges) else { continue }
            let excerpt = source.substring(with: range)
            let replacement = checker.guesses(
                forWordRange: range,
                in: text,
                language: language,
                inSpellDocumentWithTag: tag
            )?.first(where: { !$0.isEmpty && $0 != excerpt })
            issues.append(WritingIssue(
                category: .spelling,
                range: range,
                excerpt: excerpt,
                message: replacement.map { "macOS suggests “\($0)” for this spelling." }
                    ?? "macOS could not find this word in the selected English dictionary.",
                replacement: replacement,
                source: .system
            ))
        }

        var searchOffset = 0
        while searchOffset < source.length, issues.count < maximumIssues {
            var rawDetails: NSArray?
            let sentenceRange = checker.checkGrammar(
                of: text,
                startingAt: searchOffset,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: tag,
                details: &rawDetails
            )
            guard sentenceRange.location != NSNotFound,
                  isValid(sentenceRange, in: source) else { break }

            for case let detail as NSDictionary in rawDetails ?? [] where issues.count < maximumIssues {
                let relativeRange = (detail[NSGrammarRange] as? NSValue)?.rangeValue
                    ?? NSRange(location: 0, length: sentenceRange.length)
                let range = NSRange(
                    location: sentenceRange.location + relativeRange.location,
                    length: relativeRange.length
                )
                guard isValid(range, in: source), !intersectsProtected(range, protectedRanges) else { continue }
                let excerpt = source.substring(with: range)
                let corrections = detail[NSGrammarCorrections] as? [String] ?? []
                let replacement = bestGrammarCorrection(
                    corrections,
                    sentenceRange: sentenceRange,
                    issueRange: range,
                    in: text,
                    language: language,
                    checker: checker,
                    tag: tag
                )
                let message = (detail[NSGrammarUserDescription] as? String)
                    ?? "macOS found a possible grammar problem."
                issues.append(WritingIssue(
                    category: .grammar,
                    range: range,
                    excerpt: excerpt,
                    message: message,
                    replacement: replacement,
                    source: .system
                ))
            }

            let nextOffset = NSMaxRange(sentenceRange)
            searchOffset = nextOffset > searchOffset ? nextOffset : searchOffset + 1
        }

        return issues.sorted {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
    }

    private static func bestGrammarCorrection(
        _ corrections: [String],
        sentenceRange: NSRange,
        issueRange: NSRange,
        in text: String,
        language: String,
        checker: NSSpellChecker,
        tag: Int
    ) -> String? {
        guard !corrections.isEmpty else { return nil }
        let source = text as NSString
        let sentence = source.substring(with: sentenceRange)
        let relativeRange = NSRange(
            location: issueRange.location - sentenceRange.location,
            length: issueRange.length
        )
        let baselineCount = grammarIssueCount(
            in: sentence,
            language: language,
            checker: checker,
            tag: tag
        )
        var best: (replacement: String, count: Int)?

        for correction in corrections where !correction.isEmpty {
            let candidate = (sentence as NSString).replacingCharacters(in: relativeRange, with: correction)
            let count = grammarIssueCount(
                in: candidate,
                language: language,
                checker: checker,
                tag: tag
            )
            if best == nil || count < best!.count {
                best = (correction, count)
            }
        }
        guard let best, best.count < baselineCount else { return nil }
        return best.replacement
    }

    private static func grammarIssueCount(
        in text: String,
        language: String,
        checker: NSSpellChecker,
        tag: Int
    ) -> Int {
        let source = text as NSString
        var offset = 0
        var count = 0
        while offset < source.length, count < 20 {
            var details: NSArray?
            let range = checker.checkGrammar(
                of: text,
                startingAt: offset,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: tag,
                details: &details
            )
            guard range.location != NSNotFound, isValid(range, in: source) else { break }
            count += max(1, details?.count ?? 0)
            let nextOffset = NSMaxRange(range)
            offset = nextOffset > offset ? nextOffset : offset + 1
        }
        return count
    }

    private static func intersectsProtected(_ range: NSRange, _ protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func isValid(_ range: NSRange, in text: NSString) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length > 0
            && NSMaxRange(range) <= text.length
    }
}

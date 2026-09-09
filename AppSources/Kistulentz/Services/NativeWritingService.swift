import AppKit
import Foundation

private enum NativeCheckKind: Sendable {
    case spelling
    case grammar
    case unsupported
}

private struct NativeGrammarDetail: Sendable {
    var range: NSRange?
    var corrections: [String]
    var message: String?
}

private struct NativeCheckResult: Sendable {
    var kind: NativeCheckKind
    var range: NSRange
    var grammarDetails: [NativeGrammarDetail]
}

/// Adapts the spelling and grammar services built into macOS into Kistulentz
/// correction cards. This service never sends text off the Mac.
@MainActor
enum NativeWritingService {
    static func issues(
        in text: String,
        language: String = "en_US",
        maximumIssues: Int = 100,
        checker: NSSpellChecker = .shared
    ) async -> [WritingIssue] {
        guard !text.isEmpty, maximumIssues > 0 else { return [] }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let protectedRanges = MarkdownProtectedRangeFinder.ranges(in: text)
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        let checkingTypes = NSTextCheckingResult.CheckingType.spelling.rawValue
            | NSTextCheckingResult.CheckingType.grammar.rawValue
        var issues: [WritingIssue] = []
        let orthography = NSOrthography(
            dominantScript: "Latn",
            languageMap: ["Latn": [language]]
        )
        let results: [NativeCheckResult] = await withCheckedContinuation { continuation in
            checker.requestChecking(
                of: text,
                range: fullRange,
                types: checkingTypes,
                options: [.orthography: orthography],
                inSpellDocumentWithTag: tag
            ) { @Sendable _, results, _, _ in
                let values = results.map { result in
                    let kind: NativeCheckKind
                    switch result.resultType {
                    case .spelling: kind = .spelling
                    case .grammar: kind = .grammar
                    default: kind = .unsupported
                    }
                    let details = (result.grammarDetails ?? []).map { detail in
                        NativeGrammarDetail(
                            range: (detail[NSGrammarRange] as? NSValue)?.rangeValue,
                            corrections: detail[NSGrammarCorrections] as? [String] ?? [],
                            message: detail[NSGrammarUserDescription] as? String
                        )
                    }
                    return NativeCheckResult(kind: kind, range: result.range, grammarDetails: details)
                }
                continuation.resume(returning: values)
            }
        }
        guard !Task.isCancelled else { return [] }

        let spellingResults = results.filter { $0.kind == .spelling }
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

        let grammarResults = results.filter { $0.kind == .grammar }
        for result in grammarResults where issues.count < maximumIssues {
            let sentenceRange = result.range
            guard isValid(sentenceRange, in: source) else { continue }
            for detail in result.grammarDetails where issues.count < maximumIssues {
                let relativeRange = detail.range
                    ?? NSRange(location: 0, length: sentenceRange.length)
                let range = NSRange(
                    location: sentenceRange.location + relativeRange.location,
                    length: relativeRange.length
                )
                guard isValid(range, in: source), !intersectsProtected(range, protectedRanges) else { continue }
                let excerpt = source.substring(with: range)
                let replacement = detail.corrections.first { !$0.isEmpty && $0 != excerpt }
                let message = detail.message
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
        }

        return issues.sorted {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
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

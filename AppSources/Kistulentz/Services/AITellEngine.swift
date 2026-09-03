import Foundation

/// Flags prose patterns that read as generic AI phrasing rather than a specific author's voice:
/// the "isn't just X, it's Y" correlative construction, stock rhetorical wind-ups ("here's the
/// thing", "let's be honest"), formulaic openers, filler "just"/"actually", stacked hedge words,
/// and the "No X. No Y. Just Z." marketing triad.
///
/// Every issue this engine produces is advisory only — none carries a `replacement`. Unlike a
/// simpler-phrase swap ("utilize" → "use"), there is no single safe rewrite for a correlative
/// construction or a stock opener; the fix always depends on what the author actually means, so a
/// human has to write it. `LocalPolishService` already treats an issue with no `replacement` as
/// advisory, so these surface as highlights and Style & Voice review cards without ever touching
/// manuscript text on their own — the same guarantee the Benepar structural-complexity highlights
/// already give.
///
/// A few checks that would be easy to add and are common in generic marketing copy are
/// deliberately left out: a blanket em dash ban, a flat "no passive voice," or a general
/// three-short-sentences-in-a-row rule. Fiction and essayistic nonfiction use all three
/// legitimately and often, and Kistulentz's own readability engine already covers passive voice.
/// The tell isn't any single device — it's the cluster of stock phrasing below appearing at all.
enum AITellEngine {
    private static let correlativeChecks: [(regex: NSRegularExpression, message: String)] = [
        (
            regex: try! NSRegularExpression(
                pattern: #"\b(?:isn'?t|aren'?t|wasn'?t|weren'?t)\s+just\s+[^.!?:;]{1,80}?[,;:—-]\s*(?:it's|it\s+is|it\s+was|they'?re|they\s+are|they\s+were)\b"#,
                options: [.caseInsensitive]
            ),
            message: "This \"isn't just X, it's Y\" shape is the single most common AI tell. State the point directly instead of setting it up this way."
        ),
        (
            regex: try! NSRegularExpression(
                pattern: #"\b(?:it's|it\s+is)\s+not\s+about\s+[^.!?:;]{1,60}?,\s*(?:it's|it\s+is)\s+about\b"#,
                options: [.caseInsensitive]
            ),
            message: "This \"it's not about X, it's about Y\" setup announces the point instead of making it. Say what you mean directly."
        )
    ]

    private static let stockPhraseChecks: [(regex: NSRegularExpression, message: String)] = [
        (#"\bhere'?s the thing\b"#, "This wind-up phrase announces a point instead of making it. Cut it and start with the point."),
        (#"\blet'?s be honest\b"#, "This is a stock AI wind-up. State the honest point directly instead of announcing that you're about to."),
        (#"\bat the end of the day\b"#, "This is a filler transition, not an idea. Say what you actually mean."),
        (#"\bthe truth is\b"#, "State the claim directly instead of announcing that it's true."),
        (#"\bthe reality is\b"#, "State the claim directly instead of announcing that it's real."),
        (#"\blet that sink in\b"#, "This is a stock AI flourish. Trust the sentence before it to land on its own."),
        (#"\bnow more than ever\b"#, "This intensifier rarely adds real content. Cut it or replace it with the specific reason things changed."),
        (#"\bwhat if i told you\b"#, "This is a stock AI hook. Just say the thing."),
        (#"\bthe best part\?"#, "This rhetorical question is a stock AI flourish. State the point directly."),
        (#"\bthe secret\?"#, "This rhetorical question is a stock AI flourish. State the point directly."),
        (#"\bsounds impossible\?"#, "This rhetorical setup is a stock AI flourish. State the point directly.")
    ].map { pattern, message in
        (regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), message: message)
    }

    private static let stockOpenerChecks: [(regex: NSRegularExpression, message: String)] = [
        (#"^\s*in the ever-evolving world of\b"#, "This is a stock AI opener. Start with the actual first thing you want to say."),
        (#"^\s*in today'?s fast-paced\b"#, "This is a stock AI opener. Start with the actual first thing you want to say."),
        (#"^\s*gone are the days when\b"#, "This is a stock AI opener. Start with the actual first thing you want to say."),
        (#"^\s*in an era where\b"#, "This is a stock AI opener. Start with the actual first thing you want to say.")
    ].map { pattern, message in
        (regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]), message: message)
    }

    private static let staccatoTriadPattern = try! NSRegularExpression(
        pattern: #"\bNo\s+[A-Za-z][\w']{0,20}\.\s+No\s+[A-Za-z][\w']{0,20}\.\s+(?:Just|Only)\s+[A-Za-z][\w']{0,20}\."#,
        options: [.caseInsensitive]
    )

    private static let hedgeWordPattern = try! NSRegularExpression(
        pattern: #"\b(?:might|could|perhaps|possibly|maybe|somewhat)\b"#,
        options: [.caseInsensitive]
    )

    private static let justPattern = try! NSRegularExpression(pattern: #"\bjust\b"#, options: [.caseInsensitive])
    private static let justExceptionPattern = try! NSRegularExpression(
        pattern: #"\bjust\s+(?:in\s+case|started|starting|one|now|then|a\s+moment|yet|about)\b"#,
        options: [.caseInsensitive]
    )
    private static let actuallyPattern = try! NSRegularExpression(pattern: #"\bactually\b"#, options: [.caseInsensitive])

    /// Every AI-tell check the engine runs against `text`, merged into a single issue list. Called
    /// from `ReadabilityEngine.analyze`, so it participates automatically wherever that does: the
    /// live editor, whole-project Style & Voice polish, and the `SuggestionRuleValidator` safety
    /// check that stops an AI rewrite from quietly introducing a new correlative construction.
    static func analyze(_ text: String) -> [WritingIssue] {
        var issues: [WritingIssue] = []
        issues.append(contentsOf: patternIssues(correlativeChecks, in: text))
        issues.append(contentsOf: patternIssues(stockPhraseChecks, in: text))
        issues.append(contentsOf: patternIssues(stockOpenerChecks, in: text))
        issues.append(contentsOf: staccatoIssues(in: text))
        issues.append(contentsOf: hedgeStackIssues(in: text))
        issues.append(contentsOf: fillerJustIssues(in: text))
        issues.append(contentsOf: overusedActuallyIssues(in: text))
        return issues
    }

    private static func patternIssues(
        _ checks: [(regex: NSRegularExpression, message: String)],
        in text: String
    ) -> [WritingIssue] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var issues: [WritingIssue] = []
        for check in checks {
            for match in check.regex.matches(in: text, range: fullRange) {
                issues.append(WritingIssue(
                    category: .aiTell,
                    range: match.range,
                    excerpt: source.substring(with: match.range),
                    message: check.message
                ))
            }
        }
        return issues
    }

    private static func staccatoIssues(in text: String) -> [WritingIssue] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        return staccatoTriadPattern.matches(in: text, range: fullRange).map { match in
            WritingIssue(
                category: .aiTell,
                range: match.range,
                excerpt: source.substring(with: match.range),
                message: "This \"No X. No Y. Just Z.\" triad is a stock AI/marketing rhythm. Write the sentence out in full."
            )
        }
    }

    private static func hedgeStackIssues(in text: String) -> [WritingIssue] {
        let source = text as NSString
        var issues: [WritingIssue] = []
        for range in ReadabilityEngine.sentenceRanges(in: text) {
            let sentence = source.substring(with: range)
            let sentenceRange = NSRange(location: 0, length: (sentence as NSString).length)
            let hedgeCount = hedgeWordPattern.numberOfMatches(in: sentence, range: sentenceRange)
            guard hedgeCount >= 2 else { continue }
            issues.append(WritingIssue(
                category: .aiTell,
                range: range,
                excerpt: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                message: "This sentence stacks multiple hedge words (might, could, perhaps…). If you believe the claim, commit to it and cut the hedging."
            ))
        }
        return issues
    }

    /// "Just" used more than once in the same paragraph as a softener is the tell, not any single
    /// use — so this flags the second and later occurrences per paragraph, leaving the first alone.
    private static func fillerJustIssues(in text: String) -> [WritingIssue] {
        let source = text as NSString
        var issues: [WritingIssue] = []
        for paragraphRange in paragraphRanges(in: text) {
            let paragraph = source.substring(with: paragraphRange)
            let paragraphSource = paragraph as NSString
            let paragraphFullRange = NSRange(location: 0, length: paragraphSource.length)
            let exemptRanges = justExceptionPattern.matches(in: paragraph, range: paragraphFullRange).map(\.range)
            let matches = justPattern.matches(in: paragraph, range: paragraphFullRange).filter { match in
                !exemptRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
            }
            guard matches.count > 1 else { continue }
            for match in matches.dropFirst() {
                let absoluteRange = NSRange(
                    location: paragraphRange.location + match.range.location,
                    length: match.range.length
                )
                issues.append(WritingIssue(
                    category: .aiTell,
                    range: absoluteRange,
                    excerpt: paragraphSource.substring(with: match.range),
                    message: "\"Just\" already softened an earlier sentence in this paragraph. Cut this one unless it adds real meaning."
                ))
            }
        }
        return issues
    }

    /// "Actually" is a legitimate word for correcting a real misconception, so this only flags it
    /// once it shows up more often than a passage of this length would reasonably need — roughly
    /// once per 500 words, mirroring the same allowance the anti-AI style guide uses.
    private static func overusedActuallyIssues(in text: String) -> [WritingIssue] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = actuallyPattern.matches(in: text, range: fullRange)
        let wordCount = max(ReadabilityEngine.wordMatches(in: text).count, 1)
        let allowance = max(1, wordCount / 500)
        guard matches.count > allowance else { return [] }
        return matches.dropFirst(allowance).map { match in
            WritingIssue(
                category: .aiTell,
                range: match.range,
                excerpt: source.substring(with: match.range),
                message: "\"Actually\" is appearing more often than this passage's length justifies. Keep it only where you're correcting a real misconception."
            )
        }
    }

    private static func paragraphRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byParagraphs, .substringNotRequired]) {
            _, range, _, _ in
            ranges.append(NSRange(range, in: text))
        }
        return ranges
    }
}

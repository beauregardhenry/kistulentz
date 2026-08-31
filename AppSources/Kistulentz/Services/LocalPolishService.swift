import Foundation

struct LocalPolishResult: Equatable {
    let plan: PolishedDraftPlan?
    let appliedCount: Int
    let advisoryCount: Int
    let skippedCount: Int
}

enum LocalPolishService {
    static func polish(
        text: String,
        targetGrade: Int,
        issues suppliedIssues: [WritingIssue]? = nil
    ) -> LocalPolishResult {
        let issues = suppliedIssues ?? ReadabilityEngine.analyze(text, targetGrade: targetGrade).issues
        let source = text as NSString
        let protectedRanges = MarkdownProtectedRangeFinder.ranges(in: text)
        var safeConcreteIssues: [WritingIssue] = []
        var advisoryCount = 0
        var skippedCount = 0

        for issue in issues where issue.source != .ai {
            guard let replacement = issue.replacement, replacement != issue.excerpt else {
                advisoryCount += 1
                continue
            }
            guard issue.range.location != NSNotFound,
                  issue.range.location >= 0,
                  issue.range.length >= 0,
                  NSMaxRange(issue.range) <= source.length,
                  source.substring(with: issue.range) == issue.excerpt else {
                skippedCount += 1
                continue
            }
            guard !protectedRanges.contains(where: {
                NSIntersectionRange($0, issue.range).length > 0
            }) else {
                skippedCount += 1
                continue
            }
            guard SuggestionRuleValidator.introducedCategories(
                replacing: issue.range,
                in: text,
                with: replacement,
                targetGrade: targetGrade
            ).isEmpty else {
                skippedCount += 1
                continue
            }
            safeConcreteIssues.append(issue)
        }

        let application = SuggestionApplicationPlanner.plan(
            issues: safeConcreteIssues,
            in: text
        )
        skippedCount += application.conflictCount + application.staleCount
        guard application.hasChanges,
              SuggestionRuleValidator.isSafe(
                original: text,
                replacement: application.resultText,
                targetGrade: targetGrade
              ) else {
            return LocalPolishResult(
                plan: nil,
                appliedCount: 0,
                advisoryCount: advisoryCount,
                skippedCount: skippedCount + application.appliedCount
            )
        }

        let plan = PolishedDraftPlanner.plan(
            original: text,
            polished: application.resultText,
            targetGrade: targetGrade,
            origin: .local
        )
        return LocalPolishResult(
            plan: plan.changes.isEmpty ? nil : plan,
            appliedCount: application.appliedCount,
            advisoryCount: advisoryCount,
            skippedCount: skippedCount
        )
    }
}

private enum MarkdownProtectedRangeFinder {
    private static let patterns = [
        #"```[\s\S]*?```"#,
        #"~~~[\s\S]*?~~~"#,
        #"`[^`\n]*`"#,
        #"!?\[[^\]]*\]\([^\n)]*\)"#,
        #"<https?://[^>]+>"#,
        #"https?://[^\s)]+"#,
        #"<[^>\n]+>"#
    ]

    static func ranges(in text: String) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            return expression.matches(in: text, range: fullRange).map(\.range)
        }
    }
}

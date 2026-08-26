import Foundation

struct SuggestionApplicationPlan: Equatable {
    let resultText: String
    let appliedCount: Int
    let conflictCount: Int
    let staleCount: Int
    let advisoryCount: Int
    let duplicateCount: Int
    let appliedIssueIDs: [UUID]

    var hasChanges: Bool { appliedCount > 0 }
    var skippedCount: Int { conflictCount + staleCount + advisoryCount }
}

enum SuggestionApplicationPlanner {
    private struct Candidate {
        var issueIDs: [UUID]
        let range: NSRange
        let excerpt: String
        let replacement: String
    }

    static func plan(issues: [WritingIssue], in text: String) -> SuggestionApplicationPlan {
        let source = text as NSString
        var candidates: [Candidate] = []
        var staleCount = 0
        var advisoryCount = 0
        var duplicateCount = 0

        for issue in issues {
            guard let replacement = issue.replacement, replacement != issue.excerpt else {
                advisoryCount += 1
                continue
            }
            guard isValid(issue, in: source) else {
                staleCount += 1
                continue
            }

            if let duplicateIndex = candidates.firstIndex(where: {
                $0.range == issue.range
                    && $0.excerpt == issue.excerpt
                    && $0.replacement == replacement
            }) {
                candidates[duplicateIndex].issueIDs.append(issue.id)
                duplicateCount += 1
            } else {
                candidates.append(Candidate(
                    issueIDs: [issue.id],
                    range: issue.range,
                    excerpt: issue.excerpt,
                    replacement: replacement
                ))
            }
        }

        var conflicting = Set<Int>()
        if candidates.count > 1 {
            for leftIndex in 0..<(candidates.count - 1) {
                for rightIndex in (leftIndex + 1)..<candidates.count {
                    if NSIntersectionRange(candidates[leftIndex].range, candidates[rightIndex].range).length > 0 {
                        conflicting.insert(leftIndex)
                        conflicting.insert(rightIndex)
                    }
                }
            }
        }

        let applicable = candidates.enumerated()
            .filter { !conflicting.contains($0.offset) }
            .map(\.element)
            .sorted { $0.range.location > $1.range.location }

        var result = text
        for candidate in applicable {
            result = (result as NSString).replacingCharacters(in: candidate.range, with: candidate.replacement)
        }

        return SuggestionApplicationPlan(
            resultText: result,
            appliedCount: applicable.count,
            conflictCount: conflicting.count,
            staleCount: staleCount,
            advisoryCount: advisoryCount,
            duplicateCount: duplicateCount,
            appliedIssueIDs: applicable.flatMap(\.issueIDs)
        )
    }

    static func planSingle(issue: WritingIssue, in text: String) -> SuggestionApplicationPlan {
        let strictPlan = plan(issues: [issue], in: text)
        guard !strictPlan.hasChanges,
              strictPlan.staleCount == 1,
              let relocated = uniquelyRelocated(issue, in: text) else {
            return strictPlan
        }
        return plan(issues: [relocated], in: text)
    }

    private static func isValid(_ issue: WritingIssue, in text: NSString) -> Bool {
        issue.range.location != NSNotFound
            && issue.range.location >= 0
            && issue.range.length >= 0
            && NSMaxRange(issue.range) <= text.length
            && text.substring(with: issue.range) == issue.excerpt
    }

    private static func uniquelyRelocated(_ issue: WritingIssue, in text: String) -> WritingIssue? {
        guard !issue.excerpt.isEmpty else { return nil }
        let source = text as NSString
        let first = source.range(of: issue.excerpt)
        guard first.location != NSNotFound else { return nil }

        let nextLocation = NSMaxRange(first)
        if nextLocation < source.length {
            let remaining = NSRange(location: nextLocation, length: source.length - nextLocation)
            guard source.range(of: issue.excerpt, options: [], range: remaining).location == NSNotFound else {
                return nil
            }
        }

        return WritingIssue(
            id: issue.id,
            category: issue.category,
            range: first,
            excerpt: issue.excerpt,
            message: issue.message,
            replacement: issue.replacement,
            source: issue.source
        )
    }
}

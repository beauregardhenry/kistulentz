import Foundation

struct PolishedDraftChange: Identifiable, Equatable {
    let id: UUID
    let originalRange: NSRange
    let originalText: String
    let replacementText: String
    let introducedRuleCategories: [IssueCategory]

    init(
        id: UUID = UUID(),
        originalRange: NSRange,
        originalText: String,
        replacementText: String,
        introducedRuleCategories: [IssueCategory]
    ) {
        self.id = id
        self.originalRange = originalRange
        self.originalText = originalText
        self.replacementText = replacementText
        self.introducedRuleCategories = introducedRuleCategories
    }

    var isSafe: Bool { introducedRuleCategories.isEmpty }

    var safetyMessage: String? {
        guard !introducedRuleCategories.isEmpty else { return nil }
        let titles = introducedRuleCategories.map(\.title).joined(separator: ", ")
        return "This change introduces a new local flag: \(titles)."
    }
}

struct PolishedDraftPlan: Identifiable, Equatable {
    let id = UUID()
    let sourceText: String
    let polishedText: String
    let changes: [PolishedDraftChange]
    let introducedDocumentRuleCategories: [IssueCategory]

    var safeChanges: [PolishedDraftChange] { changes.filter(\.isSafe) }
    var unsafeChanges: [PolishedDraftChange] { changes.filter { !$0.isSafe } }
    var isFullReplacementSafe: Bool {
        unsafeChanges.isEmpty && introducedDocumentRuleCategories.isEmpty
    }

    func applying(changeIDs: Set<UUID>) -> String? {
        let selected = changes.filter { changeIDs.contains($0.id) }
        guard selected.allSatisfy(\.isSafe) else { return nil }

        let source = sourceText as NSString
        guard selected.allSatisfy({ change in
            change.originalRange.location != NSNotFound
                && NSMaxRange(change.originalRange) <= source.length
                && source.substring(with: change.originalRange) == change.originalText
        }) else { return nil }

        let result = NSMutableString(string: sourceText)
        for change in selected.sorted(by: { $0.originalRange.location > $1.originalRange.location }) {
            result.replaceCharacters(in: change.originalRange, with: change.replacementText)
        }
        return result as String
    }
}

enum SuggestionRuleValidator {
    static func introducedCategories(
        original: String,
        replacement: String,
        targetGrade: Int
    ) -> [IssueCategory] {
        let before = categoryCounts(in: original, targetGrade: targetGrade)
        let after = categoryCounts(in: replacement, targetGrade: targetGrade)

        return IssueCategory.allCases.filter { category in
            guard category.isLocallyValidated else { return false }
            return after[category, default: 0] > before[category, default: 0]
        }
    }

    static func isSafe(original: String, replacement: String, targetGrade: Int) -> Bool {
        introducedCategories(
            original: original,
            replacement: replacement,
            targetGrade: targetGrade
        ).isEmpty
    }

    static func introducedCategories(
        replacing range: NSRange,
        in text: String,
        with replacement: String,
        targetGrade: Int
    ) -> [IssueCategory] {
        let source = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= source.length else {
            return IssueCategory.allCases.filter(\.isLocallyValidated)
        }
        let contextRange = source.paragraphRange(for: range)
        let originalContext = source.substring(with: contextRange)
        let localRange = NSRange(
            location: range.location - contextRange.location,
            length: range.length
        )
        let replacementContext = (originalContext as NSString)
            .replacingCharacters(in: localRange, with: replacement)
        return introducedCategories(
            original: originalContext,
            replacement: replacementContext,
            targetGrade: targetGrade
        )
    }

    private static func categoryCounts(in text: String, targetGrade: Int) -> [IssueCategory: Int] {
        Dictionary(grouping: ReadabilityEngine.analyze(text, targetGrade: targetGrade).issues, by: \.category)
            .mapValues(\.count)
    }
}

enum PolishedDraftPlanner {
    private struct Line: Equatable {
        let text: String
        let utf16Length: Int
    }

    private enum DiffElement {
        case unchanged(Line)
        case removed(Line)
        case added(Line)
    }

    static func plan(
        original: String,
        polished: String,
        targetGrade: Int,
        detailedLineLimit: Int = 900
    ) -> PolishedDraftPlan {
        guard original != polished else {
            return PolishedDraftPlan(
                sourceText: original,
                polishedText: polished,
                changes: [],
                introducedDocumentRuleCategories: []
            )
        }

        let oldLines = lines(in: original)
        let newLines = lines(in: polished)
        let diff: [DiffElement]
        if oldLines.count <= detailedLineLimit, newLines.count <= detailedLineLimit {
            diff = longestCommonSubsequenceDiff(oldLines, newLines)
        } else {
            diff = boundedDiff(oldLines, newLines)
        }

        var changes: [PolishedDraftChange] = []
        var originalOffset = 0
        var hunkLocation: Int?
        var removed = ""
        var added = ""

        func finishHunk() {
            guard let hunkLocation else { return }
            let range = NSRange(location: hunkLocation, length: (removed as NSString).length)
            changes.append(PolishedDraftChange(
                originalRange: range,
                originalText: removed,
                replacementText: added,
                introducedRuleCategories: SuggestionRuleValidator.introducedCategories(
                    replacing: range,
                    in: original,
                    with: added,
                    targetGrade: targetGrade
                )
            ))
        }

        for element in diff {
            switch element {
            case .unchanged(let line):
                finishHunk()
                hunkLocation = nil
                removed = ""
                added = ""
                originalOffset += line.utf16Length
            case .removed(let line):
                if hunkLocation == nil { hunkLocation = originalOffset }
                removed += line.text
                originalOffset += line.utf16Length
            case .added(let line):
                if hunkLocation == nil { hunkLocation = originalOffset }
                added += line.text
            }
        }
        finishHunk()

        return PolishedDraftPlan(
            sourceText: original,
            polishedText: polished,
            changes: changes,
            introducedDocumentRuleCategories: SuggestionRuleValidator.introducedCategories(
                original: original,
                replacement: polished,
                targetGrade: targetGrade
            )
        )
    }

    private static func lines(in text: String) -> [Line] {
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        var result: [Line] = []
        var location = 0
        while location < source.length {
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            let value = source.substring(with: range)
            result.append(Line(text: value, utf16Length: range.length))
            location = NSMaxRange(range)
        }
        return result
    }

    private static func longestCommonSubsequenceDiff(_ old: [Line], _ new: [Line]) -> [DiffElement] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        if !old.isEmpty, !new.isEmpty {
            for oldIndex in stride(from: old.count - 1, through: 0, by: -1) {
                for newIndex in stride(from: new.count - 1, through: 0, by: -1) {
                    if old[oldIndex] == new[newIndex] {
                        lengths[oldIndex][newIndex] = lengths[oldIndex + 1][newIndex + 1] + 1
                    } else {
                        lengths[oldIndex][newIndex] = max(
                            lengths[oldIndex + 1][newIndex],
                            lengths[oldIndex][newIndex + 1]
                        )
                    }
                }
            }
        }

        var result: [DiffElement] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count,
               newIndex < new.count,
               old[oldIndex] == new[newIndex] {
                result.append(.unchanged(old[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if newIndex < new.count,
                      oldIndex == old.count || lengths[oldIndex][newIndex + 1] >= lengths[oldIndex + 1][newIndex] {
                result.append(.added(new[newIndex]))
                newIndex += 1
            } else if oldIndex < old.count {
                result.append(.removed(old[oldIndex]))
                oldIndex += 1
            }
        }
        return result
    }

    private static func boundedDiff(_ old: [Line], _ new: [Line]) -> [DiffElement] {
        var prefixCount = 0
        while prefixCount < old.count,
              prefixCount < new.count,
              old[prefixCount] == new[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < old.count - prefixCount,
              suffixCount < new.count - prefixCount,
              old[old.count - suffixCount - 1] == new[new.count - suffixCount - 1] {
            suffixCount += 1
        }

        var result = old.prefix(prefixCount).map(DiffElement.unchanged)
        result += old[prefixCount..<(old.count - suffixCount)].map(DiffElement.removed)
        result += new[prefixCount..<(new.count - suffixCount)].map(DiffElement.added)
        result += old.suffix(suffixCount).map(DiffElement.unchanged)
        return result
    }
}

private extension IssueCategory {
    var isLocallyValidated: Bool {
        switch self {
        case .hardSentence, .veryHardSentence, .adverb, .passiveVoice,
             .structuralComplexity, .complexPhrase, .spelling, .grammar:
            true
        case .aiSuggestion, .referenceVoice, .continuity:
            false
        }
    }
}

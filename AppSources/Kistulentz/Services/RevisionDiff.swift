import Foundation

enum RevisionDiffKind: Equatable {
    case unchanged
    case added
    case removed
}

struct RevisionDiffLine: Identifiable, Equatable {
    let id: Int
    let kind: RevisionDiffKind
    let text: String
}

enum RevisionDiff {
    static func compare(old: String, new: String, detailedLineLimit: Int = 600) -> [RevisionDiffLine] {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        let raw: [(RevisionDiffKind, String)]
        if oldLines.count <= detailedLineLimit && newLines.count <= detailedLineLimit {
            raw = longestCommonSubsequenceDiff(oldLines, newLines)
        } else {
            raw = boundedDiff(oldLines, newLines)
        }
        return raw.enumerated().map { RevisionDiffLine(id: $0.offset, kind: $0.element.0, text: $0.element.1) }
    }

    private static func longestCommonSubsequenceDiff(
        _ old: [String],
        _ new: [String]
    ) -> [(RevisionDiffKind, String)] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        if !old.isEmpty && !new.isEmpty {
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

        var result: [(RevisionDiffKind, String)] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count,
               newIndex < new.count,
               old[oldIndex] == new[newIndex] {
                result.append((.unchanged, old[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if newIndex < new.count,
                      (oldIndex == old.count || lengths[oldIndex][newIndex + 1] >= lengths[oldIndex + 1][newIndex]) {
                result.append((.added, new[newIndex]))
                newIndex += 1
            } else if oldIndex < old.count {
                result.append((.removed, old[oldIndex]))
                oldIndex += 1
            }
        }
        return result
    }

    private static func boundedDiff(
        _ old: [String],
        _ new: [String]
    ) -> [(RevisionDiffKind, String)] {
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

        var result = old.prefix(prefixCount).map { (RevisionDiffKind.unchanged, $0) }
        result += old[prefixCount..<(old.count - suffixCount)].map { (.removed, $0) }
        result += new[prefixCount..<(new.count - suffixCount)].map { (.added, $0) }
        result += old.suffix(suffixCount).map { (.unchanged, $0) }
        return result
    }
}

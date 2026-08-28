import Foundation

struct DismissedSuggestion: Codable, Hashable {
    let category: IssueCategory
    let source: IssueSource
    let excerpt: String
    let replacement: String?
    let prefix: String
    let suffix: String

    private static let contextLength = 32

    init?(issue: WritingIssue, in text: String) {
        let sourceText = text as NSString
        guard Self.isValid(issue.range, excerpt: issue.excerpt, in: sourceText) else { return nil }

        category = issue.category
        source = issue.source
        excerpt = issue.excerpt
        replacement = issue.replacement
        prefix = Self.prefix(for: issue.range, in: sourceText)
        suffix = Self.suffix(for: issue.range, in: sourceText)
    }

    func matches(_ issue: WritingIssue, in text: String) -> Bool {
        guard category == issue.category,
              source == issue.source,
              excerpt == issue.excerpt,
              replacement == issue.replacement else { return false }

        let sourceText = text as NSString
        guard Self.isValid(issue.range, excerpt: excerpt, in: sourceText) else { return false }
        return prefix == Self.prefix(for: issue.range, in: sourceText)
            && suffix == Self.suffix(for: issue.range, in: sourceText)
    }

    func passageStillExists(in text: String) -> Bool {
        guard !excerpt.isEmpty else { return false }
        let sourceText = text as NSString
        var searchRange = NSRange(location: 0, length: sourceText.length)

        while searchRange.length > 0 {
            let found = sourceText.range(of: excerpt, options: [], range: searchRange)
            guard found.location != NSNotFound else { return false }
            if prefix == Self.prefix(for: found, in: sourceText),
               suffix == Self.suffix(for: found, in: sourceText) {
                return true
            }

            let nextLocation = NSMaxRange(found)
            guard nextLocation < sourceText.length else { return false }
            searchRange = NSRange(location: nextLocation, length: sourceText.length - nextLocation)
        }
        return false
    }

    private static func isValid(_ range: NSRange, excerpt: String, in text: NSString) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && NSMaxRange(range) <= text.length
            && text.substring(with: range) == excerpt
    }

    private static func prefix(for range: NSRange, in text: NSString) -> String {
        let length = min(contextLength, range.location)
        return text.substring(with: NSRange(location: range.location - length, length: length))
    }

    private static func suffix(for range: NSRange, in text: NSString) -> String {
        let location = NSMaxRange(range)
        let length = min(contextLength, text.length - location)
        return text.substring(with: NSRange(location: location, length: length))
    }
}

final class DismissedSuggestionStore {
    private struct Archive: Codable {
        var documents: [String: [DismissedSuggestion]] = [:]
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.beauhenry.kistulentz.dismissedSuggestions.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func suggestions(for documentKey: String) -> [DismissedSuggestion] {
        archive().documents[documentKey] ?? []
    }

    func save(_ suggestions: [DismissedSuggestion], for documentKey: String) {
        var archive = archive()
        if suggestions.isEmpty {
            archive.documents.removeValue(forKey: documentKey)
        } else {
            archive.documents[documentKey] = suggestions
        }

        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func archive() -> Archive {
        guard let data = defaults.data(forKey: storageKey),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else {
            return Archive()
        }
        return archive
    }
}

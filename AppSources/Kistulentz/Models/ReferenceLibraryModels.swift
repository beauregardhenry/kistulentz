import Foundation

struct LibraryExcerpt: Identifiable, Codable, Hashable {
    let id: UUID
    var section: String
    var purpose: String
    var text: String

    init(id: UUID = UUID(), section: String, purpose: String, text: String) {
        self.id = id
        self.section = section
        self.purpose = purpose
        self.text = text
    }
}

struct LibraryBook: Identifiable, Codable {
    var id: UUID
    var sourcePath: String
    var sourceFileSize: Int64
    var sourceModifiedAt: Date?
    var title: String
    var author: String
    var genres: [String]
    var profile: ReferenceProfile
    var excerpts: [LibraryExcerpt]
    var importedAt: Date
    var updatedAt: Date

    var reference: EPUBReference {
        EPUBReference(
            id: id,
            fileName: URL(fileURLWithPath: sourcePath).lastPathComponent,
            title: title,
            author: author.nonEmpty,
            subjects: genres,
            chapters: excerpts.enumerated().map { index, excerpt in
                ReferenceChapter(
                    id: index,
                    title: "\(excerpt.section) — \(excerpt.purpose)",
                    text: excerpt.text
                )
            },
            profile: profile
        )
    }
}

struct LibraryAIInsight: Identifiable, Codable {
    var id: UUID
    var title: String
    var bookIDs: [UUID]
    var provider: String
    var model: String
    var markdown: String
    var createdAt: Date
}

struct ReferenceLibraryIndex: Codable {
    var schemaVersion = 1
    var books: [LibraryBook] = []
    var insights: [LibraryAIInsight] = []
}

enum LibraryReferenceKind: String, CaseIterable, Identifiable {
    case book
    case author
    case genre

    var id: String { rawValue }

    var title: String {
        switch self {
        case .book: "Books"
        case .author: "Authors"
        case .genre: "Genres"
        }
    }

    var systemImage: String {
        switch self {
        case .book: "book.closed"
        case .author: "person.2"
        case .genre: "tag"
        }
    }
}

struct LibraryReferenceChoice: Identifiable, Hashable {
    let id: String
    let kind: LibraryReferenceKind
    let title: String
    let subtitle: String
    let bookIDs: [UUID]
}

struct ReferenceDeepening: Codable {
    let summary: String
    let style: String
    let voice: String
    let tone: String
    let vocabulary: String
    let characterContinuity: String
    let tempo: String
    let techniques: [String]
    let suggestedGenres: [String]

    var markdown: String {
        var result = "## Editorial synthesis\n\n\(summary)\n\n"
        result += "### Style\n\n\(style)\n\n"
        result += "### Voice\n\n\(voice)\n\n"
        result += "### Tone\n\n\(tone)\n\n"
        result += "### Vocabulary\n\n\(vocabulary)\n\n"
        result += "### Characters and continuity\n\n\(characterContinuity)\n\n"
        result += "### Tempo\n\n\(tempo)\n\n"
        if !techniques.isEmpty {
            result += "### Techniques\n\n"
            result += techniques.map { "- \($0)" }.joined(separator: "\n")
            result += "\n\n"
        }
        if !suggestedGenres.isEmpty {
            result += "### Suggested genres\n\n"
            result += suggestedGenres.map { "- \($0)" }.joined(separator: "\n")
            result += "\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

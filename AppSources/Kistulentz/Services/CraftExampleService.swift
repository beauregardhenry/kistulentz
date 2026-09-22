import Foundation

/// Finds a short, attributed excerpt from the writer's own Reference Library that demonstrates
/// strong handling of a flagged issue's craft element ("show me how a reference author does
/// this" rather than only "here's what's wrong"). The AI selects an excerpt by id from a list of
/// excerpts Kistulentz already holds verbatim -- it never generates or reproduces quote text
/// itself, so a hallucinated or misattributed quote is structurally impossible: the text shown to
/// the writer always comes from `LibraryExcerpt.text`, never from the AI's own output. Only the
/// short "why it works" note is AI-authored prose.
struct CraftExampleService {
    struct Candidate: Equatable {
        let bookID: UUID
        let bookTitle: String
        let bookAuthor: String
        let excerpt: LibraryExcerpt
    }

    // `notFound`, not `none`: this type is stored as `Lookup?` at the call site (nil = not yet
    // asked this session), and `Lookup.none` would collide with `Optional<Lookup>.none` (nil)
    // under switch pattern matching -- `case .none` on an Optional<Lookup> is genuinely ambiguous
    // between the two once both exist.
    enum Lookup: Equatable {
        case found(bookID: UUID, bookTitle: String, bookAuthor: String, excerpt: LibraryExcerpt, whyItWorks: String)
        case notFound
    }

    private struct Selection: Decodable {
        let excerptID: String?
        let whyItWorks: String?

        private enum CodingKeys: String, CodingKey {
            case excerptID = "excerptId"
            case whyItWorks
        }
    }

    /// Spreads picks evenly across the flattened (book, excerpt) list -- the same idiom
    /// `ManuscriptStructuralSampler`/`ReferenceStructuralSampler` already use -- so a library with
    /// many books doesn't get crowded out by whichever books happen to sort first, then caps total
    /// characters so a large library can't blow the request budget. Each excerpt is already capped
    /// to ~900 characters at import time (`LibraryExcerptBuilder`), so the character cap is a
    /// backstop, not the primary limit.
    static func candidates(
        from books: [LibraryBook],
        maximumCount: Int = 20,
        maximumCharacters: Int = 14_000
    ) -> [Candidate] {
        let all = books.flatMap { book in
            book.excerpts.map {
                Candidate(bookID: book.id, bookTitle: book.title, bookAuthor: book.author, excerpt: $0)
            }
        }
        guard !all.isEmpty else { return [] }
        let limit = min(all.count, maximumCount)
        let sampled = all.count <= limit ? all : (0..<limit).map { all[$0 * all.count / limit] }
        var selected: [Candidate] = []
        var totalCharacters = 0
        for candidate in sampled {
            guard totalCharacters == 0 || totalCharacters + candidate.excerpt.text.count <= maximumCharacters else { break }
            selected.append(candidate)
            totalCharacters += candidate.excerpt.text.count
        }
        return selected
    }

    static func referenceContext(for candidates: [Candidate]) -> String {
        guard !candidates.isEmpty else { return "" }
        let blocks = candidates.map { candidate in
            """
            <excerpt id="\(candidate.excerpt.id.uuidString)" book="\(candidate.bookTitle)" author="\(candidate.bookAuthor)" purpose="\(candidate.excerpt.purpose)">
            \(candidate.excerpt.text)
            </excerpt>
            """
        }
        return "<candidate_excerpts>\n" + blocks.joined(separator: "\n\n") + "\n</candidate_excerpts>"
    }

    static func primaryText(for issue: WritingIssue) -> String {
        """
        <flagged_passage category="\(issue.category.title)">
        \(issue.excerpt)
        </flagged_passage>

        <task>
        Find the id of the one candidate excerpt, if any, that best demonstrates strong handling of "\(issue.category.title)" -- the craft element flagged above (\(issue.message)). If none clearly do, return null for both fields.
        </task>
        """
    }

    private static func resolve(_ selection: Selection, candidates: [Candidate]) -> Lookup {
        let trimmedID = selection.excerptID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedWhy = selection.whyItWorks?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedID.isEmpty,
              !trimmedWhy.isEmpty,
              let excerptID = UUID(uuidString: trimmedID),
              let match = candidates.first(where: { $0.excerpt.id == excerptID }) else {
            return .notFound
        }
        return .found(
            bookID: match.bookID,
            bookTitle: match.bookTitle,
            bookAuthor: match.bookAuthor,
            excerpt: match.excerpt,
            whyItWorks: trimmedWhy
        )
    }

    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    /// Takes the whole confirmed `AIRequestPreview` -- built from `primaryText(for:)` and
    /// `referenceContext(for:)` at preview time -- and sends exactly `request.instructions`/
    /// `request.input` rather than re-deriving them here, the same way `SelectionRewriteService
    /// .rewrite(request:apiKey:)` does. Re-deriving would risk the actual request silently
    /// diverging from what the preview showed the user.
    func find(request: AIRequestPreview, candidates: [Candidate], apiKey: String?) async throws -> Lookup {
        guard case .craftExample = request.purpose else { throw WritingAIError.invalidResponse }
        guard !candidates.isEmpty else { return .notFound }
        let raw = try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: "craft_example_selection",
            schema: Self.schema,
            maxTokens: 500
        )
        return Self.resolve(try Self.decode(raw), candidates: candidates)
    }

    private static func decode(_ rawText: String) throws -> Selection {
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(Selection.self, from: data) else {
            throw WritingAIError.invalidResponse
        }
        return result
    }

    private static var schema: [String: Any] { [
        "type": "object",
        "properties": [
            "excerptId": ["type": ["string", "null"]],
            "whyItWorks": ["type": ["string", "null"]]
        ],
        "required": ["excerptId", "whyItWorks"],
        "additionalProperties": false
    ] }
}

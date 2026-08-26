import AppKit
import Foundation

@MainActor
final class ReferenceLibraryStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var books: [LibraryBook] = []
    @Published private(set) var insights: [LibraryAIInsight] = []
    @Published private(set) var isImporting = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeepening = false
    @Published private(set) var importCompleted = 0
    @Published private(set) var importTotal = 0
    @Published private(set) var importFailures: [String] = []
    @Published private(set) var currentImportName = ""
    @Published var errorMessage: String?

    private static let locationKey = "referenceLibraryFolder"
    private let defaults: UserDefaults
    private var importTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var deepeningTask: Task<Void, Never>?
    private let deepeningService = ReferenceDeepeningService()
    private let persistence = ReferenceLibraryPersistence()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.locationKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            do {
                let index = try ReferenceLibraryDisk.load(from: url)
                rootURL = url
                books = index.books
                insights = index.insights
            } catch {
                errorMessage = "Kistulentz could not reopen the reference library: \(error.localizedDescription)"
            }
        }
    }

    var libraryName: String {
        rootURL?.lastPathComponent ?? "No library selected"
    }

    var authorsCount: Int {
        Set(books.map { normalized($0.author, fallback: "Unknown Author").lowercased() }).count
    }

    var genresCount: Int {
        Set(books.flatMap(\.genres).map { normalized($0, fallback: "Unclassified").lowercased() }).count
    }

    func setLocation(_ url: URL) {
        do {
            let index = try ReferenceLibraryDisk.load(from: url)
            rootURL = url
            books = index.books
            insights = index.insights
            defaults.set(url.path, forKey: Self.locationKey)
            errorMessage = nil
            persist(regenerateKnowledgeBase: true)
        } catch {
            errorMessage = "Kistulentz could not use that folder: \(error.localizedDescription)"
        }
    }

    func choices(kind: LibraryReferenceKind, search: String = "") -> [LibraryReferenceChoice] {
        let values: [LibraryReferenceChoice]
        switch kind {
        case .book:
            values = books.map { book in
                LibraryReferenceChoice(
                    id: "book:\(book.id.uuidString)",
                    kind: .book,
                    title: book.title,
                    subtitle: "\(book.author) · \(book.genres.joined(separator: ", "))",
                    bookIDs: [book.id]
                )
            }
        case .author:
            values = groupedChoices(kind: .author)
        case .genre:
            values = groupedChoices(kind: .genre)
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return values
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func book(id: UUID) -> LibraryBook? {
        books.first(where: { $0.id == id })
    }

    func updateBook(id: UUID, title: String, author: String, genres: [String]) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = normalized(title, fallback: books[index].title)
        let cleanAuthor = normalized(author, fallback: "Unknown Author")
        let cleanGenres = cleanedGenres(genres)
        books[index].title = cleanTitle
        books[index].author = cleanAuthor
        books[index].genres = cleanGenres
        books[index].updatedAt = Date()
        persist(regenerateKnowledgeBase: true)
    }

    func importEPUBs(from urls: [URL]) {
        guard rootURL != nil else {
            errorMessage = "Choose a Reference Library folder before importing EPUBs."
            return
        }
        importTask?.cancel()
        isImporting = true
        importCompleted = 0
        importTotal = 0
        importFailures = []
        currentImportName = "Finding EPUB files…"
        errorMessage = nil

        importTask = Task { [weak self] in
            guard let self else { return }
            let discovered = await Task.detached(priority: .userInitiated) {
                Self.discoverEPUBs(in: urls)
            }.value
            guard !Task.isCancelled else { return }
            self.importTotal = discovered.count

            if discovered.isEmpty {
                self.isImporting = false
                self.currentImportName = ""
                self.errorMessage = "No EPUB files were found in that selection."
                return
            }

            for url in discovered {
                guard !Task.isCancelled else { break }
                self.currentImportName = url.lastPathComponent
                let standardizedPath = url.standardizedFileURL.path
                let existing = self.books.first(where: { $0.sourcePath == standardizedPath })
                let attributes = try? FileManager.default.attributesOfItem(atPath: standardizedPath)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let modified = attributes?[.modificationDate] as? Date

                if let existing,
                   existing.sourceFileSize == size,
                   existing.sourceModifiedAt == modified {
                    self.importCompleted += 1
                    continue
                }

                let result = await Task.detached(priority: .userInitiated) {
                    Result { () -> LibraryBook in
                        let reference = try EPUBProcessor.load(url: url)
                        let now = Date()
                        return LibraryBook(
                            id: existing?.id ?? UUID(),
                            sourcePath: standardizedPath,
                            sourceFileSize: size,
                            sourceModifiedAt: modified,
                            title: reference.title,
                            author: reference.author?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown Author",
                            genres: LocalGenreClassifier.classify(reference: reference),
                            profile: reference.profile,
                            excerpts: LibraryExcerptBuilder.select(from: reference),
                            importedAt: existing?.importedAt ?? now,
                            updatedAt: now
                        )
                    }
                }.value

                guard !Task.isCancelled else { break }
                switch result {
                case .success(let book):
                    if let position = self.books.firstIndex(where: { $0.id == book.id }) {
                        self.books[position] = book
                    } else {
                        self.books.append(book)
                    }
                case .failure(let error):
                    self.importFailures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                self.importCompleted += 1

                if self.importCompleted.isMultiple(of: 25), let root = self.rootURL {
                    let snapshot = ReferenceLibraryIndex(books: self.books, insights: self.insights)
                    try? ReferenceLibraryDisk.saveIndex(snapshot, to: root)
                }
            }

            self.isImporting = false
            self.currentImportName = ""
            self.persist(regenerateKnowledgeBase: true)
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
        currentImportName = ""
        persist(regenerateKnowledgeBase: true)
    }

    func reference(for choiceIDs: Set<String>) -> EPUBReference? {
        let selectedChoices = LibraryReferenceKind.allCases.flatMap { choices(kind: $0) }
            .filter { choiceIDs.contains($0.id) }
        let selectedIDs = Set(selectedChoices.flatMap(\.bookIDs))
        let selectedBooks = books.filter { selectedIDs.contains($0.id) }
        guard !selectedBooks.isEmpty else { return nil }

        let profiles = selectedBooks.map(\.profile)
        let profile = ReferenceProfileCombiner.merge(profiles)
        let selectedTitles = selectedChoices.map(\.title)
        let title = selectedTitles.count == 1
            ? selectedTitles[0]
            : "\(selectedBooks.count) combined references"
        let authors = Set(selectedBooks.map(\.author))
        let author = authors.count == 1 ? authors.first : nil
        let genres = Array(Set(selectedBooks.flatMap(\.genres))).sorted()

        var chapters: [ReferenceChapter] = []
        for book in evenlySampled(selectedBooks, limit: 120) {
            for excerpt in book.excerpts.prefix(2) where chapters.count < 160 {
                chapters.append(ReferenceChapter(
                    id: chapters.count,
                    title: "\(book.title) — \(excerpt.section)",
                    text: excerpt.text
                ))
            }
        }

        let relevantInsights = insights
            .filter { Set($0.bookIDs).isSubset(of: selectedIDs) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
            .map { "# \($0.title)\n\($0.markdown)" }
            .joined(separator: "\n\n")

        return EPUBReference(
            fileName: "Kistulentz Reference Library",
            title: title,
            author: author,
            subjects: genres,
            chapters: chapters,
            profile: profile,
            learnedInsights: relevantInsights.isEmpty ? nil : relevantInsights,
            sourceCount: selectedBooks.count
        )
    }

    func deepen(choiceIDs: Set<String>, settings: AppSettings) {
        guard !isDeepening, let reference = reference(for: choiceIDs) else {
            errorMessage = "Select at least one book, author, or genre to deepen."
            return
        }
        let provider = settings.provider
        guard let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
            errorMessage = "Add your \(provider.title) API key in Settings before using Deepen with AI."
            return
        }
        let selectedChoices = LibraryReferenceKind.allCases.flatMap { choices(kind: $0) }
            .filter { choiceIDs.contains($0.id) }
        let bookIDs = Array(Set(selectedChoices.flatMap(\.bookIDs)))

        isDeepening = true
        errorMessage = nil
        deepeningTask?.cancel()
        deepeningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.deepeningService.deepen(
                    reference: reference,
                    provider: provider,
                    model: settings.model(for: provider),
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                let title = selectedChoices.count == 1
                    ? "AI insight: \(selectedChoices[0].title)"
                    : "AI insight: \(reference.title)"
                self.insights.append(LibraryAIInsight(
                    id: UUID(),
                    title: title,
                    bookIDs: bookIDs,
                    provider: provider.title,
                    model: settings.model(for: provider),
                    markdown: result.markdown,
                    createdAt: Date()
                ))
                self.isDeepening = false
                self.persist(regenerateKnowledgeBase: true)
            } catch is CancellationError {
                self.isDeepening = false
            } catch {
                self.isDeepening = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func openKnowledgeBase() {
        guard let rootURL else { return }
        NSWorkspace.shared.open(rootURL.appendingPathComponent("Kistulentz Library.md"))
    }

    private func groupedChoices(kind: LibraryReferenceKind) -> [LibraryReferenceChoice] {
        var groups: [String: (title: String, books: [LibraryBook])] = [:]
        for book in books {
            let values = kind == .author ? [book.author] : book.genres
            for rawValue in values {
                let title = normalized(rawValue, fallback: kind == .author ? "Unknown Author" : "Unclassified")
                let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
                if groups[key] == nil { groups[key] = (title, []) }
                groups[key]?.books.append(book)
            }
        }
        return groups.map { key, group in
            LibraryReferenceChoice(
                id: "\(kind.rawValue):\(key)",
                kind: kind,
                title: group.title,
                subtitle: "\(group.books.count) book\(group.books.count == 1 ? "" : "s")",
                bookIDs: group.books.map(\.id)
            )
        }
    }

    private func persist(regenerateKnowledgeBase: Bool) {
        guard let rootURL else { return }
        let snapshot = ReferenceLibraryIndex(books: books, insights: insights)
        isSaving = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await self?.persistence.save(
                    snapshot,
                    to: rootURL,
                    regenerateKnowledgeBase: regenerateKnowledgeBase
                )
                guard !Task.isCancelled else { return }
                self?.isSaving = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.isSaving = false
                self?.errorMessage = "The reference library could not be saved: \(error.localizedDescription)"
            }
        }
    }

    nonisolated private static func discoverEPUBs(in urls: [URL]) -> [URL] {
        var results: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, url.pathExtension.caseInsensitiveCompare("epub") == .orderedSame {
                results[url.standardizedFileURL.path] = url
                continue
            }
            guard values?.isDirectory == true,
                  let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }
            for case let candidate as URL in enumerator {
                let candidateValues = try? candidate.resourceValues(forKeys: Set(keys))
                if candidateValues?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if candidateValues?.isRegularFile == true,
                   candidate.pathExtension.caseInsensitiveCompare("epub") == .orderedSame {
                    results[candidate.standardizedFileURL.path] = candidate
                }
            }
        }
        return results.values.sorted { $0.path < $1.path }
    }

    private func cleanedGenres(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let cleaned = normalized(value, fallback: "")
            guard !cleaned.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) else { continue }
            result.append(cleaned)
        }
        return result.isEmpty ? ["Unclassified"] : result
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func evenlySampled<T>(_ values: [T], limit: Int) -> [T] {
        guard values.count > limit, limit > 0 else { return values }
        return (0..<limit).map { index in
            values[index * values.count / limit]
        }
    }
}

private actor ReferenceLibraryPersistence {
    func save(
        _ index: ReferenceLibraryIndex,
        to root: URL,
        regenerateKnowledgeBase: Bool
    ) throws {
        if regenerateKnowledgeBase {
            try ReferenceLibraryDisk.regenerateKnowledgeBase(index, at: root)
        } else {
            try ReferenceLibraryDisk.saveIndex(index, to: root)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

import Foundation

/// In-project text search. Extracted out of `WritingProjectStore`. Needs the
/// still-combined store to read the current chapter list/root and to flush
/// the live edit buffer before searching, exactly as before.
@MainActor
final class SearchStore: ObservableObject {

    typealias Searcher = (String, [ProjectChapter], URL) async throws -> [ProjectSearchResult]

    @Published var searchResults: [ProjectSearchResult] = []
    @Published var isSearching = false

    weak var core: WritingProjectStore?

    private var searchTask: Task<Void, Never>?
    private var activeSearchID: UUID?
    private let debounceDuration: Duration
    private let searcher: Searcher

    init(
        debounceDuration: Duration = .milliseconds(180),
        searcher: @escaping Searcher = SearchStore.searchDisk
    ) {
        self.debounceDuration = debounceDuration
        self.searcher = searcher
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        searchResults = []
        isSearching = false
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let core, let rootURL = core.rootURL else {
            searchTask = nil
            activeSearchID = nil
            searchResults = []
            isSearching = false
            return
        }
        core.saveNow()
        let chapterSnapshot = core.chapters
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: debounceDuration)
                try Task.checkCancellation()
                let results = try await searcher(trimmed, chapterSnapshot, rootURL)
                try Task.checkCancellation()
                guard activeSearchID == searchID else { return }
                searchResults = results
                finish(searchID)
            } catch is CancellationError {
                self?.finish(searchID)
            } catch {
                guard let self, activeSearchID == searchID else { return }
                searchResults = []
                core.errorMessage = error.localizedDescription
                finish(searchID)
            }
        }
    }

    private func finish(_ searchID: UUID) {
        guard activeSearchID == searchID else { return }
        activeSearchID = nil
        searchTask = nil
        isSearching = false
    }

    private nonisolated static func searchDisk(
        _ query: String,
        _ chapters: [ProjectChapter],
        _ rootURL: URL
    ) async throws -> [ProjectSearchResult] {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let results = try WritingProjectDisk.search(query, chapters: chapters, at: rootURL)
            try Task.checkCancellation()
            return results
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

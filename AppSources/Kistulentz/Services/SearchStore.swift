import Foundation

/// In-project text search. Extracted out of `WritingProjectStore`. Needs the
/// still-combined store to read the current chapter list/root and to flush
/// the live edit buffer before searching, exactly as before.
@MainActor
final class SearchStore: ObservableObject {

    @Published var searchResults: [ProjectSearchResult] = []
    @Published var isSearching = false

    weak var core: WritingProjectStore?

    private var searchTask: Task<Void, Never>?

    /// Matches `WritingProjectStore.closeProject()`'s original behavior exactly:
    /// only `searchResults` is reset here, `isSearching` is left untouched.
    /// A pre-existing asymmetry, preserved rather than "fixed" in this pass.
    func reset() {
        searchTask?.cancel()
        searchResults = []
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let core, let rootURL = core.rootURL else {
            searchResults = []
            isSearching = false
            return
        }
        core.saveNow()
        let chapterSnapshot = core.chapters
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    try WritingProjectDisk.search(trimmed, chapters: chapterSnapshot, at: rootURL)
                }.value
                guard !Task.isCancelled else { return }
                self?.searchResults = results
                self?.isSearching = false
            } catch {
                self?.searchResults = []
                self?.isSearching = false
                self?.core?.errorMessage = error.localizedDescription
            }
        }
    }
}

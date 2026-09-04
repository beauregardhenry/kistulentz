import Foundation

extension WritingProjectStore {

    // MARK: - Search

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rootURL else {
            searchResults = []
            isSearching = false
            return
        }
        saveNow()
        let chapterSnapshot = chapters
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
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}

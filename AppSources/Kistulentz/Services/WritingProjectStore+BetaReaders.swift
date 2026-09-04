import Foundation

extension WritingProjectStore {

    // MARK: - Beta Readers

    func addCustomBetaReader(name: String, focus: String, audience: BetaReaderAudience) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanFocus.isEmpty else { return }
        customBetaReaders.append(BetaReaderProfile(name: cleanName, focus: cleanFocus, audience: audience))
        saveCustomBetaReaders()
    }

    func updateCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn,
              let index = customBetaReaders.firstIndex(where: { $0.id == reader.id }) else { return }
        customBetaReaders[index] = reader
        saveCustomBetaReaders()
    }

    func removeCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn else { return }
        customBetaReaders.removeAll { $0.id == reader.id }
        saveCustomBetaReaders()
    }

    func documents(for scope: BetaReaderScope, selection: String?) throws -> [ManuscriptDocument] {
        switch scope {
        case .selection:
            guard let selection,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingAIError.emptySelection
            }
            return [ManuscriptDocument(relativePath: selectedChapterPath ?? "Selection", title: "Selection", text: selection)]
        case .chapter:
            return [ManuscriptDocument(
                relativePath: selectedChapterPath ?? "Chapter",
                title: selectedChapterTitle,
                text: text
            )]
        case .manuscript:
            return try manuscriptDocuments()
        }
    }

    private func saveCustomBetaReaders() {
        guard let rootURL else { return }
        do {
            try ManuscriptProjectDisk.saveCustomBetaReaders(customBetaReaders, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

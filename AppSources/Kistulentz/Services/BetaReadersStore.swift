import Foundation

/// User-defined beta reader personas for the open project. Extracted out of
/// `WritingProjectStore`. Needs the still-combined store for chapter/manuscript
/// content when assembling documents for a beta reader packet.
@MainActor
final class BetaReadersStore: ObservableObject {

    @Published var customBetaReaders: [BetaReaderProfile] = []

    weak var core: WritingProjectStore?

    func load(at root: URL) throws {
        customBetaReaders = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)
    }

    func reset() {
        customBetaReaders = []
    }

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
            return [ManuscriptDocument(relativePath: core?.selectedChapterPath ?? "Selection", title: "Selection", text: selection)]
        case .chapter:
            return [ManuscriptDocument(
                relativePath: core?.selectedChapterPath ?? "Chapter",
                title: core?.selectedChapterTitle ?? "Chapter",
                text: core?.text ?? ""
            )]
        case .manuscript:
            return try core?.manuscriptDocuments() ?? []
        }
    }

    private func saveCustomBetaReaders() {
        guard let rootURL = core?.rootURL else { return }
        do {
            try ManuscriptProjectDisk.saveCustomBetaReaders(customBetaReaders, at: rootURL)
        } catch {
            core?.errorMessage = error.localizedDescription
        }
    }
}

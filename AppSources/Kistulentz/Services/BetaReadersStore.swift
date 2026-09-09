import Foundation

/// User-defined beta reader personas for the open project. Extracted out of
/// `WritingProjectStore`. Needs the still-combined store for chapter/manuscript
/// content when assembling documents for a beta reader packet.
@MainActor
final class BetaReadersStore: ObservableObject {

    typealias CurrentChapter = () -> (path: String?, title: String, text: String)?
    typealias ManuscriptProvider = () throws -> [ManuscriptDocument]
    typealias ReadersSaver = ([BetaReaderProfile], URL) throws -> Void

    @Published var customBetaReaders: [BetaReaderProfile] = []

    private let projectRoot: () -> URL?
    private let currentChapter: CurrentChapter
    private let manuscriptProvider: ManuscriptProvider
    private let reportError: (Error) -> Void
    private let saveReaders: ReadersSaver

    init(
        projectRoot: @escaping () -> URL?,
        currentChapter: @escaping CurrentChapter,
        manuscriptProvider: @escaping ManuscriptProvider,
        reportError: @escaping (Error) -> Void,
        saveReaders: @escaping ReadersSaver = ManuscriptProjectDisk.saveCustomBetaReaders
    ) {
        self.projectRoot = projectRoot
        self.currentChapter = currentChapter
        self.manuscriptProvider = manuscriptProvider
        self.reportError = reportError
        self.saveReaders = saveReaders
    }

    func load(at root: URL) throws {
        customBetaReaders = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)
    }

    func replaceContents(_ readers: [BetaReaderProfile]) {
        customBetaReaders = readers
    }

    func reset() {
        customBetaReaders = []
    }

    func addCustomBetaReader(name: String, focus: String, audience: BetaReaderAudience) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanFocus.isEmpty else { return }
        var updated = customBetaReaders
        updated.append(BetaReaderProfile(name: cleanName, focus: cleanFocus, audience: audience))
        persist(updated)
    }

    func updateCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn,
              let index = customBetaReaders.firstIndex(where: { $0.id == reader.id }) else { return }
        var updated = customBetaReaders
        updated[index] = reader
        persist(updated)
    }

    func removeCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn else { return }
        var updated = customBetaReaders
        updated.removeAll { $0.id == reader.id }
        persist(updated)
    }

    func documents(for scope: BetaReaderScope, selection: String?) throws -> [ManuscriptDocument] {
        switch scope {
        case .selection:
            guard let selection,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingAIError.emptySelection
            }
            return [ManuscriptDocument(
                relativePath: currentChapter()?.path ?? "Selection",
                title: "Selection",
                text: selection
            )]
        case .chapter:
            let chapter = currentChapter()
            return [ManuscriptDocument(
                relativePath: chapter?.path ?? "Chapter",
                title: chapter?.title ?? "Chapter",
                text: chapter?.text ?? ""
            )]
        case .manuscript:
            return try manuscriptProvider()
        }
    }

    private func persist(_ updated: [BetaReaderProfile]) {
        guard updated != customBetaReaders, let rootURL = projectRoot() else { return }
        do {
            try saveReaders(updated, rootURL)
            customBetaReaders = updated
        } catch {
            reportError(error)
        }
    }
}

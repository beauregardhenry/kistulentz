import AppKit
import Foundation

/// Research sources, quotations, claim links, and free-form research notes for
/// the open project. Extracted out of `WritingProjectStore` because this
/// concern touches nothing else in the app beyond the project root -- it was
/// verified to have zero coupling with any other store's behavior.
@MainActor
final class ProjectResearchStore: ObservableObject {

    typealias BibliographySaver = (ProjectBibliographyArchive, URL) throws -> Void
    typealias NotesSaver = (String, URL) throws -> Void

    @Published var projectBibliography = ProjectBibliographyArchive()
    @Published var researchNotesText = ""

    private let projectRoot: () -> URL?
    private let reportError: (Error) -> Void
    private let saveBibliography: BibliographySaver
    private let saveNotes: NotesSaver

    init(
        projectRoot: @escaping () -> URL?,
        reportError: @escaping (Error) -> Void,
        saveBibliography: @escaping BibliographySaver = ProjectResearchDisk.save,
        saveNotes: @escaping NotesSaver = { text, root in
            try text.write(
                to: ProjectResearchDisk.notesURL(at: root),
                atomically: true,
                encoding: .utf8
            )
        }
    ) {
        self.projectRoot = projectRoot
        self.reportError = reportError
        self.saveBibliography = saveBibliography
        self.saveNotes = saveNotes
    }

    func load(at root: URL) throws {
        projectBibliography = try ProjectResearchDisk.load(at: root)
        researchNotesText = try String(contentsOf: ProjectResearchDisk.notesURL(at: root), encoding: .utf8)
    }

    func replaceContents(
        bibliography: ProjectBibliographyArchive,
        notesText: String
    ) {
        projectBibliography = bibliography
        researchNotesText = notesText
    }

    func reset() {
        projectBibliography = ProjectBibliographyArchive()
        researchNotesText = ""
    }

    func addResearchSource(_ sourceID: UUID) {
        guard !projectBibliography.sourceIDs.contains(sourceID) else { return }
        var updated = projectBibliography
        updated.sourceIDs.append(sourceID)
        persist(updated)
    }

    func removeResearchSource(_ sourceID: UUID) {
        var updated = projectBibliography
        updated.sourceIDs.removeAll { $0 == sourceID }
        updated.quotations.removeAll { $0.sourceID == sourceID }
        updated.claimLinks.removeAll { $0.sourceID == sourceID }
        persist(updated)
    }

    func setBibliographyStyle(_ style: BibliographyStyle) {
        var updated = projectBibliography
        updated.style = style
        persist(updated)
    }

    func addQuotation(sourceID: UUID, text: String, locator: String, note: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var updated = projectBibliography
        updated.quotations.append(ProjectResearchQuotation(
            sourceID: sourceID,
            text: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        persist(updated)
    }

    func removeQuotation(_ id: UUID) {
        var updated = projectBibliography
        updated.quotations.removeAll { $0.id == id }
        persist(updated)
    }

    func addClaimLink(sourceID: UUID, chapterPath: String, excerpt: String, locator: String, note: String) {
        let clean = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var updated = projectBibliography
        updated.claimLinks.append(ProjectClaimSourceLink(
            sourceID: sourceID,
            chapterPath: chapterPath,
            claimExcerpt: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        persist(updated)
    }

    func removeClaimLink(_ id: UUID) {
        var updated = projectBibliography
        updated.claimLinks.removeAll { $0.id == id }
        persist(updated)
    }

    func updateResearchNotes(_ value: String) {
        guard let rootURL = projectRoot(), value != researchNotesText else { return }
        do {
            try saveNotes(value, rootURL)
            researchNotesText = value
        } catch {
            reportError(error)
        }
    }

    func revealResearchNotes() {
        guard let rootURL = projectRoot() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ProjectResearchDisk.notesURL(at: rootURL)])
    }

    func projectSources(in library: ResearchLibraryStore) -> [ResearchSource] {
        let ids = Set(projectBibliography.sourceIDs)
        return library.sources.filter { ids.contains($0.id) }
    }

    private func persist(_ updated: ProjectBibliographyArchive) {
        guard updated != projectBibliography, let rootURL = projectRoot() else { return }
        do {
            try saveBibliography(updated, rootURL)
            projectBibliography = updated
        } catch {
            reportError(error)
        }
    }
}

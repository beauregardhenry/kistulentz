import AppKit
import Foundation

extension WritingProjectStore {

    // MARK: - Research & Bibliography

    func addResearchSource(_ sourceID: UUID) {
        guard !projectBibliography.sourceIDs.contains(sourceID) else { return }
        projectBibliography.sourceIDs.append(sourceID)
        saveProjectBibliography()
    }

    func removeResearchSource(_ sourceID: UUID) {
        projectBibliography.sourceIDs.removeAll { $0 == sourceID }
        projectBibliography.quotations.removeAll { $0.sourceID == sourceID }
        projectBibliography.claimLinks.removeAll { $0.sourceID == sourceID }
        saveProjectBibliography()
    }

    func setBibliographyStyle(_ style: BibliographyStyle) {
        projectBibliography.style = style
        saveProjectBibliography()
    }

    func addQuotation(sourceID: UUID, text: String, locator: String, note: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectBibliography.quotations.append(ProjectResearchQuotation(
            sourceID: sourceID,
            text: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        saveProjectBibliography()
    }

    func removeQuotation(_ id: UUID) {
        projectBibliography.quotations.removeAll { $0.id == id }
        saveProjectBibliography()
    }

    func addClaimLink(sourceID: UUID, chapterPath: String, excerpt: String, locator: String, note: String) {
        let clean = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectBibliography.claimLinks.append(ProjectClaimSourceLink(
            sourceID: sourceID,
            chapterPath: chapterPath,
            claimExcerpt: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        saveProjectBibliography()
    }

    func removeClaimLink(_ id: UUID) {
        projectBibliography.claimLinks.removeAll { $0.id == id }
        saveProjectBibliography()
    }

    func updateResearchNotes(_ value: String) {
        guard let rootURL, value != researchNotesText else { return }
        researchNotesText = value
        do {
            try value.write(to: ProjectResearchDisk.notesURL(at: rootURL), atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealResearchNotes() {
        guard let rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ProjectResearchDisk.notesURL(at: rootURL)])
    }

    func projectSources(in library: ResearchLibraryStore) -> [ResearchSource] {
        let ids = Set(projectBibliography.sourceIDs)
        return library.sources.filter { ids.contains($0.id) }
    }

    private func saveProjectBibliography() {
        guard let rootURL else { return }
        do {
            try ProjectResearchDisk.save(projectBibliography, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

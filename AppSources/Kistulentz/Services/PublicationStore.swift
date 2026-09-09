import Foundation

/// Export profiles, metadata, and publication history for the open project.
/// Extracted out of `WritingProjectStore`. Needs the still-combined store for
/// project identity/outline/save orchestration, and the research store for
/// the bibliography it embeds in an export plan.
@MainActor
final class PublicationStore: ObservableObject {

    @Published var publicationArchive = PublicationArchive()

    private let projectRoot: () -> URL?
    private let projectManifest: () -> WritingProjectManifest?
    private let projectOutline: () -> [OutlineNode]
    private let bibliography: () -> ProjectBibliographyArchive
    private let saveCurrentDocument: () -> Void
    private let saveProjectOutline: () -> Void
    private let reportError: (Error) -> Void

    init(
        projectRoot: @escaping () -> URL?,
        projectManifest: @escaping () -> WritingProjectManifest?,
        projectOutline: @escaping () -> [OutlineNode],
        bibliography: @escaping () -> ProjectBibliographyArchive,
        saveCurrentDocument: @escaping () -> Void,
        saveProjectOutline: @escaping () -> Void,
        reportError: @escaping (Error) -> Void
    ) {
        self.projectRoot = projectRoot
        self.projectManifest = projectManifest
        self.projectOutline = projectOutline
        self.bibliography = bibliography
        self.saveCurrentDocument = saveCurrentDocument
        self.saveProjectOutline = saveProjectOutline
        self.reportError = reportError
    }

    func load(at root: URL) throws {
        publicationArchive = try PublicationDisk.load(at: root)
    }

    func replaceContents(_ archive: PublicationArchive) {
        publicationArchive = archive
    }

    func reset() {
        publicationArchive = PublicationArchive()
    }

    func updatePublicationArchive(_ archive: PublicationArchive) {
        guard let rootURL = projectRoot() else { return }
        do {
            try PublicationDisk.save(archive, at: rootURL)
            publicationArchive = archive
        } catch {
            reportError(error)
        }
    }

    func publicationPlan(
        sources: [ResearchSource],
        profileID: UUID? = nil,
        format: PublicationExportFormat? = nil
    ) throws -> PublicationExportPlan {
        guard let rootURL = projectRoot(), let manifest = projectManifest() else {
            throw PublicationExportError.missingProject
        }
        saveCurrentDocument()
        saveProjectOutline()
        let selectedID = profileID ?? publicationArchive.selectedProfileID
        guard let profile = publicationArchive.profiles.first(where: { $0.id == selectedID }) else {
            throw PublicationExportError.missingProfile
        }
        return PublicationPlanBuilder.build(
            projectName: manifest.name,
            root: rootURL,
            outline: projectOutline(),
            archive: publicationArchive,
            bibliography: bibliography(),
            librarySources: sources,
            profile: profile,
            format: format ?? profile.preferredFormat,
            destinations: publicationArchive.selectedDestinations
        )
    }

    func copyPublicationCover(from url: URL) {
        guard let rootURL = projectRoot() else { return }
        do {
            var archive = publicationArchive
            archive.metadata.coverImageRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            reportError(error)
        }
    }

    func copyPrintCover(from url: URL) {
        guard let rootURL = projectRoot() else { return }
        do {
            var archive = publicationArchive
            archive.metadata.printCoverPDFRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "print-cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            reportError(error)
        }
    }

    func recordPublicationExport(_ result: PublicationExportResult, plan: PublicationExportPlan) {
        var archive = publicationArchive
        archive.history.insert(ExportHistoryRecord(
            profileID: plan.profile.id,
            profileName: plan.profile.name,
            format: plan.format,
            outputPath: (result.packageURL ?? result.outputURL).path,
            sha256: result.sha256,
            byteCount: result.byteCount,
            warningCount: result.preflight.warnings.count
        ), at: 0)
        updatePublicationArchive(archive)
    }
}

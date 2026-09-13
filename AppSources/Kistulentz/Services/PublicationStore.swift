import Foundation

struct PublicationPersistence {
    var load: (URL) throws -> PublicationArchive
    var save: (PublicationArchive, URL) throws -> Void
    var copyAsset: (URL, String, URL) throws -> String

    static var live: PublicationPersistence { PublicationPersistence(
        load: PublicationDisk.load,
        save: { try PublicationDisk.save($0, at: $1) },
        copyAsset: { try PublicationDisk.copyPublicationAsset(from: $0, preferredName: $1, at: $2) }
    ) }
}

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
    private let persistence: PublicationPersistence

    /// Late-bound, not a constructor parameter: `PublicationStore` is created before the
    /// app-wide `CustomFontStore` environment object is available (see `EditorWorkspace`'s
    /// `onAppear`), so these default to no-ops and are wired up once the environment is ready.
    /// Nothing else about project-font bundling depends on this timing -- until it's configured,
    /// saving a publication archive just doesn't bundle anything yet.
    var availableCustomFonts: () -> [CustomFontRecord] = { [] }
    var customFontFileURL: (CustomFontRecord) -> URL = { record in URL(fileURLWithPath: record.storedFilename) }

    init(
        projectRoot: @escaping () -> URL?,
        projectManifest: @escaping () -> WritingProjectManifest?,
        projectOutline: @escaping () -> [OutlineNode],
        bibliography: @escaping () -> ProjectBibliographyArchive,
        saveCurrentDocument: @escaping () -> Void,
        saveProjectOutline: @escaping () -> Void,
        reportError: @escaping (Error) -> Void,
        persistence: PublicationPersistence = .live
    ) {
        self.projectRoot = projectRoot
        self.projectManifest = projectManifest
        self.projectOutline = projectOutline
        self.bibliography = bibliography
        self.saveCurrentDocument = saveCurrentDocument
        self.saveProjectOutline = saveProjectOutline
        self.reportError = reportError
        self.persistence = persistence
    }

    func load(at root: URL) throws {
        publicationArchive = try persistence.load(root)
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
            try persistence.save(archive, rootURL)
            publicationArchive = archive
            ProjectFontDisk.bundleReferencedFonts(
                in: archive,
                at: rootURL,
                availableCustomFonts: availableCustomFonts(),
                fileURL: customFontFileURL
            )
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
            archive.metadata.coverImageRelativePath = try persistence.copyAsset(url, "cover", rootURL)
            updatePublicationArchive(archive)
        } catch {
            reportError(error)
        }
    }

    func copyPrintCover(from url: URL) {
        guard let rootURL = projectRoot() else { return }
        do {
            var archive = publicationArchive
            archive.metadata.printCoverPDFRelativePath = try persistence.copyAsset(url, "print-cover", rootURL)
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

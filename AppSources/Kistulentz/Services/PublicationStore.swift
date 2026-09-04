import Foundation

/// Export profiles, metadata, and publication history for the open project.
/// Extracted out of `WritingProjectStore`. Needs the still-combined store for
/// project identity/outline/save orchestration, and the research store for
/// the bibliography it embeds in an export plan.
@MainActor
final class PublicationStore: ObservableObject {

    @Published var publicationArchive = PublicationArchive()

    weak var core: WritingProjectStore?
    weak var research: ProjectResearchStore?

    func load(at root: URL) throws {
        publicationArchive = try PublicationDisk.load(at: root)
    }

    func reset() {
        publicationArchive = PublicationArchive()
    }

    func updatePublicationArchive(_ archive: PublicationArchive) {
        guard let rootURL = core?.rootURL else { return }
        do {
            try PublicationDisk.save(archive, at: rootURL)
            publicationArchive = archive
        } catch {
            core?.errorMessage = error.localizedDescription
        }
    }

    func publicationPlan(
        sources: [ResearchSource],
        profileID: UUID? = nil,
        format: PublicationExportFormat? = nil
    ) throws -> PublicationExportPlan {
        guard let core, let rootURL = core.rootURL, let manifest = core.manifest else {
            throw PublicationExportError.missingProject
        }
        core.saveNow()
        core.saveOutlineNow()
        let selectedID = profileID ?? publicationArchive.selectedProfileID
        guard let profile = publicationArchive.profiles.first(where: { $0.id == selectedID }) else {
            throw PublicationExportError.missingProfile
        }
        return PublicationPlanBuilder.build(
            projectName: manifest.name,
            root: rootURL,
            outline: core.outlineNodes,
            archive: publicationArchive,
            bibliography: research?.projectBibliography ?? ProjectBibliographyArchive(),
            librarySources: sources,
            profile: profile,
            format: format ?? profile.preferredFormat,
            destinations: publicationArchive.selectedDestinations
        )
    }

    func copyPublicationCover(from url: URL) {
        guard let rootURL = core?.rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.coverImageRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            core?.errorMessage = error.localizedDescription
        }
    }

    func copyPrintCover(from url: URL) {
        guard let rootURL = core?.rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.printCoverPDFRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "print-cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            core?.errorMessage = error.localizedDescription
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

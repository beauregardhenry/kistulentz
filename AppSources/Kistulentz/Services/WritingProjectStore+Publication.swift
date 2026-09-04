import Foundation

extension WritingProjectStore {

    // MARK: - Publication

    func updatePublicationArchive(_ archive: PublicationArchive) {
        guard let rootURL else { return }
        do {
            try PublicationDisk.save(archive, at: rootURL)
            publicationArchive = archive
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publicationPlan(
        sources: [ResearchSource],
        profileID: UUID? = nil,
        format: PublicationExportFormat? = nil
    ) throws -> PublicationExportPlan {
        guard let rootURL, let manifest else { throw PublicationExportError.missingProject }
        saveNow()
        saveOutlineNow()
        let selectedID = profileID ?? publicationArchive.selectedProfileID
        guard let profile = publicationArchive.profiles.first(where: { $0.id == selectedID }) else {
            throw PublicationExportError.missingProfile
        }
        return PublicationPlanBuilder.build(
            projectName: manifest.name,
            root: rootURL,
            outline: outlineNodes,
            archive: publicationArchive,
            bibliography: projectBibliography,
            librarySources: sources,
            profile: profile,
            format: format ?? profile.preferredFormat,
            destinations: publicationArchive.selectedDestinations
        )
    }

    func copyPublicationCover(from url: URL) {
        guard let rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.coverImageRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPrintCover(from url: URL) {
        guard let rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.printCoverPDFRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "print-cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            errorMessage = error.localizedDescription
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

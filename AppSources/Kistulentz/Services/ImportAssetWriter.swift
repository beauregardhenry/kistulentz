import Foundation

/// Builds unique, filesystem-safe destinations for a batch of imported assets inside one folder,
/// then creates the folder and writes them atomically. Shared by
/// `ProjectImportOutputService.writeCombinedMarkdown` (several documents combined into one file)
/// and its `writeProjectDocuments` (several documents kept as separate chapters) -- the two places
/// that used to hand-duplicate this exact sequence.
///
/// `DocumentImportService.save` (a single document) still writes its own assets directly rather
/// than through this: its filename-to-embed-reference resolution
/// (`DocumentImportDraft.renderedMarkdown`) recomputes each asset's on-disk name independently from
/// `assetFolderName` rather than consulting an explicit per-asset reference map the way
/// `ProjectImportConversion.renderedMarkdown(assetReferences:)` already does. Uniquifying names
/// here without also changing that model's contract would let a collision give a file a different
/// on-disk name than the Markdown it renders points to -- a real behavior change, not just a
/// dedup, so it's left as a separate, disclosed follow-up rather than folded in silently.
enum ImportAssetWriter {
    struct PlannedAsset {
        let asset: DocumentImportAsset
        let destination: URL
    }

    struct Plan {
        /// Each asset's ID mapped to "folderName/fileName", for embedding in rendered Markdown.
        let references: [UUID: String]
        let files: [PlannedAsset]
        var isEmpty: Bool { files.isEmpty }
    }

    /// Assigns each asset a unique, sanitized filename inside `folder` -- doesn't touch disk.
    /// `proposedName` need not already be sanitized or unique; both are handled here.
    static func plan(
        _ assets: [(id: UUID, proposedName: String, asset: DocumentImportAsset)],
        in folder: URL
    ) -> Plan {
        var references: [UUID: String] = [:]
        var files: [PlannedAsset] = []
        var reserved: Set<String> = []
        for (id, proposedName, asset) in assets {
            let name = uniqueFilename(proposedName, reserved: &reserved)
            references[id] = folder.lastPathComponent + "/" + name
            files.append(PlannedAsset(asset: asset, destination: folder.appendingPathComponent(name)))
        }
        return Plan(references: references, files: files)
    }

    /// Creates `folder` and writes every planned file into it, atomically. A no-op when the plan
    /// is empty -- nothing is created. Returns the URLs it created, folder first then each file in
    /// write order, so a caller can undo them if a later step in the same import fails.
    @discardableResult
    static func write(_ plan: Plan, to folder: URL) throws -> [URL] {
        guard !plan.isEmpty else { return [] }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var created = [folder]
        for file in plan.files {
            try AtomicFileWriter.write(data: file.asset.data, to: file.destination)
            created.append(file.destination)
        }
        return created
    }

    private static func uniqueFilename(_ proposed: String, reserved: inout Set<String>) -> String {
        let safe = DocumentImportFilename.safe(proposed)
        let url = URL(fileURLWithPath: safe)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = safe
        var suffix = 2
        while reserved.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            suffix += 1
        }
        reserved.insert(candidate.lowercased())
        return candidate
    }
}

import Foundation

enum ProjectImportSourceDiscovery {
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]

    static func discover(from selections: [URL]) throws -> ProjectImportDiscoveryResult {
        var found: [URL] = []
        var skipped: [String] = []

        for selection in selections {
            let didAccess = selection.startAccessingSecurityScopedResource()
            defer { if didAccess { selection.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: selection.path, isDirectory: &isDirectory) else {
                skipped.append("\(selection.lastPathComponent): file not found")
                continue
            }
            if isSupported(selection) {
                found.append(selection)
            } else if isDirectory.boolValue {
                found.append(contentsOf: discoverFolder(selection, skipped: &skipped))
            } else {
                skipped.append("\(selection.lastPathComponent): unsupported file type")
            }
        }

        var seen: Set<String> = []
        let unique = found.filter { url in
            seen.insert(url.standardizedFileURL.resolvingSymlinksInPath().path).inserted
        }
        guard !unique.isEmpty else { throw ProjectImportError.noSupportedDocuments }
        return ProjectImportDiscoveryResult(
            sources: unique.map { ProjectImportSource(url: $0) },
            skippedItems: skipped
        )
    }

    static func isSupported(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
            || DocumentImportFormat.format(for: url) != nil
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private static func discoverFolder(_ folder: URL, skipped: inout [String]) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            skipped.append("\(folder.lastPathComponent): folder could not be read")
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if isSupported(url) {
                result.append(url)
                if values?.isDirectory == true { enumerator.skipDescendants() }
            }
        }
        return result.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}

enum ProjectImportConversionService {
    private static let maximumMarkdownBytes: UInt64 = 250_000_000

    static func load(_ source: ProjectImportSource) throws -> ProjectImportConversion {
        if ProjectImportSourceDiscovery.isMarkdown(source.url) {
            return try loadMarkdown(source)
        }
        return ProjectImportConversion(source: source, draft: try DocumentImportService.load(from: source.url))
    }

    private static func loadMarkdown(_ source: ProjectImportSource) throws -> ProjectImportConversion {
        let didAccess = source.url.startAccessingSecurityScopedResource()
        defer { if didAccess { source.url.stopAccessingSecurityScopedResource() } }

        let attributes = try FileManager.default.attributesOfItem(atPath: source.url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size <= maximumMarkdownBytes else { throw DocumentImportError.documentTooLarge }
        let data = try Data(contentsOf: source.url, options: .mappedIfSafe)
        let markdown = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let markdown else { throw ProjectImportError.unreadableMarkdown }
        return ProjectImportConversion(
            source: source,
            templateMarkdown: markdown,
            notices: [
                DocumentImportNotice(
                    severity: .information,
                    title: "Markdown preserved",
                    detail: "The source Markdown remains untouched. Kistulentz will write a separate imported copy."
                )
            ]
        )
    }
}

enum ProjectImportMarkdown {
    static func combinedDocument(
        from conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision],
        assetReferences: [UUID: String] = [:]
    ) -> String {
        conversions.map { conversion in
            hierarchicalSection(
                title: conversion.source.title,
                kind: conversion.source.kind,
                markdown: conversion.renderedMarkdown(
                    decisions: decisions,
                    assetReferences: assetReferences
                )
            )
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func hierarchicalSection(title: String, kind: OutlineNodeKind, markdown: String) -> String {
        let level: Int
        switch kind {
        case .part: level = 1
        case .chapter: level = 2
        case .scene, .section: level = 3
        }
        let shifted = shiftingHeadings(in: markdown, by: level)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = String(repeating: "#", count: level) + " " + title
        return shifted.isEmpty ? heading + "\n" : heading + "\n\n" + shifted + "\n"
    }

    static func shiftingHeadings(in markdown: String, by amount: Int) -> String {
        var fence: (character: Character, count: Int)?
        return markdown.components(separatedBy: "\n").map { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let marker = fenceMarker(in: trimmed) {
                if let open = fence {
                    if marker.character == open.character && marker.count >= open.count {
                        fence = nil
                    }
                } else {
                    fence = marker
                }
                return line
            }
            guard fence == nil else { return line }

            let prefixLength = line.prefix(while: { $0 == " " }).count
            guard prefixLength <= 3 else { return line }
            let content = line.dropFirst(prefixLength)
            let hashes = content.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes) else { return line }
            let afterHashes = content.dropFirst(hashes)
            guard afterHashes.first == " " || afterHashes.first == "\t" else { return line }
            let level = min(6, hashes + amount)
            return String(repeating: " ", count: prefixLength)
                + String(repeating: "#", count: level)
                + afterHashes
        }.joined(separator: "\n")
    }

    private static func fenceMarker(in content: Substring) -> (character: Character, count: Int)? {
        guard let first = content.first, first == "`" || first == "~" else { return nil }
        let count = content.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}

enum ProjectImportOutlineBuilder {
    static func build(paths: [String], sources: [ProjectImportSource]) throws -> [OutlineNode] {
        guard paths.count == sources.count else {
            throw ProjectImportError.invalidHierarchy("The import plan no longer matches its converted documents.")
        }
        var roots: [OutlineNode] = []
        var currentPartIndex: Int?
        var currentChapterLocation: (part: Int?, chapter: Int)?

        for (path, source) in zip(paths, sources) {
            var metadata = OutlineNodeMetadata()
            metadata.status = .drafting
            let node = OutlineNode(
                title: source.title,
                kind: source.kind,
                relativePath: path,
                metadata: metadata
            )

            switch source.kind {
            case .part:
                roots.append(node)
                currentPartIndex = roots.count - 1
                currentChapterLocation = nil
            case .chapter:
                if let partIndex = currentPartIndex {
                    roots[partIndex].children.append(node)
                    currentChapterLocation = (partIndex, roots[partIndex].children.count - 1)
                } else {
                    roots.append(node)
                    currentChapterLocation = (nil, roots.count - 1)
                }
            case .scene, .section:
                guard let location = currentChapterLocation else {
                    throw ProjectImportError.invalidHierarchy(
                        "\(source.kind.title) “\(source.title)” needs a Chapter before it. Reorder the files or change its assignment in the preview."
                    )
                }
                if let partIndex = location.part {
                    roots[partIndex].children[location.chapter].children.append(node)
                } else {
                    roots[location.chapter].children.append(node)
                }
            }
        }
        return roots
    }
}

enum ProjectImportOutputService {
    static func writeCombinedMarkdown(
        _ conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision],
        to outputURL: URL,
        replacingExisting: Bool = false
    ) throws -> ProjectImportWriteResult {
        try requireDecisions(for: conversions, decisions: decisions)
        let existedBefore = FileManager.default.fileExists(atPath: outputURL.path)
        guard !existedBefore || replacingExisting else {
            throw ProjectImportError.destinationExists(outputURL.lastPathComponent)
        }
        for conversion in conversions where conversion.source.url.standardizedFileURL == outputURL.standardizedFileURL {
            throw DocumentImportError.sourceWouldBeOverwritten
        }

        let parent = outputURL.deletingLastPathComponent()
        let assetFolder = uniqueDirectory(
            named: outputURL.deletingPathExtension().lastPathComponent + "-assets",
            in: parent
        )
        let assetPlan = ImportAssetWriter.plan(assetSpecs(for: conversions), in: assetFolder)

        var createdAssetURLs: [URL] = []
        do {
            createdAssetURLs = try ImportAssetWriter.write(assetPlan, to: assetFolder)
            let markdown = ProjectImportMarkdown.combinedDocument(
                from: conversions,
                decisions: decisions,
                assetReferences: assetPlan.references
            )
            try AtomicFileWriter.write(text: markdown, to: outputURL)
            return ProjectImportWriteResult(
                rootURL: outputURL,
                importedPaths: [outputURL.lastPathComponent],
                selectedPath: outputURL.lastPathComponent
            )
        } catch {
            var steps: [(label: String, attempt: () throws -> Void)] = []
            if !createdAssetURLs.isEmpty {
                steps.append((
                    label: "removing \(assetFolder.lastPathComponent)",
                    attempt: { try FileManager.default.removeItem(at: assetFolder) }
                ))
            }
            if !existedBefore {
                steps.append((
                    label: "removing \(outputURL.lastPathComponent)",
                    attempt: { try FileManager.default.removeItem(at: outputURL) }
                ))
            }
            try RollbackTracker.run(after: error, steps: steps) { originalReason, details in
                ProjectImportError.importFailedAndRollbackIncomplete(originalReason: originalReason, details: details)
            }
        }
    }

    static func createProject(
        from conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision],
        in parent: URL,
        name: String,
        kind: WritingProjectKind
    ) throws -> ProjectImportWriteResult {
        try requireDecisions(for: conversions, decisions: decisions)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanName.contains("/"), !cleanName.contains(":"), cleanName != ".", cleanName != ".." else {
            throw ProjectImportError.invalidProjectName
        }
        let destination = parent.appendingPathComponent(cleanName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ProjectImportError.destinationExists(cleanName)
        }

        let root = try WritingProjectDisk.createProject(in: parent, name: cleanName, kind: kind)
        do {
            let starterManifest = try WritingProjectDisk.loadManifest(at: root)
            let starterPaths = starterManifest.chapterOrder
            let result = try writeProjectDocuments(
                conversions,
                decisions: decisions,
                root: root,
                manifest: WritingProjectManifest(
                    name: starterManifest.name,
                    kind: starterManifest.kind,
                    createdAt: starterManifest.createdAt
                ),
                outline: ProjectOutlineArchive()
            )
            for path in starterPaths where !result.importedPaths.contains(path) {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
            }
            return result
        } catch {
            try RollbackTracker.run(
                after: error,
                steps: [(label: "removing the new project folder", attempt: { try FileManager.default.removeItem(at: root) })]
            ) { originalReason, details in
                ProjectImportError.importFailedAndRollbackIncomplete(originalReason: originalReason, details: details)
            }
        }
    }

    static func addToProject(
        _ conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision],
        root: URL
    ) throws -> ProjectImportWriteResult {
        try requireDecisions(for: conversions, decisions: decisions)
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let outline = try ProjectOutlineDisk.load(at: root)
        return try writeProjectDocuments(
            conversions,
            decisions: decisions,
            root: root,
            manifest: manifest,
            outline: outline
        )
    }

    private static func writeProjectDocuments(
        _ conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision],
        root: URL,
        manifest originalManifest: WritingProjectManifest,
        outline originalOutline: ProjectOutlineArchive
    ) throws -> ProjectImportWriteResult {
        var reserved = Set(originalManifest.chapterOrder.map { $0.lowercased() })
        let paths = conversions.map { conversion in
            let proposed = HeadingSplitPlanner.safeFileComponent(conversion.source.title) + ".md"
            return uniqueFilename(proposed, reserved: &reserved)
        }
        let importedNodes = try ProjectImportOutlineBuilder.build(
            paths: paths,
            sources: conversions.map(\.source)
        )

        let assetFolder = uniqueDirectory(named: "Imported Assets", in: root)
        let assetPlan = ImportAssetWriter.plan(assetSpecs(for: conversions), in: assetFolder)

        var createdURLs: [URL] = []
        do {
            // Track the asset folder as a single unit (like writeCombinedMarkdown does) rather
            // than each file inside it individually -- FileManager.removeItem already removes a
            // directory and its contents in one call, so per-file entries would just mean more
            // (equally reliable, but more confusingly reported on partial failure) rollback steps.
            if !(try ImportAssetWriter.write(assetPlan, to: assetFolder)).isEmpty {
                createdURLs.append(assetFolder)
            }
            for (conversion, path) in zip(conversions, paths) {
                let target = root.appendingPathComponent(path)
                guard conversion.source.url.standardizedFileURL != target.standardizedFileURL else {
                    throw DocumentImportError.sourceWouldBeOverwritten
                }
                let markdown = conversion.renderedMarkdown(
                    decisions: decisions,
                    assetReferences: assetPlan.references
                )
                try AtomicFileWriter.write(text: markdown, to: target)
                createdURLs.append(target)
            }

            var manifest = originalManifest
            manifest.chapterOrder.append(contentsOf: paths)
            manifest.lastOpenedChapter = paths.first ?? manifest.lastOpenedChapter
            var outline = originalOutline
            outline.nodes.append(contentsOf: importedNodes)
            try WritingProjectDisk.saveManifest(manifest, at: root)
            try ProjectOutlineDisk.save(outline, at: root)
            return ProjectImportWriteResult(
                rootURL: root,
                importedPaths: paths,
                selectedPath: paths.first
            )
        } catch {
            var rollbackFailures: [String] = []
            do {
                try WritingProjectDisk.saveManifest(originalManifest, at: root)
            } catch let rollbackError {
                rollbackFailures.append("chapter list: \(rollbackError.localizedDescription)")
            }
            do {
                try ProjectOutlineDisk.save(originalOutline, at: root)
            } catch let rollbackError {
                rollbackFailures.append("outline: \(rollbackError.localizedDescription)")
            }
            for url in createdURLs.reversed() {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let rollbackError {
                    rollbackFailures.append("\(url.lastPathComponent): \(rollbackError.localizedDescription)")
                }
            }
            // Only the ORIGINAL error matters when the rollback itself succeeds -- that's the
            // existing, well-tested behavior. But if any rollback step also failed, manifest.json
            // and outline.json (or the newly-created files) can now disagree, so the caller needs
            // a distinctly more severe message rather than one that implies nothing changed.
            guard rollbackFailures.isEmpty else {
                throw ProjectImportError.importFailedAndRollbackIncomplete(
                    originalReason: error.localizedDescription,
                    details: rollbackFailures.joined(separator: "; ")
                )
            }
            throw error
        }
    }

    private static func requireDecisions(
        for conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision]
    ) throws {
        let required = Set(conversions.flatMap(\.reviewCards).map(\.id))
        guard Set(decisions.keys).isSuperset(of: required) else {
            throw ProjectImportError.unresolvedTrackedChanges
        }
    }

    private static func assetSpecs(
        for conversions: [ProjectImportConversion]
    ) -> [(id: UUID, proposedName: String, asset: DocumentImportAsset)] {
        conversions.flatMap { conversion in
            conversion.assets.map { asset in
                (id: asset.id, proposedName: conversion.source.title + "-" + asset.suggestedFilename, asset: asset)
            }
        }
    }

    private static func uniqueDirectory(named name: String, in parent: URL) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
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

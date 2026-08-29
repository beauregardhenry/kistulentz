import AppKit
import Foundation
import ImageIO

enum PublicationDisk {
    private static let fileName = "publication.json"
    private static let assetsDirectoryName = "publication-assets"

    static func prepare(at root: URL, projectName: String, projectKind: WritingProjectKind) throws {
        try FileManager.default.createDirectory(at: assetsURL(at: root), withIntermediateDirectories: true)
        let url = archiveURL(at: root)
        if FileManager.default.fileExists(atPath: url.path) {
            var archive = try load(at: root)
            archive = reconcile(archive, projectName: projectName, projectKind: projectKind)
            try save(archive, at: root)
        } else {
            try save(PublicationArchive(projectName: projectName, projectKind: projectKind), at: root)
        }
    }

    static func load(at root: URL) throws -> PublicationArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PublicationArchive.self, from: Data(contentsOf: archiveURL(at: root)))
    }

    static func save(_ archive: PublicationArchive, at root: URL) throws {
        try FileManager.default.createDirectory(at: WritingProjectDisk.metadataURL(at: root), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(archive).write(to: archiveURL(at: root), options: .atomic)
    }

    static func copyPublicationAsset(from sourceURL: URL, preferredName: String, at root: URL) throws -> String {
        let source = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw PublicationExportError.outputCreationFailed("The selected asset no longer exists.")
        }
        try FileManager.default.createDirectory(at: assetsURL(at: root), withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased()
        let safeBase = HeadingSplitPlanner.safeFileComponent(preferredName)
        let fileName = ext.isEmpty ? safeBase : "\(safeBase).\(ext)"
        let destination = assetsURL(at: root).appendingPathComponent(fileName)
        if source == destination.standardizedFileURL {
            return "\(WritingProjectDisk.metadataDirectoryName)/\(assetsDirectoryName)/\(fileName)"
        }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        return "\(WritingProjectDisk.metadataDirectoryName)/\(assetsDirectoryName)/\(fileName)"
    }

    static func resolveAsset(_ relativePath: String?, at root: URL) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return root.appendingPathComponent(relativePath).standardizedFileURL
    }

    private static func archiveURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(fileName)
    }

    private static func assetsURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    private static func reconcile(
        _ archive: PublicationArchive,
        projectName: String,
        projectKind: WritingProjectKind
    ) -> PublicationArchive {
        var result = archive
        if result.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.metadata.title = projectName
        }
        let existingProfileIDs = Set(result.profiles.map(\.id))
        result.profiles.append(contentsOf: ExportProfile.builtIns(for: projectKind).filter { !existingProfileIDs.contains($0.id) })
        if !result.profiles.contains(where: { $0.id == result.selectedProfileID }), let first = result.profiles.first {
            result.selectedProfileID = first.id
        }
        let existingKinds = Set(result.matter.map(\.kind))
        result.matter.append(contentsOf: PublicationMatterGenerator.defaultItems(metadata: result.metadata).filter { !existingKinds.contains($0.kind) })
        return result
    }
}

enum PublicationPlanBuilder {
    static func build(
        projectName: String,
        root: URL,
        outline: [OutlineNode],
        archive: PublicationArchive,
        bibliography: ProjectBibliographyArchive,
        librarySources: [ResearchSource],
        profile: ExportProfile,
        format: PublicationExportFormat,
        destinations: [PublicationDestination]? = nil
    ) -> PublicationExportPlan {
        var items: [ExportPlanItem] = []
        if profile.includeFrontMatter {
            for matter in archive.matter.filter({ $0.kind.isFrontMatter }) {
                let enabled = matter.isIncluded
                    && (matter.kind != .tableOfContents || profile.includeTableOfContents)
                items.append(matterItem(matter, kind: .frontMatter, included: enabled))
            }
        }

        func append(_ nodes: [OutlineNode], depth: Int, ancestorIncluded: Bool) {
            for node in nodes {
                let explicitlyIncluded = node.metadata.includedInExport
                let effectiveIncluded = ancestorIncluded && explicitlyIncluded
                let reason: String? = !ancestorIncluded
                    ? "A parent outline item is excluded."
                    : (!explicitlyIncluded ? "Excluded in Project Organization." : nil)

                if let path = node.relativePath {
                    let url = root.appendingPathComponent(path)
                    let text = (try? WritingProjectDisk.readChapter(path, at: root)) ?? ""
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    items.append(ExportPlanItem(
                        id: "outline-\(node.id.uuidString)",
                        kind: .manuscript,
                        title: node.title,
                        markdown: text,
                        sourcePath: path,
                        outlineNodeID: node.id,
                        depth: depth,
                        isIncluded: effectiveIncluded && exists,
                        exclusionReason: exists ? reason : "The Markdown file is missing.",
                        matterKind: nil
                    ))
                } else {
                    items.append(ExportPlanItem(
                        id: "outline-\(node.id.uuidString)",
                        kind: .part,
                        title: node.title,
                        markdown: "# \(node.title)\n",
                        sourcePath: nil,
                        outlineNodeID: node.id,
                        depth: depth,
                        isIncluded: effectiveIncluded,
                        exclusionReason: reason,
                        matterKind: nil
                    ))
                }
                append(node.children, depth: depth + 1, ancestorIncluded: effectiveIncluded)
            }
        }
        append(outline, depth: 0, ancestorIncluded: true)

        if profile.citationMode == .endnotes,
           let endnotes = archive.matter.first(where: { $0.kind == .endnotes }) {
            items.append(matterItem(endnotes, kind: .backMatter, included: true))
        }
        if profile.includeBibliography,
           let bibliographyMatter = archive.matter.first(where: { $0.kind == .bibliography }) {
            items.append(matterItem(bibliographyMatter, kind: .backMatter, included: true))
        }
        if profile.includeBackMatter {
            for matter in archive.matter.filter({ !$0.kind.isFrontMatter && ![.endnotes, .bibliography].contains($0.kind) }) {
                items.append(matterItem(matter, kind: .backMatter, included: matter.isIncluded))
            }
        }

        let sourceIDs = Set(bibliography.sourceIDs)
        return PublicationExportPlan(
            projectName: projectName,
            profile: profile,
            format: format,
            items: items,
            metadata: archive.metadata,
            bibliography: bibliography,
            sources: librarySources.filter { sourceIDs.contains($0.id) },
            destinations: destinations ?? (format == .epub ? [.genericEPUB] : [])
        )
    }

    static func previewMarkdown(_ plan: PublicationExportPlan) -> String {
        plan.includedItems.map { item in
            let marker: String
            switch item.kind {
            case .frontMatter: marker = "FRONT MATTER"
            case .part: marker = "DIVISION"
            case .manuscript: marker = item.sourcePath ?? "MANUSCRIPT"
            case .backMatter: marker = "BACK MATTER"
            }
            return "<!-- \(marker): \(item.title) -->\n\n\(item.markdown.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n\n---\n\n") + "\n"
    }

    private static func matterItem(
        _ matter: PublicationMatterItem,
        kind: ExportPlanItemKind,
        included: Bool
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: "matter-\(matter.kind.rawValue)",
            kind: kind,
            title: matter.title,
            markdown: matter.markdown,
            sourcePath: nil,
            outlineNodeID: nil,
            depth: 0,
            isIncluded: included,
            exclusionReason: included ? nil : "Excluded in Publication Setup.",
            matterKind: matter.kind
        )
    }
}

struct PublicationImageReference: Equatable {
    var altText: String
    var path: String
    var title: String
    var range: NSRange
}

enum PublicationMarkdownScanner {
    private static let imageRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\((?:<([^>]+)>|([^\s\)]+))(?:\s+[\"']([^\"']*)[\"'])?\)"#
    )
    private static let citationContainerRegex = try! NSRegularExpression(pattern: #"\[[^\]]*@[^\]]+\]"#)
    private static let citationKeyRegex = try! NSRegularExpression(pattern: #"@([A-Za-z0-9_:\-]+)"#)
    private static let footnoteReferenceRegex = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)
    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: #"(?m)^\[\^([^\]]+)\]:\s*(.+)$"#)

    static func images(in markdown: String) -> [PublicationImageReference] {
        let source = markdown as NSString
        return imageRegex.matches(in: markdown, range: NSRange(location: 0, length: source.length)).map { match in
            let pathRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            return PublicationImageReference(
                altText: match.range(at: 1).location == NSNotFound ? "" : source.substring(with: match.range(at: 1)),
                path: source.substring(with: pathRange).removingPercentEncoding ?? source.substring(with: pathRange),
                title: match.range(at: 4).location == NSNotFound ? "" : source.substring(with: match.range(at: 4)),
                range: match.range
            )
        }
    }

    static func citationKeys(in markdown: String) -> [String] {
        let source = markdown as NSString
        var keys: [String] = []
        for container in citationContainerRegex.matches(in: markdown, range: NSRange(location: 0, length: source.length)) {
            let text = source.substring(with: container.range)
            let value = text as NSString
            for match in citationKeyRegex.matches(in: text, range: NSRange(location: 0, length: value.length)) {
                keys.append(value.substring(with: match.range(at: 1)))
            }
        }
        return keys
    }

    static func footnoteReferences(in markdown: String) -> [String] {
        let withoutDefinitions = footnoteDefinitionRegex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: (markdown as NSString).length),
            withTemplate: ""
        )
        let source = withoutDefinitions as NSString
        return footnoteReferenceRegex.matches(in: withoutDefinitions, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
    }

    static func footnoteDefinitions(in markdown: String) -> [String: String] {
        let source = markdown as NSString
        return footnoteDefinitionRegex.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        ).reduce(into: [:]) { result, match in
            let key = source.substring(with: match.range(at: 1))
            if result[key] == nil { result[key] = source.substring(with: match.range(at: 2)) }
        }
    }

    static func headingLevels(in markdown: String) -> [Int] {
        var inFence = false
        var levels: [Int] = []
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            let count = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(count), trimmed.dropFirst(count).first == " " { levels.append(count) }
        }
        return levels
    }

    static func resolveImagePath(_ path: String, sourcePath: String?, root: URL) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        let directory = sourcePath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        return root.appendingPathComponent(directory).appendingPathComponent(path).standardizedFileURL
    }
}

struct PublicationRasterImageInfo: Equatable {
    var pixelWidth: Int
    var pixelHeight: Int
    var colorModel: String?

    var pixelCount: Int { pixelWidth * pixelHeight }
    var shortestSide: Int { min(pixelWidth, pixelHeight) }
}

enum PublicationImageInspector {
    static func rasterInfo(at url: URL) -> PublicationRasterImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PublicationRasterImageInfo(
            pixelWidth: width,
            pixelHeight: height,
            colorModel: properties[kCGImagePropertyColorModel] as? String
        )
    }

    static func effectiveDPI(
        image: PublicationRasterImageInfo,
        layout: PublicationLayout
    ) -> Double {
        let contentWidth = max(1, layout.pageSize.widthPoints - layout.insideMargin - layout.outsideMargin)
        let contentHeight = max(1, layout.pageSize.heightPoints - layout.topMargin - layout.bottomMargin) * 0.55
        let scale = min(contentWidth / Double(image.pixelWidth), contentHeight / Double(image.pixelHeight))
        let placedWidthInches = Double(image.pixelWidth) * scale / 72
        let placedHeightInches = Double(image.pixelHeight) * scale / 72
        return min(
            Double(image.pixelWidth) / max(placedWidthInches, 0.01),
            Double(image.pixelHeight) / max(placedHeightInches, 0.01)
        )
    }
}

enum PublicationPreflight {
    static func run(plan: PublicationExportPlan, root: URL) -> PublicationPreflightReport {
        var findings: [PublicationPreflightFinding] = []
        func add(
            _ severity: PublicationPreflightSeverity,
            _ id: String,
            _ title: String,
            _ detail: String,
            _ path: String? = nil,
            readiness: PublicationReadinessStatus = .actionRequired,
            requirementURL: String? = nil
        ) {
            findings.append(PublicationPreflightFinding(
                id: id,
                severity: severity,
                title: title,
                detail: detail,
                sourcePath: path,
                readinessStatus: readiness,
                requirementURL: requirementURL
            ))
        }

        if plan.destinations.isEmpty {
            add(.warning, "destination-none", "No publication destination is selected", "Choose at least one destination to receive target-specific checks and a useful submission report.")
        }
        for destination in plan.destinations where !destination.compatibleFormats.contains(plan.format) {
            add(
                .error,
                "destination-format-\(destination.rawValue)",
                "\(destination.title) does not accept \(plan.format.title)",
                "Choose \(destination.compatibleFormats.map(\.title).joined(separator: " or ")) or remove this destination from the current export.",
                readiness: .actionRequired,
                requirementURL: destination.requirementURL
            )
        }
        for destination in plan.destinations where destination.compatibleFormats.contains(plan.format) {
            add(
                .information,
                "destination-pass-\(destination.rawValue)",
                "Format matches \(destination.title)",
                "Kistulentz can run the local checks documented for this destination.",
                readiness: .passedLocally,
                requirementURL: destination.requirementURL
            )
        }

        if plan.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, "metadata-title", "Publication title is missing", "Enter a title in Publication Setup.")
        }
        if plan.metadata.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, "metadata-language", "Language is missing", "EPUB and document metadata require a publication language.")
        }
        if plan.metadata.authors.isEmpty {
            add(.warning, "metadata-author", "No author is listed", "Add at least one author or confirm that an anonymous publication is intentional.")
        }
        if plan.metadata.identifier.isEmpty {
            add(.warning, "metadata-identifier", "Identifier is missing", "Add an ISBN or another stable identifier for publication metadata.")
        }
        if plan.manuscriptItems.isEmpty {
            add(.error, "manuscript-empty", "No manuscript sections are included", "Enable at least one outline item in the Export Plan.")
        }

        for item in plan.items where item.exclusionReason == "The Markdown file is missing." {
            add(.error, "missing-\(item.id)", "Outline file is missing", "\(item.title) points to a Markdown file that no longer exists.", item.sourcePath)
        }

        let knownCitations = Set(plan.sources.map { $0.citeKey.lowercased() })
        let citationGroups = Dictionary(grouping: plan.sources, by: { $0.citeKey.lowercased() })
        for (key, matches) in citationGroups where matches.count > 1 {
            add(.error, "duplicate-cite-\(key)", "Citation key @\(key) is duplicated", "Give every project source a unique citation key before exporting.")
        }
        var referencedFootnotes: Set<String> = []
        var definedFootnotes: Set<String> = []
        var rasterImages: [(path: String, info: PublicationRasterImageInfo)] = []
        for item in plan.includedItems {
            if item.kind == .manuscript, item.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(.warning, "empty-\(item.id)", "Included section is empty", "\(item.title) contains no exportable text.", item.sourcePath)
            }
            for key in Set(PublicationMarkdownScanner.citationKeys(in: item.markdown)) where !knownCitations.contains(key.lowercased()) {
                add(.error, "cite-\(item.id)-\(key.lowercased())", "Unresolved citation @\(key)", "Add this source to the project bibliography or correct the citation key.", item.sourcePath)
            }
            referencedFootnotes.formUnion(PublicationMarkdownScanner.footnoteReferences(in: item.markdown))
            definedFootnotes.formUnion(PublicationMarkdownScanner.footnoteDefinitions(in: item.markdown).keys)
            for (imageIndex, image) in PublicationMarkdownScanner.images(in: item.markdown).enumerated() {
                let url = PublicationMarkdownScanner.resolveImagePath(image.path, sourcePath: item.sourcePath, root: root)
                if !FileManager.default.fileExists(atPath: url.path) {
                    add(.error, "image-\(item.id)-\(imageIndex)", "Image is missing", "The image path \(image.path) cannot be resolved.", item.sourcePath)
                } else if let info = PublicationImageInspector.rasterInfo(at: url) {
                    rasterImages.append((url.lastPathComponent, info))
                }
                if plan.format == .epub, PublicationMediaType.epub(for: url) == nil {
                    add(.error, "image-format-\(item.id)-\(imageIndex)", "Image format is not EPUB-compatible", "Convert \(url.lastPathComponent) to PNG, JPEG, GIF, SVG, or WebP.", item.sourcePath)
                }
                if plan.format == .docx, PublicationMediaType.docx(for: url) == nil {
                    add(.error, "image-format-\(item.id)-\(imageIndex)", "Image format is not DOCX-compatible", "Convert \(url.lastPathComponent) to PNG, JPEG, GIF, TIFF, or BMP.", item.sourcePath)
                }
                if image.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let severity: PublicationPreflightSeverity = plan.profile.kind == .accessibleEPUB ? .error : .warning
                    add(severity, "alt-\(item.id)-\(imageIndex)", "Image has no alternative text", "Add meaningful text inside the Markdown image brackets.", item.sourcePath)
                }
            }
        }
        for key in referencedFootnotes.subtracting(definedFootnotes).sorted() {
            add(.error, "footnote-\(key)", "Footnote [^\(key)] has no definition", "Add a matching [^\(key)]: definition.")
        }

        if plan.profile.includeCover {
            if let coverURL = PublicationDisk.resolveAsset(plan.metadata.coverImageRelativePath, at: root) {
                if !FileManager.default.fileExists(atPath: coverURL.path) {
                    add(.error, "cover-missing", "Cover image is missing", "Choose the cover image again in Publication Setup.")
                } else if plan.metadata.coverAltText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let severity: PublicationPreflightSeverity = plan.profile.kind == .accessibleEPUB ? .error : .warning
                    add(severity, "cover-alt", "Cover has no alternative text", "Describe the cover for digital accessibility.")
                }
                if plan.format == .epub, PublicationMediaType.epub(for: coverURL) == nil {
                    add(.error, "cover-format", "Cover format is not EPUB-compatible", "Use a PNG, JPEG, GIF, SVG, or WebP cover image.")
                }
                if plan.format == .docx, PublicationMediaType.docx(for: coverURL) == nil {
                    add(.error, "cover-format", "Cover format is not DOCX-compatible", "Use a PNG, JPEG, GIF, TIFF, or BMP cover image.")
                }
                if let info = PublicationImageInspector.rasterInfo(at: coverURL) {
                    targetCoverChecks(plan: plan, coverURL: coverURL, info: info, add: add)
                }
            } else {
                add(.warning, "cover-none", "No cover image is selected", "The publication can still export, but digital editions will not contain a cover image.")
            }
        }

        if plan.format == .printPDF,
           let printCover = plan.metadata.printCoverPDFRelativePath,
           let url = PublicationDisk.resolveAsset(printCover, at: root),
           !FileManager.default.fileExists(atPath: url.path) {
            add(.warning, "print-cover-missing", "Separate print cover is missing", "Choose the print-cover PDF again. The interior PDF can still be generated.")
        }
        if [.printPDF, .readerPDF, .docx].contains(plan.format) {
            if NSFont(name: plan.profile.layout.bodyFontName, size: plan.profile.layout.bodyFontSize) == nil {
                add(.warning, "font-body", "Body font is unavailable", "Kistulentz will use a system serif fallback instead of \(plan.profile.layout.bodyFontName).")
            }
            if NSFont(name: plan.profile.layout.headingFontName, size: plan.profile.layout.bodyFontSize * 1.5) == nil {
                add(.warning, "font-heading", "Heading font is unavailable", "Kistulentz will use a system sans-serif fallback instead of \(plan.profile.layout.headingFontName).")
            }
        }
        if plan.format == .printPDF {
            targetPrintChecks(plan: plan, rasterImages: rasterImages, add: add)
        }
        if plan.format == .epub {
            targetEPUBChecks(plan: plan, rasterImages: rasterImages, add: add)
        }
        if plan.profile.kind == .accessibleEPUB {
            for item in plan.manuscriptItems {
                let levels = PublicationMarkdownScanner.headingLevels(in: item.markdown)
                var previous = 1
                for level in levels.dropFirst(levels.first == 1 ? 1 : 0) {
                    if level > previous + 1 {
                        add(.error, "heading-\(item.id)-\(level)", "Heading levels skip structure", "\(item.title) jumps from level \(previous) to level \(level). Use consecutive heading levels for accessible navigation.", item.sourcePath)
                        break
                    }
                    previous = level
                }
            }
            add(
                .information,
                "a11y-scope",
                "Accessibility review remains necessary",
                "Kistulentz checks structure, navigation, language, images, and metadata locally. Human review and a dedicated EPUB conformance checker remain necessary before claiming WCAG or EPUB Accessibility conformance.",
                readiness: .manualReviewRequired,
                requirementURL: "https://www.w3.org/TR/epub-a11y-11/"
            )
        }
        return PublicationPreflightReport(findings: findings)
    }

    private static func targetCoverChecks(
        plan: PublicationExportPlan,
        coverURL: URL,
        info: PublicationRasterImageInfo,
        add: (PublicationPreflightSeverity, String, String, String, String?, PublicationReadinessStatus, String?) -> Void
    ) {
        if plan.destinations.contains(.appleBooks), info.pixelCount > 5_600_000 {
            add(.error, "apple-cover-pixels", "Apple Books cover exceeds 5.6 million pixels", "The selected cover is \(info.pixelWidth) × \(info.pixelHeight) pixels. Resize it before submission.", nil, .actionRequired, PublicationDestination.appleBooks.requirementURL)
        }
        if plan.destinations.contains(.kindleEbook) {
            let extensionName = coverURL.pathExtension.lowercased()
            if !["jpg", "jpeg", "tif", "tiff"].contains(extensionName) {
                add(.warning, "kindle-cover-format", "Kindle requires a JPEG or TIFF marketing cover", "The embedded cover can remain in the EPUB, but supply a separate JPEG or TIFF cover for KDP.", nil, .actionRequired, "https://kdp.amazon.com/en_US/help/topic/G200645690")
            }
            if info.pixelWidth < 1_000 || info.pixelHeight < 625 {
                add(.warning, "kindle-cover-size", "Kindle cover is below the documented minimum", "The selected cover is \(info.pixelWidth) × \(info.pixelHeight) pixels; KDP documents a 1,000 × 625 pixel minimum.", nil, .actionRequired, "https://kdp.amazon.com/en_US/help/topic/G200645690")
            }
        }
        if plan.destinations.contains(.ingramSparkEbook) {
            if !["jpg", "jpeg"].contains(coverURL.pathExtension.lowercased()) {
                add(.warning, "ingram-cover-format", "IngramSpark eBook cover should be JPEG", "Supply the separate eBook cover as a JPEG even though the current image can be embedded in the EPUB.", nil, .actionRequired, PublicationDestination.ingramSparkEbook.requirementURL)
            }
            if info.shortestSide < 1_600 {
                add(.warning, "ingram-cover-size", "IngramSpark cover is below 1,600 pixels on its shortest side", "The selected cover is \(info.pixelWidth) × \(info.pixelHeight) pixels.", nil, .actionRequired, PublicationDestination.ingramSparkEbook.requirementURL)
            }
            if let model = info.colorModel, model.localizedCaseInsensitiveCompare("RGB") != .orderedSame {
                add(.warning, "ingram-cover-color", "IngramSpark eBook cover is not identified as RGB", "The detected color model is \(model). Verify or convert the separate cover before submission.", nil, .manualReviewRequired, PublicationDestination.ingramSparkEbook.requirementURL)
            }
        }
    }

    private static func targetEPUBChecks(
        plan: PublicationExportPlan,
        rasterImages: [(path: String, info: PublicationRasterImageInfo)],
        add: (PublicationPreflightSeverity, String, String, String, String?, PublicationReadinessStatus, String?) -> Void
    ) {
        let retailerDestinations: [PublicationDestination] = [.appleBooks, .kindleEbook, .ingramSparkEbook]
        if !plan.destinations.filter({ retailerDestinations.contains($0) }).isEmpty,
           (!plan.profile.includeCover || plan.metadata.coverImageRelativePath == nil) {
            add(.warning, "retailer-ebook-cover", "No retailer eBook cover will be packaged", "Choose and include a cover, or plan to create and supply one in the retailer's separate cover workflow.", nil, .actionRequired, plan.destinations.first(where: { retailerDestinations.contains($0) })?.requirementURL)
        }
        if plan.destinations.contains(.appleBooks) {
            for image in rasterImages where image.info.pixelCount > 5_600_000 {
                add(.error, "apple-image-\(PublicationHash.shortHash(image.path))", "Image exceeds Apple Books' pixel limit", "\(image.path) is \(image.info.pixelWidth) × \(image.info.pixelHeight) pixels, exceeding 5.6 million pixels.", image.path, .actionRequired, PublicationDestination.appleBooks.requirementURL)
            }
            add(.information, "apple-transporter", "Apple Transporter validation is still required", "Kistulentz cannot guarantee acceptance by Apple Books. Validate the finished EPUB during delivery with Apple's current Transporter workflow.", nil, .externalValidationRequired, PublicationDestination.appleBooks.requirementURL)
        }
        if plan.destinations.contains(.kindleEbook) {
            if !plan.profile.includeTableOfContents {
                add(.warning, "kindle-visible-toc", "A visible table of contents is disabled", "The EPUB still contains logical navigation, but KDP strongly recommends a visible HTML table of contents.", nil, .actionRequired, "https://kdp.amazon.com/en_US/help/topic/G201605710")
            }
            add(.information, "kindle-previewer", "Kindle Previewer review is required", "Open the finished EPUB in Kindle Previewer and inspect reflow, navigation, images, and typography before upload.", nil, .externalValidationRequired, PublicationDestination.kindleEbook.requirementURL)
        }
        if plan.destinations.contains(.ingramSparkEbook) {
            if !isValidISBN13(plan.metadata.identifier) {
                add(.warning, "ingram-ebook-isbn", "IngramSpark eBook identifier is not a valid ISBN-13", "Enter the eBook edition's own ISBN-13 in Publication Setup before submission.", nil, .actionRequired, PublicationDestination.ingramSparkEbook.requirementURL)
            }
            add(.information, "ingram-ebook-upload", "IngramSpark upload validation is required", "Kistulentz checks the local EPUB package, but IngramSpark's current upload validation remains authoritative.", nil, .externalValidationRequired, PublicationDestination.ingramSparkEbook.requirementURL)
        }
        add(.information, "epubcheck", "EPUBCheck validation is required", "Kistulentz will run EPUBCheck automatically when its command-line tool is installed. Otherwise, the submission report records that external validation remains outstanding.", nil, .externalValidationRequired, "https://github.com/w3c/epubcheck")
        add(.information, "epub-visual-review", "Reading-system review is required", "Inspect the exported book in at least one representative reading system. Automated checks cannot judge every visual or semantic result.", nil, .manualReviewRequired, "https://www.w3.org/TR/epub-a11y-11/")
    }

    private static func targetPrintChecks(
        plan: PublicationExportPlan,
        rasterImages: [(path: String, info: PublicationRasterImageInfo)],
        add: (PublicationPreflightSeverity, String, String, String, String?, PublicationReadinessStatus, String?) -> Void
    ) {
        let printTargets = plan.destinations.filter { [.kdpPrint, .ingramSparkPrint].contains($0) }
        guard !printTargets.isEmpty else { return }
        if plan.profile.layout.bodyFontSize < 7 {
            add(.error, "print-font-size", "Body type is smaller than 7 points", "Increase the body font size for print submission.", nil, .actionRequired, PublicationDestination.kdpPrint.requirementURL)
        }
        let minimumOutside = plan.profile.printBleed == .outside ? 27.0 : 18.0
        if plan.profile.layout.topMargin < minimumOutside ||
            plan.profile.layout.bottomMargin < minimumOutside ||
            plan.profile.layout.outsideMargin < minimumOutside {
            add(.error, "print-outer-margins", "Print safety margins are too small", "Use at least \(minimumOutside / 72) inches for top, bottom, and outside margins with the selected bleed mode.", nil, .actionRequired, PublicationDestination.kdpPrint.requirementURL)
        }
        if plan.profile.layout.insideMargin < 27 {
            add(.error, "print-gutter-minimum", "Inside gutter is below the smallest KDP minimum", "Use at least 0.375 inches. Longer books require a larger gutter after final pagination.", nil, .actionRequired, "https://kdp.amazon.com/en_US/help/topic/GVBQ3CMEQW3W2VL6")
        }
        for image in rasterImages {
            let dpi = PublicationImageInspector.effectiveDPI(image: image.info, layout: plan.profile.layout)
            if dpi < 300 {
                add(.warning, "print-image-dpi-\(PublicationHash.shortHash(image.path))", "Image may render below 300 DPI", "\(image.path) is estimated at \(Int(dpi.rounded())) DPI at its maximum placed size.", image.path, .actionRequired, PublicationDestination.kdpPrint.requirementURL)
            }
        }
        add(.information, "print-bleed-geometry", "Print page geometry will be generated locally", plan.profile.printBleed == .outside ? "The PDF will include 0.125-inch top, bottom, and outside bleed with no gutter bleed or printer marks." : "The PDF will use the selected trim size without bleed or printer marks.", nil, .passedLocally, printTargets[0].requirementURL)
        add(.information, "print-font-embedding", "Font embedding requires final-PDF verification", "Kistulentz verifies that the selected fonts are available before export. Confirm embedding in the completed PDF before submission.", nil, .externalValidationRequired, printTargets[0].requirementURL)
        add(.information, "print-gutter-review", "Final page count and gutter require review", "Retailer gutter requirements depend on the final page count. The submission report records the generated page count so you can confirm the applicable bracket.", nil, .manualReviewRequired, printTargets[0].requirementURL)
        if plan.destinations.contains(.ingramSparkPrint) {
            if !isValidISBN13(plan.metadata.identifier) {
                add(.warning, "ingram-print-isbn", "IngramSpark print identifier is not a valid ISBN-13", "Enter the print edition's ISBN-13 in Publication Setup before submission.", nil, .actionRequired, PublicationDestination.ingramSparkPrint.requirementURL)
            }
            add(.information, "ingram-color-review", "Print color handling requires review", "Kistulentz does not convert placed artwork to a printer-specific CMYK profile. Confirm image color and ink coverage for the selected IngramSpark print option.", nil, .manualReviewRequired, PublicationDestination.ingramSparkPrint.requirementURL)
        }
        if plan.metadata.printCoverPDFRelativePath == nil {
            add(.warning, "print-cover-none", "No separate print-cover PDF is supplied", "The submission folder will contain the interior and readiness documents only. Add a cover made from the retailer's current template before submission.", nil, .actionRequired, printTargets[0].requirementURL)
        }
        add(.information, "print-cover-review", "Separate cover geometry requires review", "The supplied cover PDF is copied unchanged. Confirm trim, spine width, bleed, barcode area, and current template against the final page count.", nil, .manualReviewRequired, printTargets[0].requirementURL)
    }

    private static func isValidISBN13(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == 13, digits[0] == 9, [7, 8].contains(digits[1]) else { return false }
        let checksum = digits.prefix(12).enumerated().reduce(0) { partial, entry in
            partial + entry.element * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - checksum % 10) % 10 == digits[12]
    }
}

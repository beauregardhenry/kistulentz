import AppKit
import XCTest
@testable import Kistulentz

/// Covers `PublicationPlanning.swift`'s pure, synchronous logic that `PublicationTests` never
/// reached: `PublicationDisk.reconcile`'s upgrade-path fallbacks, `copyPublicationAsset`'s edge
/// cases, `previewMarkdown` and `headingLevels` (both entirely untested), and -- the largest gap
/// by far -- `PublicationPreflight`'s destination-specific checks (Apple Books/Kindle/IngramSpark
/// cover and format rules, print margin/gutter/DPI rules). None of this touches the network or a
/// hardcoded singleton, so it's all directly testable.
final class PublicationPlanningTests: XCTestCase {

    // MARK: - PublicationDisk

    func testPrepareReconcilesABlankTitleAndAnInvalidSelectedProfileOnReopen() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try PublicationDisk.prepare(at: root, projectName: "Original Name", projectKind: .fiction)
        var archive = try PublicationDisk.load(at: root)
        archive.metadata.title = "   "
        archive.selectedProfileID = UUID()
        try PublicationDisk.save(archive, at: root)

        try PublicationDisk.prepare(at: root, projectName: "Reopened Name", projectKind: .fiction)

        let reconciled = try PublicationDisk.load(at: root)
        XCTAssertEqual(reconciled.metadata.title, "Reopened Name", "a blank title must be refilled from the current project name")
        XCTAssertEqual(reconciled.selectedProfileID, reconciled.profiles.first?.id, "a selected profile that no longer exists must fall back to the first available one")
    }

    func testCopyPublicationAssetRejectsAMissingSourceFile() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missingSource = root.appendingPathComponent("does-not-exist.png")

        XCTAssertThrowsError(try PublicationDisk.copyPublicationAsset(from: missingSource, preferredName: "cover", at: root)) { error in
            guard case .outputCreationFailed = error as? PublicationExportError else {
                return XCTFail("expected outputCreationFailed, got \(error)")
            }
        }
    }

    func testCopyPublicationAssetIsANoOpWhenTheSourceIsAlreadyAtTheDestination() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let source = outside.appendingPathComponent("cover.png")
        try makePNG(at: source)
        let firstPath = try PublicationDisk.copyPublicationAsset(from: source, preferredName: "cover", at: root)
        let destinationURL = root.appendingPathComponent(firstPath)

        let secondPath = try PublicationDisk.copyPublicationAsset(from: destinationURL, preferredName: "cover", at: root)

        XCTAssertEqual(secondPath, firstPath)
    }

    // MARK: - PublicationMarkdownScanner.headingLevels

    func testHeadingLevelsSkipsFencedCodeBlocksAndIgnoresHeadingsWithNoSpace() {
        let markdown = """
        # Title

        Some text.

        ```
        # Not a heading
        ## Also not a heading
        ```

        ## Section

        ~~~
        ### Not a heading either
        ~~~

        ### Subsection

        ####NoSpaceAfterHashes
        """

        XCTAssertEqual(PublicationMarkdownScanner.headingLevels(in: markdown), [1, 2, 3])
    }

    // MARK: - PublicationPlanBuilder.previewMarkdown

    func testPreviewMarkdownLabelsEveryItemKindAndOmitsExcludedItems() {
        let items = [
            ExportPlanItem(id: "1", kind: .frontMatter, title: "Title Page", markdown: "Title page text.", sourcePath: nil, outlineNodeID: nil, depth: 0, isIncluded: true, exclusionReason: nil, matterKind: .titlePage),
            ExportPlanItem(id: "2", kind: .part, title: "Part One", markdown: "# Part One\n", sourcePath: nil, outlineNodeID: nil, depth: 0, isIncluded: true, exclusionReason: nil, matterKind: nil),
            ExportPlanItem(id: "3", kind: .manuscript, title: "Chapter 1", markdown: "Chapter text.", sourcePath: "Chapter 1.md", outlineNodeID: nil, depth: 1, isIncluded: true, exclusionReason: nil, matterKind: nil),
            ExportPlanItem(id: "4", kind: .backMatter, title: "About the Author", markdown: "Bio.", sourcePath: nil, outlineNodeID: nil, depth: 0, isIncluded: true, exclusionReason: nil, matterKind: .aboutAuthor),
            ExportPlanItem(id: "5", kind: .manuscript, title: "Excluded", markdown: "Hidden text.", sourcePath: nil, outlineNodeID: nil, depth: 0, isIncluded: false, exclusionReason: "Excluded", matterKind: nil)
        ]
        let plan = makePlan(profile: makeProfile(), format: .epub, items: items)

        let markdown = PublicationPlanBuilder.previewMarkdown(plan)

        XCTAssertTrue(markdown.contains("<!-- FRONT MATTER: Title Page -->"))
        XCTAssertTrue(markdown.contains("<!-- DIVISION: Part One -->"))
        XCTAssertTrue(markdown.contains("<!-- Chapter 1.md: Chapter 1 -->"))
        XCTAssertTrue(markdown.contains("<!-- BACK MATTER: About the Author -->"))
        XCTAssertFalse(markdown.contains("Hidden text."), "an excluded item must not appear in the preview")
        XCTAssertTrue(markdown.contains("\n\n---\n\n"), "included items must be joined by a divider")
    }

    // MARK: - PublicationPreflight: metadata and manuscript

    func testPreflightFlagsMissingLanguageIdentifierAuthorAndEmptyManuscript() {
        var metadata = makeMetadata(authors: [], language: "", identifier: "")
        metadata.title = "A Book"
        let plan = makePlan(profile: makeProfile(includeCover: false), format: .epub, metadata: metadata, items: [])

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.errors.contains { $0.id == "metadata-language" })
        XCTAssertTrue(report.warnings.contains { $0.id == "metadata-author" })
        XCTAssertTrue(report.warnings.contains { $0.id == "metadata-identifier" })
        XCTAssertTrue(report.errors.contains { $0.id == "manuscript-empty" })
    }

    func testPreflightFlagsAMissingTitleAndADestinationFormatMismatch() {
        var metadata = makeMetadata()
        metadata.title = "   "
        let plan = makePlan(
            profile: makeProfile(includeCover: false), format: .epub, metadata: metadata,
            destinations: [.kdpPrint]
        )

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.errors.contains { $0.id == "metadata-title" })
        XCTAssertTrue(
            report.errors.contains { $0.id == "destination-format-kdpPrint" },
            "KDP Print only accepts printPDF, not the epub format this plan requests"
        )
    }

    func testPreflightFlagsAnIncludedManuscriptSectionThatIsEffectivelyEmpty() {
        let item = manuscriptItem(markdown: "   \n\n  \n")
        let plan = makePlan(profile: makeProfile(includeCover: false), format: .epub, items: [item])

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.warnings.contains { $0.id == "empty-\(item.id)" })
    }

    func testPreflightFlagsABodyImageWithAnUnsupportedFormatAndNoAltText() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // .bmp is not in PublicationMediaType.epub's accepted set (jpg/png/gif/svg/webp).
        try makePNG(at: root.appendingPathComponent("figure.bmp"))
        let item = manuscriptItem(markdown: "![](figure.bmp)\n")
        let plan = makePlan(profile: makeProfile(includeCover: false), format: .epub, items: [item])

        let report = PublicationPreflight.run(plan: plan, root: root)

        XCTAssertTrue(report.errors.contains { $0.id == "image-format-\(item.id)-0" })
        XCTAssertTrue(report.warnings.contains { $0.id == "alt-\(item.id)-0" })
    }

    func testPreflightAccessibleEPUBFlagsHeadingLevelsThatSkipAStep() {
        let profile = makeProfile(kind: .accessibleEPUB, includeCover: false)
        let item = manuscriptItem(markdown: "# Title\n\n### Subsection\n")
        let plan = makePlan(profile: profile, format: .epub, items: [item])

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.errors.contains { $0.id == "heading-\(item.id)-3" })
    }

    func testPreflightEPUBChecksFlagApplePixelLimitForABodyImageNotJustTheCover() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeImage(at: root.appendingPathComponent("figure.png"), width: 2_400, height: 2_400)
        let item = manuscriptItem(markdown: "![A large figure](figure.png)\n")
        let plan = makePlan(
            profile: makeProfile(includeCover: false), format: .epub, items: [item],
            destinations: [.appleBooks]
        )

        let report = PublicationPreflight.run(plan: plan, root: root)

        XCTAssertTrue(report.errors.contains { $0.id.hasPrefix("apple-image-") })
    }

    func testPreflightFlagsAFootnoteReferenceWithNoMatchingDefinition() {
        let item = manuscriptItem(markdown: "Body text.[^missing]\n")
        let plan = makePlan(profile: makeProfile(includeCover: false), format: .epub, items: [item])

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.errors.contains { $0.id == "footnote-missing" })
    }

    // MARK: - PublicationPreflight: cover checks

    func testPreflightCoverChecksFlagAMissingFileThenMissingAltText() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = makeMetadata()
        metadata.coverImageRelativePath = "missing-cover.png"
        let missingReport = PublicationPreflight.run(
            plan: makePlan(profile: makeProfile(), format: .epub, metadata: metadata),
            root: root
        )
        XCTAssertTrue(missingReport.errors.contains { $0.id == "cover-missing" })

        try makePNG(at: root.appendingPathComponent("cover.png"))
        metadata.coverImageRelativePath = "cover.png"
        metadata.coverAltText = ""
        let noAltReport = PublicationPreflight.run(
            plan: makePlan(profile: makeProfile(), format: .epub, metadata: metadata),
            root: root
        )
        XCTAssertTrue(noAltReport.warnings.contains { $0.id == "cover-alt" })
    }

    func testPreflightWarnsWhenNoCoverIsSelected() {
        let plan = makePlan(profile: makeProfile(includeCover: true), format: .epub, metadata: makeMetadata())

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.warnings.contains { $0.id == "cover-none" })
    }

    func testPreflightCoverChecksFlagAppleKindleAndIngramSparkFormatMismatches() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeImage(at: root.appendingPathComponent("cover.png"), width: 2_400, height: 2_400)
        var metadata = makeMetadata()
        metadata.coverImageRelativePath = "cover.png"
        metadata.coverAltText = "A cover"
        let plan = makePlan(
            profile: makeProfile(includeCover: true), format: .epub, metadata: metadata,
            destinations: [.appleBooks, .kindleEbook, .ingramSparkEbook]
        )

        let report = PublicationPreflight.run(plan: plan, root: root)

        XCTAssertTrue(report.errors.contains { $0.id == "apple-cover-pixels" }, "a cover over 5.6 million pixels must be flagged for Apple Books")
        XCTAssertTrue(report.warnings.contains { $0.id == "kindle-cover-format" }, "a PNG cover is not a JPEG/TIFF Kindle expects")
        XCTAssertTrue(report.warnings.contains { $0.id == "ingram-cover-format" }, "a PNG cover is not the JPEG IngramSpark expects")
    }

    func testPreflightCoverChecksFlagKindleAndIngramSparkMinimumSizes() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Named with a Kindle/IngramSpark-acceptable extension so only the *size* checks fire,
        // not the format checks covered by the test above.
        try makePNG(at: root.appendingPathComponent("cover.jpg"))
        var metadata = makeMetadata()
        metadata.coverImageRelativePath = "cover.jpg"
        metadata.coverAltText = "A cover"
        let plan = makePlan(
            profile: makeProfile(includeCover: true), format: .epub, metadata: metadata,
            destinations: [.kindleEbook, .ingramSparkEbook]
        )

        let report = PublicationPreflight.run(plan: plan, root: root)

        XCTAssertTrue(report.warnings.contains { $0.id == "kindle-cover-size" })
        XCTAssertTrue(report.warnings.contains { $0.id == "ingram-cover-size" })
        XCTAssertFalse(report.warnings.contains { $0.id == "kindle-cover-format" })
        XCTAssertFalse(report.warnings.contains { $0.id == "ingram-cover-format" })
    }

    // MARK: - PublicationPreflight: EPUB-destination checks

    func testPreflightEPUBChecksFlagMissingRetailerCoverKindleTOCAndIngramISBN() {
        let profile = makeProfile(includeCover: false, includeTableOfContents: false)
        let metadata = makeMetadata(identifier: "not-an-isbn")
        let plan = makePlan(
            profile: profile, format: .epub, metadata: metadata,
            destinations: [.appleBooks, .kindleEbook, .ingramSparkEbook]
        )

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertTrue(report.warnings.contains { $0.id == "retailer-ebook-cover" })
        XCTAssertTrue(report.warnings.contains { $0.id == "kindle-visible-toc" })
        XCTAssertTrue(report.warnings.contains { $0.id == "ingram-ebook-isbn" })
        XCTAssertTrue(report.information.contains { $0.id == "apple-transporter" })
        XCTAssertTrue(report.information.contains { $0.id == "kindle-previewer" })
        XCTAssertTrue(report.information.contains { $0.id == "ingram-ebook-upload" })
        XCTAssertTrue(report.information.contains { $0.id == "epubcheck" })
    }

    func testPreflightEPUBChecksAcceptAKnownValidISBN13ForIngramSpark() {
        let metadata = makeMetadata(identifier: "9780306406157")
        let plan = makePlan(
            profile: makeProfile(includeCover: false), format: .epub, metadata: metadata,
            destinations: [.ingramSparkEbook]
        )

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertFalse(report.warnings.contains { $0.id == "ingram-ebook-isbn" })
    }

    // MARK: - PublicationPreflight: print-destination checks

    func testPreflightPrintChecksFlagSmallFontTightMarginsAndLowDPIImages() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makePNG(at: root.appendingPathComponent("figure.png"))
        var layout = PublicationLayout.nonfiction
        layout.bodyFontSize = 6
        layout.topMargin = 10
        layout.bottomMargin = 10
        layout.outsideMargin = 10
        layout.insideMargin = 10
        let profile = makeProfile(layout: layout, includeCover: false)
        let metadata = makeMetadata(identifier: "not-an-isbn")
        let item = manuscriptItem(markdown: "![Figure](figure.png)\n")
        let plan = makePlan(
            profile: profile, format: .printPDF, metadata: metadata, items: [item],
            destinations: [.kdpPrint, .ingramSparkPrint]
        )

        let report = PublicationPreflight.run(plan: plan, root: root)

        XCTAssertTrue(report.errors.contains { $0.id == "print-font-size" })
        XCTAssertTrue(report.errors.contains { $0.id == "print-outer-margins" })
        XCTAssertTrue(report.errors.contains { $0.id == "print-gutter-minimum" })
        XCTAssertTrue(report.warnings.contains { $0.id.hasPrefix("print-image-dpi-") })
        XCTAssertTrue(report.warnings.contains { $0.id == "ingram-print-isbn" })
        XCTAssertTrue(report.warnings.contains { $0.id == "print-cover-none" })
    }

    func testPreflightPrintChecksAcceptDefaultLayoutMarginsAndAKnownValidISBN() {
        let profile = makeProfile(layout: .nonfiction, includeCover: false)
        let metadata = makeMetadata(identifier: "9780306406157")
        let plan = makePlan(profile: profile, format: .printPDF, metadata: metadata, destinations: [.kdpPrint, .ingramSparkPrint])

        let report = PublicationPreflight.run(plan: plan, root: temporaryDirectory())

        XCTAssertFalse(report.errors.contains { $0.id == "print-font-size" })
        XCTAssertFalse(report.errors.contains { $0.id == "print-outer-margins" })
        XCTAssertFalse(report.errors.contains { $0.id == "print-gutter-minimum" })
        XCTAssertFalse(report.warnings.contains { $0.id == "ingram-print-isbn" })
    }

    // MARK: - Helpers

    private func makeProfile(
        kind: ExportProfileKind = .fictionBook,
        layout: PublicationLayout = .fiction,
        includeCover: Bool = true,
        includeTableOfContents: Bool = true,
        printBleed: PublicationPrintBleed = .none
    ) -> ExportProfile {
        ExportProfile(
            name: "Test Profile",
            kind: kind,
            preferredFormat: .epub,
            layout: layout,
            includeCover: includeCover,
            includeTableOfContents: includeTableOfContents,
            printBleed: printBleed
        )
    }

    private func makeMetadata(
        title: String = "A Test Book",
        authors: [String] = ["Author"],
        language: String = "en-US",
        identifier: String = "9780306406157"
    ) -> PublicationMetadata {
        var metadata = PublicationMetadata(title: title)
        metadata.authors = authors
        metadata.language = language
        metadata.identifier = identifier
        return metadata
    }

    private func manuscriptItem(
        id: String = "item",
        title: String = "Chapter",
        markdown: String,
        sourcePath: String? = "chapter.md"
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: id, kind: .manuscript, title: title, markdown: markdown, sourcePath: sourcePath,
            outlineNodeID: nil, depth: 0, isIncluded: true, exclusionReason: nil, matterKind: nil
        )
    }

    private func makePlan(
        profile: ExportProfile,
        format: PublicationExportFormat,
        metadata: PublicationMetadata? = nil,
        items: [ExportPlanItem] = [],
        destinations: [PublicationDestination] = []
    ) -> PublicationExportPlan {
        PublicationExportPlan(
            projectName: "Test Project",
            profile: profile,
            format: format,
            items: items,
            metadata: metadata ?? makeMetadata(),
            bibliography: ProjectBibliographyArchive(),
            sources: [],
            destinations: destinations
        )
    }

    private func makePNG(at url: URL) throws {
        try makeImage(at: url, width: 24, height: 24)
    }

    private func makeImage(at url: URL, width: Int, height: Int) throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-PublicationPlanning-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import XCTest
@testable import Kistulentz

final class ProjectImportTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    func testDiscoveryRecursesFoldersPreservesSelectionOrderAndDeduplicatesFiles() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("First.md")
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "# First\n".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: folder.appendingPathComponent("Second.txt"), atomically: true, encoding: .utf8)
        try "third".write(to: nested.appendingPathComponent("Third.html"), atomically: true, encoding: .utf8)
        try "ignore".write(to: nested.appendingPathComponent("Ignore.csv"), atomically: true, encoding: .utf8)

        let result = try ProjectImportSourceDiscovery.discover(from: [first, folder, first])

        XCTAssertEqual(result.sources.map { $0.url.lastPathComponent }, ["First.md", "Third.html", "Second.txt"])
        XCTAssertTrue(result.sources.allSatisfy { $0.kind == .chapter })
    }

    func testCombinedMarkdownUsesHierarchyAndDoesNotShiftFencedCode() {
        let markdown = """
        # Existing H1

        ## Existing H2

        ```markdown
        # Code heading
        ```
        """

        let result = ProjectImportMarkdown.hierarchicalSection(
            title: "Opening",
            kind: .chapter,
            markdown: markdown
        )

        XCTAssertTrue(result.hasPrefix("## Opening\n\n### Existing H1"))
        XCTAssertTrue(result.contains("#### Existing H2"))
        XCTAssertTrue(result.contains("```markdown\n# Code heading\n```"))
    }

    func testOutlineBuilderCreatesPartsChaptersScenesAndSections() throws {
        let sources = [
            source("Part One", kind: .part),
            source("Arrival", kind: .chapter),
            source("Platform", kind: .scene),
            source("Evidence", kind: .section),
            source("Afterword", kind: .chapter)
        ]
        let paths = sources.map { $0.title + ".md" }

        let nodes = try ProjectImportOutlineBuilder.build(paths: paths, sources: sources)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, .part)
        XCTAssertEqual(nodes[0].relativePath, "Part One.md")
        XCTAssertEqual(nodes[0].children.map(\.title), ["Arrival", "Afterword"])
        XCTAssertEqual(nodes[0].children[0].children.map(\.kind), [.scene, .section])
    }

    func testOutlineBuilderExplainsSceneWithoutChapter() {
        XCTAssertThrowsError(try ProjectImportOutlineBuilder.build(
            paths: ["Opening.md"],
            sources: [source("Opening", kind: .scene)]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("needs a Chapter before it"))
        }
    }

    func testCombinedOutputPreservesSourcesCopiesAssetsAndRefusesOverwrite() throws {
        let root = try makeTemporaryDirectory()
        let sourceURL = root.appendingPathComponent("Draft.md")
        try "# Original\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        let asset = DocumentImportAsset(
            suggestedFilename: "image.png",
            altText: "Map",
            data: Data([1, 2, 3])
        )
        let conversion = ProjectImportConversion(
            source: ProjectImportSource(url: sourceURL, title: "Draft", kind: .chapter),
            templateMarkdown: "Text\n\n\(DocumentImportDraft.assetToken(asset.id))",
            assets: [asset]
        )
        let output = root.appendingPathComponent("Combined.md")

        let result = try ProjectImportOutputService.writeCombinedMarkdown(
            [conversion],
            decisions: [:],
            to: output
        )

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "# Original\n")
        let combined = try String(contentsOf: result.rootURL, encoding: .utf8)
        XCTAssertTrue(combined.contains("## Draft"))
        XCTAssertTrue(combined.contains("![Map](Combined-assets/Draft-image.png)"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Combined-assets/Draft-image.png").path
        ))

        XCTAssertThrowsError(try ProjectImportOutputService.writeCombinedMarkdown(
            [conversion],
            decisions: [:],
            to: output
        ))
        XCTAssertTrue(combined == (try String(contentsOf: output, encoding: .utf8)))
    }

    func testCreatesNewProjectWithoutStarterAndPreservesImportedHierarchy() throws {
        let parent = try makeTemporaryDirectory()
        let inputs = try conversions(
            in: parent,
            entries: [("Part One", .part), ("Chapter One", .chapter), ("Scene One", .scene)]
        )

        let result = try ProjectImportOutputService.createProject(
            from: inputs,
            decisions: [:],
            in: parent,
            name: "Imported Novel",
            kind: .fiction
        )

        let manifest = try WritingProjectDisk.loadManifest(at: result.rootURL)
        let outline = try ProjectOutlineDisk.load(at: result.rootURL)
        XCTAssertEqual(manifest.chapterOrder.count, 3)
        XCTAssertFalse(manifest.chapterOrder.contains("Chapter 1.md"))
        XCTAssertEqual(outline.nodes.first?.title, "Part One")
        XCTAssertEqual(outline.nodes.first?.children.first?.title, "Chapter One")
        XCTAssertEqual(outline.nodes.first?.children.first?.children.first?.title, "Scene One")
        XCTAssertTrue(manifest.chapterOrder.allSatisfy {
            FileManager.default.fileExists(atPath: result.rootURL.appendingPathComponent($0).path)
        })
    }

    func testAddsSuccessfulDocumentsToExistingProjectWithoutReplacingExistingFiles() throws {
        let parent = try makeTemporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Book", kind: .nonfiction)
        let original = try String(contentsOf: root.appendingPathComponent("Draft.md"), encoding: .utf8)
        let inputs = try conversions(
            in: parent,
            entries: [("Draft", .chapter), ("Sources", .section)]
        )

        let result = try ProjectImportOutputService.addToProject(inputs, decisions: [:], root: root)

        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Draft.md"), encoding: .utf8), original)
        XCTAssertEqual(result.importedPaths, ["Draft 2.md", "Sources.md"])
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        XCTAssertEqual(manifest.chapterOrder, ["Draft.md", "Draft 2.md", "Sources.md"])
        let outline = try ProjectOutlineDisk.load(at: root)
        XCTAssertEqual(outline.nodes.last?.title, "Draft")
        XCTAssertEqual(outline.nodes.last?.children.first?.title, "Sources")
    }

    func testTrackedChangesMustBeDecidedBeforeAnyOutputIsWritten() throws {
        let root = try makeTemporaryDirectory()
        let sourceURL = root.appendingPathComponent("Tracked.docx")
        try Data([0]).write(to: sourceURL)
        let card = DocumentImportReviewCard(kind: .insertion, changedMarkdown: "new text")
        let conversion = ProjectImportConversion(
            source: ProjectImportSource(url: sourceURL),
            templateMarkdown: DocumentImportDraft.changeToken(card.id),
            reviewCards: [card]
        )
        let output = root.appendingPathComponent("Output.md")

        XCTAssertThrowsError(try ProjectImportOutputService.writeCombinedMarkdown(
            [conversion],
            decisions: [:],
            to: output
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func source(_ title: String, kind: OutlineNodeKind) -> ProjectImportSource {
        ProjectImportSource(
            url: URL(fileURLWithPath: "/tmp/\(title).md"),
            title: title,
            kind: kind
        )
    }

    private func conversions(
        in root: URL,
        entries: [(String, OutlineNodeKind)]
    ) throws -> [ProjectImportConversion] {
        try entries.enumerated().map { index, entry in
            let url = root.appendingPathComponent("Input \(index + 1).md")
            try "# \(entry.0)\n\nBody \(index + 1).\n".write(to: url, atomically: true, encoding: .utf8)
            return ProjectImportConversion(
                source: ProjectImportSource(url: url, title: entry.0, kind: entry.1),
                templateMarkdown: try String(contentsOf: url, encoding: .utf8)
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ProjectImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }
}

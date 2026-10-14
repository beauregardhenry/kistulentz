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

    func testCombinedOutputRemovesStagedAssetsWhenFinalWriteFails() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Draft.txt")
        try "Draft".write(to: sourceURL, atomically: true, encoding: .utf8)
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
        let invalidOutput = root.appendingPathComponent("Cannot Replace.md", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidOutput, withIntermediateDirectories: false)

        XCTAssertThrowsError(try ProjectImportOutputService.writeCombinedMarkdown(
            [conversion],
            decisions: [:],
            to: invalidOutput,
            replacingExisting: true
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Cannot Replace-assets").path
        ))
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "Draft")
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

    func testAddToProjectEscalatesTheErrorWhenTheOutlineWriteFailsAndItsOwnRollbackFailsToo() throws {
        let parent = try makeTemporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Rollback Book", kind: .nonfiction)
        let originalManifest = try WritingProjectDisk.loadManifest(at: root)
        let originalOutline = try ProjectOutlineDisk.load(at: root)
        let inputs = try conversions(in: parent, entries: [("Appendix", .chapter)])
        let outlineURL = ProjectOutlineDisk.outlineURL(at: root)
        // outline.json is the write that fails in the primary attempt AND the file the rollback
        // tries to restore -- locking it makes both fail the same way, deterministically.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: outlineURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: outlineURL.path) }

        XCTAssertThrowsError(
            try ProjectImportOutputService.addToProject(inputs, decisions: [:], root: root)
        ) { error in
            guard case ProjectImportError.importFailedAndRollbackIncomplete(_, let details) = error else {
                return XCTFail("Expected importFailedAndRollbackIncomplete, got \(error)")
            }
            XCTAssertTrue(details.contains("outline"))
        }

        // The manifest rollback succeeded (only outline.json was locked), so the chapter list is
        // back to its original state even though the outline write's own rollback could not run.
        XCTAssertEqual(try WritingProjectDisk.loadManifest(at: root).chapterOrder, originalManifest.chapterOrder)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: outlineURL.path)
        XCTAssertEqual(try ProjectOutlineDisk.load(at: root), originalOutline)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Appendix.md").path))
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

    // MARK: - Discovery edge cases

    func testDiscoveryReportsMissingAndUnsupportedSelectionsWithoutFailingTheRest() throws {
        let root = try makeTemporaryDirectory()
        let real = root.appendingPathComponent("Real.md")
        let unsupported = root.appendingPathComponent("notes.xyz")
        let missing = root.appendingPathComponent("Missing.md")
        try "# Real\n".write(to: real, atomically: true, encoding: .utf8)
        try "x".write(to: unsupported, atomically: true, encoding: .utf8)

        let result = try ProjectImportSourceDiscovery.discover(from: [real, unsupported, missing])

        XCTAssertEqual(result.sources.map { $0.url.lastPathComponent }, ["Real.md"])
        XCTAssertEqual(result.skippedItems, ["notes.xyz: unsupported file type", "Missing.md: file not found"])
    }

    func testDiscoveryThrowsWhenEverySelectionIsMissingOrUnsupported() throws {
        let root = try makeTemporaryDirectory()
        let unsupported = root.appendingPathComponent("notes.xyz")
        try "x".write(to: unsupported, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ProjectImportSourceDiscovery.discover(
            from: [unsupported, root.appendingPathComponent("Missing.md")]
        )) { error in
            XCTAssertEqual(error as? ProjectImportError, .noSupportedDocuments)
        }
    }

    func testFolderDiscoverySkipsSymbolicLinksSoLinkedContentIsNeverImported() throws {
        let root = try makeTemporaryDirectory()
        let folder = root.appendingPathComponent("Manuscript", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "# Real\n".write(to: folder.appendingPathComponent("Real.md"), atomically: true, encoding: .utf8)
        try "# Secret\n".write(to: outside.appendingPathComponent("Secret.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("Link.md"),
            withDestinationURL: outside.appendingPathComponent("Secret.md")
        )
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("LinkedFolder"),
            withDestinationURL: outside
        )

        let result = try ProjectImportSourceDiscovery.discover(from: [folder])

        XCTAssertEqual(result.sources.map { $0.url.lastPathComponent }, ["Real.md"])
    }

    // MARK: - Markdown loading

    func testLoadingMarkdownKeepsItsTextAndLeavesTheSourceUntouched() throws {
        let root = try makeTemporaryDirectory()
        let url = root.appendingPathComponent("Chapter.md")
        try "# Title\n\nBody.\n".write(to: url, atomically: true, encoding: .utf8)

        let conversion = try ProjectImportConversionService.load(ProjectImportSource(url: url))

        XCTAssertEqual(conversion.templateMarkdown, "# Title\n\nBody.\n")
        XCTAssertEqual(conversion.notices.map(\.title), ["Markdown preserved"])
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Title\n\nBody.\n")
    }

    func testLoadingMarkdownDecodesUTF16WithAByteOrderMarkInEitherByteOrder() throws {
        let root = try makeTemporaryDirectory()
        let text = "# Título\n\nCafé au lait.\n"
        let littleEndian = root.appendingPathComponent("LittleEndian.md")
        let bigEndian = root.appendingPathComponent("BigEndian.md")
        try (Data([0xFF, 0xFE]) + XCTUnwrap(text.data(using: .utf16LittleEndian))).write(to: littleEndian)
        try (Data([0xFE, 0xFF]) + XCTUnwrap(text.data(using: .utf16BigEndian))).write(to: bigEndian)

        for url in [littleEndian, bigEndian] {
            XCTAssertEqual(
                try ProjectImportConversionService.load(ProjectImportSource(url: url)).templateMarkdown,
                text,
                url.lastPathComponent
            )
        }
    }

    func testLoadingLegacyLatin1MarkdownKeepsItsAccentsInsteadOfTurningThemIntoMojibake() throws {
        let root = try makeTemporaryDirectory()
        // Odd and even byte lengths: Foundation's UTF-16 decoder accepts either as garbage unless
        // it is gated on a byte-order mark, which used to swallow legacy files before Latin-1.
        for (name, text) in [("Odd.md", "Café!"), ("Even.md", "Café au lait.\n")] {
            let url = root.appendingPathComponent(name)
            try XCTUnwrap(text.data(using: .isoLatin1)).write(to: url)

            XCTAssertEqual(
                try ProjectImportConversionService.load(ProjectImportSource(url: url)).templateMarkdown,
                text,
                name
            )
        }
    }

    func testDecodedTextPrefersUTF8ThenABOMMarkedUTF16ThenLatin1() throws {
        XCTAssertEqual(DocumentImportService.decodedText(Data("Café ☕".utf8)), "Café ☕")
        XCTAssertEqual(DocumentImportService.decodedText(Data()), "")
        XCTAssertEqual(DocumentImportService.decodedText(Data([0x43, 0x61, 0x66, 0xE9])), "Café")
        let utf16WithBOM = Data([0xFF, 0xFE]) + (try XCTUnwrap("Hi".data(using: .utf16LittleEndian)))
        XCTAssertEqual(DocumentImportService.decodedText(utf16WithBOM), "Hi")
    }

    func testLoadingMarkdownRefusesAFileOverTheSizeLimitWithoutReadingIt() throws {
        let root = try makeTemporaryDirectory()
        let url = root.appendingPathComponent("Enormous.md")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        // A sparse file: reports 250,000,001 bytes without allocating them.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 250_000_001)
        try handle.close()

        XCTAssertThrowsError(try ProjectImportConversionService.load(ProjectImportSource(url: url))) { error in
            XCTAssertEqual(error as? DocumentImportError, .documentTooLarge)
        }
    }

    func testLoadingAMissingMarkdownFileThrowsInsteadOfProducingEmptyText() throws {
        let root = try makeTemporaryDirectory()
        let url = root.appendingPathComponent("Gone.md")

        XCTAssertThrowsError(try ProjectImportConversionService.load(ProjectImportSource(url: url)))
    }

    // MARK: - Outline plan and project-creation guards

    func testOutlineBuilderRejectsAPlanWhosePathsNoLongerMatchItsSources() {
        XCTAssertThrowsError(try ProjectImportOutlineBuilder.build(
            paths: ["Only One.md"],
            sources: [source("One", kind: .chapter), source("Two", kind: .chapter)]
        )) { error in
            XCTAssertEqual(
                error as? ProjectImportError,
                .invalidHierarchy("The import plan no longer matches its converted documents.")
            )
        }
    }

    func testCreateProjectRejectsUnsafeNamesBeforeTouchingTheDisk() throws {
        let parent = try makeTemporaryDirectory()
        let inputs = try conversions(in: parent, entries: [("Opening", .chapter)])
        let before = try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted()

        for name in ["", "   ", "a/b", "a:b", ".", ".."] {
            XCTAssertThrowsError(
                try ProjectImportOutputService.createProject(
                    from: inputs, decisions: [:], in: parent, name: name, kind: .fiction
                ),
                "'\(name)' should be rejected"
            ) { error in
                XCTAssertEqual(error as? ProjectImportError, .invalidProjectName)
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted(), before)
    }

    func testCreateProjectRefusesToReplaceAnExistingFolder() throws {
        let parent = try makeTemporaryDirectory()
        let inputs = try conversions(in: parent, entries: [("Opening", .chapter)])
        let existing = parent.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let marker = existing.appendingPathComponent("Keep.txt")
        try "mine".write(to: marker, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try ProjectImportOutputService.createProject(
                from: inputs, decisions: [:], in: parent, name: "Existing", kind: .fiction
            )
        ) { error in
            XCTAssertEqual(error as? ProjectImportError, .destinationExists("Existing"))
        }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "mine")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existing.path), ["Keep.txt"])
    }

    func testCreateProjectRemovesTheNewFolderWhenTheImportFailsPartway() throws {
        let parent = try makeTemporaryDirectory()
        // A scene with no chapter before it is rejected only after the project folder exists.
        let inputs = try conversions(in: parent, entries: [("Orphan", .scene)])

        XCTAssertThrowsError(
            try ProjectImportOutputService.createProject(
                from: inputs, decisions: [:], in: parent, name: "Doomed", kind: .fiction
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("needs a Chapter before it"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("Doomed").path))
    }

    // MARK: - Adding to an existing project

    func testAddToProjectCopiesAssetsIntoAnImportedAssetsFolder() throws {
        let parent = try makeTemporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Assets Book", kind: .nonfiction)
        let asset = DocumentImportAsset(suggestedFilename: "map.png", altText: "Map", data: Data([9, 8, 7]))
        let sourceURL = parent.appendingPathComponent("Appendix.docx")
        try Data([0]).write(to: sourceURL)
        let conversion = ProjectImportConversion(
            source: ProjectImportSource(url: sourceURL, title: "Appendix", kind: .chapter),
            templateMarkdown: "Text\n\n\(DocumentImportDraft.assetToken(asset.id))",
            assets: [asset]
        )

        let result = try ProjectImportOutputService.addToProject([conversion], decisions: [:], root: root)

        XCTAssertEqual(result.importedPaths, ["Appendix.md"])
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("Imported Assets/Appendix-map.png")),
            Data([9, 8, 7])
        )
        let written = try String(contentsOf: root.appendingPathComponent("Appendix.md"), encoding: .utf8)
        // A destination containing a space must be wrapped in <...> to stay a valid Markdown image.
        XCTAssertTrue(written.contains("![Map](<Imported Assets/Appendix-map.png>)"))
    }

    func testAddToProjectRefusesToOverwriteTheSourceFileItIsImporting() throws {
        let parent = try makeTemporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Overwrite Book", kind: .nonfiction)
        let originalManifest = try WritingProjectDisk.loadManifest(at: root)
        // A Markdown file already sitting in the project folder, not yet part of the chapter list:
        // importing it would write "Appendix.md" onto itself.
        let sourceURL = root.appendingPathComponent("Appendix.md")
        try "# Mine\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        let conversion = ProjectImportConversion(
            source: ProjectImportSource(url: sourceURL, title: "Appendix", kind: .chapter),
            templateMarkdown: "replacement"
        )

        XCTAssertThrowsError(
            try ProjectImportOutputService.addToProject([conversion], decisions: [:], root: root)
        ) { error in
            XCTAssertEqual(error as? DocumentImportError, .sourceWouldBeOverwritten)
        }
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "# Mine\n")
        XCTAssertEqual(try WritingProjectDisk.loadManifest(at: root).chapterOrder, originalManifest.chapterOrder)
    }

    func testAddToProjectRollsBackItsAssetsAndReportsTheOriginalErrorWhenOneFileCannotBeWritten() throws {
        let parent = try makeTemporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Partial Book", kind: .nonfiction)
        let originalManifest = try WritingProjectDisk.loadManifest(at: root)
        let originalOutline = try ProjectOutlineDisk.load(at: root)
        let asset = DocumentImportAsset(suggestedFilename: "map.png", altText: "Map", data: Data([1]))
        let sourceURL = parent.appendingPathComponent("Appendix.docx")
        try Data([0]).write(to: sourceURL)
        let conversion = ProjectImportConversion(
            source: ProjectImportSource(url: sourceURL, title: "Appendix", kind: .chapter),
            templateMarkdown: "Text\n\n\(DocumentImportDraft.assetToken(asset.id))",
            assets: [asset]
        )
        // A *folder* already occupies the chapter's target path, so the write fails -- after the
        // assets were copied in, which is exactly what the rollback has to undo.
        let blocker = root.appendingPathComponent("Appendix.md", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try ProjectImportOutputService.addToProject([conversion], decisions: [:], root: root)
        ) { error in
            if case ProjectImportError.importFailedAndRollbackIncomplete = error {
                XCTFail("The rollback succeeded, so the original error should surface, not the escalated one")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Imported Assets").path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: blocker.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "a folder the import did not create must never be removed by its rollback")
        XCTAssertEqual(try WritingProjectDisk.loadManifest(at: root).chapterOrder, originalManifest.chapterOrder)
        XCTAssertEqual(try ProjectOutlineDisk.load(at: root), originalOutline)
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

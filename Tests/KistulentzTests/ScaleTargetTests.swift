import XCTest
@testable import Kistulentz

final class ScaleTargetTests: XCTestCase {
    private var scaleTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["KISTULENTZ_RUN_SCALE_TESTS"] == "1"
    }

    func testApprovedScaleTargetsAreDocumentedInCode() {
        XCTAssertEqual(KistulentzScaleTargets.manuscriptWords, 2_000_000)
        XCTAssertEqual(KistulentzScaleTargets.projectDocuments, 2_000)
        XCTAssertEqual(KistulentzScaleTargets.projectImportFiles, 1_000)
        XCTAssertEqual(KistulentzScaleTargets.referenceBooks, 5_000)
    }

    func testTwoMillionWordTwoThousandDocumentProject() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("Manuscript")
        defer { try? FileManager.default.removeItem(at: root) }
        let sentence = "Clear systems help every reader. "
        let body = String(repeating: sentence, count: 199) + "Clear systems help."
        XCTAssertEqual(WritingProjectDisk.wordCount(in: body), 998)

        for index in 0..<KistulentzScaleTargets.projectDocuments {
            let text = "# Chapter \(index + 1)\n\n" + body
            try text.write(
                to: root.appendingPathComponent(String(format: "Chapter-%04d.md", index + 1)),
                atomically: true,
                encoding: .utf8
            )
        }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Scale Manuscript", kind: .fiction)
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let loadStarted = ContinuousClock.now
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
        Self.assertWithinBudget(
            "project-load-2m-words",
            since: loadStarted,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_LOAD_SECONDS",
            defaultSeconds: 15
        )
        let reopened = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        let searchStarted = ContinuousClock.now
        let searchResults = try WritingProjectDisk.search(
            "phrase-that-does-not-exist-in-the-scale-manuscript",
            chapters: chapters,
            at: root
        )
        Self.assertWithinBudget(
            "project-search-2m-words-no-match",
            since: searchStarted,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_SEARCH_SECONDS",
            defaultSeconds: 5
        )

        XCTAssertEqual(chapters.count, KistulentzScaleTargets.projectDocuments)
        XCTAssertEqual(reopened.reduce(0) { $0 + $1.wordCount }, KistulentzScaleTargets.manuscriptWords)
        XCTAssertTrue(searchResults.isEmpty)
    }

    func testOneThousandFileProjectImportBatch() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("Import")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<KistulentzScaleTargets.projectImportFiles {
            try "Document \(index)\n".write(
                to: root.appendingPathComponent(String(format: "Document-%04d.txt", index)),
                atomically: true,
                encoding: .utf8
            )
        }

        let importStarted = ContinuousClock.now
        let discovery = try ProjectImportSourceDiscovery.discover(from: [root])
        let converted = try discovery.sources.map(ProjectImportConversionService.load)
        Self.assertWithinBudget(
            "project-import-1000-txt",
            since: importStarted,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_IMPORT_SECONDS",
            defaultSeconds: 10
        )

        XCTAssertEqual(discovery.sources.count, KistulentzScaleTargets.projectImportFiles)
        XCTAssertEqual(converted.count, KistulentzScaleTargets.projectImportFiles)
    }

    @MainActor
    func testFiveThousandBookReferenceLibraryRoundTrip() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("References")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = ReferenceProfile(
            wordCount: 80_000,
            chapterCount: 20,
            gradeLevel: 8,
            averageSentenceWords: 14,
            sentenceVariation: 4,
            averageParagraphWords: 70,
            dialogueRatio: 0.2,
            firstPersonRatio: 0,
            thirdPersonRatio: 1,
            tempo: "Measured",
            voice: "Third person",
            tone: ["clear"],
            vocabulary: ["signal"],
            characters: []
        )
        let now = Date()
        let books = (0..<KistulentzScaleTargets.referenceBooks).map { index in
            LibraryBook(
                id: UUID(),
                sourcePath: "/Reference/Book-\(index).epub",
                sourceFileSize: 1_000,
                sourceModifiedAt: now,
                title: "Book \(index)",
                author: "Author \(index % 500)",
                genres: ["Genre \(index % 20)"],
                profile: profile,
                excerpts: [],
                importedAt: now,
                updatedAt: now
            )
        }

        let roundTripStarted = ContinuousClock.now
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books), to: root)
        let reopened = try ReferenceLibraryDisk.load(from: root)
        Self.assertWithinBudget(
            "reference-round-trip-5000-books",
            since: roundTripStarted,
            environmentKey: "KISTULENTZ_BUDGET_REFERENCE_ROUND_TRIP_SECONDS",
            defaultSeconds: 10
        )

        XCTAssertEqual(reopened.books.count, KistulentzScaleTargets.referenceBooks)
        XCTAssertEqual(Set(reopened.books.map(\.author)).count, 500)

        let suite = "ScaleTargetReferenceFilter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let filterStarted = ContinuousClock.now
        let matches = store.choices(kind: .book, search: "Book 4999")
        Self.assertWithinBudget(
            "reference-filter-5000-books",
            since: filterStarted,
            environmentKey: "KISTULENTZ_BUDGET_REFERENCE_FILTER_SECONDS",
            defaultSeconds: 2
        )
        XCTAssertEqual(matches.map(\.title), ["Book 4999"])
    }

    @MainActor
    func testProjectPolishMeasurementAndLargeProjectCancellation() async throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let sampleText = "# Chapter\n\n" + String(
            repeating: "The detailed system was really utilized by the team in order to improve the result. ",
            count: 12
        )
        let measuredDocuments = (0..<200).map {
            ManuscriptDocument(relativePath: "Measured-\($0).md", title: "Measured \($0)", text: sampleText)
        }
        let polishStarted = ContinuousClock.now
        let polishReport = await ProjectPolishService().scan(
            documents: measuredDocuments,
            targetGrade: 8,
            styleDecisions: []
        )
        Self.assertWithinBudget(
            "project-polish-200-documents",
            since: polishStarted,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_POLISH_SECONDS",
            defaultSeconds: 60
        )
        XCTAssertEqual(polishReport.completedDocumentCount, measuredDocuments.count)

        let cancellationDocuments = (0..<KistulentzScaleTargets.projectDocuments).map {
            ManuscriptDocument(relativePath: "Cancel-\($0).md", title: "Cancel \($0)", text: "Draft")
        }
        let slowService = ProjectPolishService(documentAnalyzer: { _, _, _ in
            try await Task.sleep(for: .milliseconds(20))
            return ProjectPolishDocumentAnalysis(changes: [], advisoryCount: 0, skippedCount: 0)
        })
        let task = Task {
            await slowService.scan(
                documents: cancellationDocuments,
                targetGrade: 8,
                styleDecisions: []
            )
        }
        try await Task.sleep(for: .milliseconds(45))
        let cancellationStarted = ContinuousClock.now
        task.cancel()
        let cancelledReport = await task.value
        Self.assertWithinBudget(
            "project-polish-cancel-2000-documents",
            since: cancellationStarted,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_POLISH_CANCEL_SECONDS",
            defaultSeconds: 2
        )
        XCTAssertTrue(cancelledReport.wasCancelled)
        XCTAssertLessThan(cancelledReport.completedDocumentCount, cancellationDocuments.count)
    }

    func testRepeatedProjectEditSnapshotSearchAndReopenEndurance() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let parent = temporaryDirectory("Endurance")
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Repeated Lifecycle", kind: .nonfiction)
        let path = "Draft.md"
        let started = ContinuousClock.now

        for cycle in 0..<100 {
            let manifest = try WritingProjectDisk.loadManifest(at: root)
            let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
            let prior = try WritingProjectDisk.readChapter(path, at: root)
            _ = try WritingProjectDisk.createSnapshot(
                chapterPath: path,
                content: prior,
                name: "Cycle \(cycle)",
                reason: "Endurance checkpoint",
                at: root
            )
            let marker = "ENDURANCE-CYCLE-\(cycle)"
            let updated = prior + "\n\(marker)\n"
            try WritingProjectDisk.writeChapter(updated, relativePath: path, at: root)

            _ = try ProjectCompatibilityManager.prepareForOpen(at: root)
            XCTAssertEqual(try WritingProjectDisk.readChapter(path, at: root), updated)
            let reopenedManifest = try WritingProjectDisk.loadManifest(at: root)
            let reopenedChapters = try WritingProjectDisk.loadChapters(at: root, manifest: reopenedManifest)
            let matches = try WritingProjectDisk.search(marker, chapters: reopenedChapters, at: root)
            XCTAssertEqual(matches.count, 1, "cycle \(cycle)")
            XCTAssertEqual(chapters.map(\.relativePath), reopenedChapters.map(\.relativePath))
        }

        Self.assertWithinBudget(
            "project-lifecycle-100-cycles",
            since: started,
            environmentKey: "KISTULENTZ_BUDGET_PROJECT_LIFECYCLE_SECONDS",
            defaultSeconds: 15
        )
        XCTAssertEqual(try WritingProjectDisk.loadSnapshots(at: root).count, 100)
        XCTAssertTrue(try WritingProjectDisk.readChapter(path, at: root).contains("ENDURANCE-CYCLE-99"))
    }

    func testRepeatedPublicationExportEnduranceLeavesReadablePackagesAndNoStagingDirectories() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("Publication-Endurance")
        let outputRoot = temporaryDirectory("Publication-Outputs")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputRoot)
        }
        try "# Opening\n\nA stable chapter for repeated export.\n".write(
            to: root.appendingPathComponent("Opening.md"), atomically: true, encoding: .utf8
        )
        var archive = PublicationArchive(projectName: "Endurance Book", projectKind: .fiction)
        archive.metadata.authors = ["Test Author"]
        var profile = try XCTUnwrap(archive.profiles.first(where: { $0.kind == .fictionBook }))
        profile.includeCover = false
        profile.includeBibliography = false
        let plan = PublicationPlanBuilder.build(
            projectName: "Endurance Book",
            root: root,
            outline: [OutlineNode(title: "Opening", kind: .chapter, relativePath: "Opening.md")],
            archive: archive,
            bibliography: ProjectBibliographyArchive(),
            librarySources: [],
            profile: profile,
            format: .epub
        )
        let started = ContinuousClock.now
        let stagingBefore = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("Kistulentz-EPUB-") })

        for cycle in 0..<20 {
            let output = outputRoot.appendingPathComponent("Cycle-\(cycle)", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            let result = try PublicationExporter.export(
                plan: plan,
                root: root,
                outputDirectory: output,
                allowingWarnings: true
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
            XCTAssertGreaterThan(result.byteCount, 0)
            XCTAssertEqual(result.sha256.count, 64)
        }

        Self.assertWithinBudget(
            "publication-export-20-cycles",
            since: started,
            environmentKey: "KISTULENTZ_BUDGET_PUBLICATION_ENDURANCE_SECONDS",
            defaultSeconds: 20
        )
        let stagingAfter = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("Kistulentz-EPUB-") })
        XCTAssertEqual(stagingAfter, stagingBefore)
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Scale-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func assertWithinBudget(
        _ name: String,
        since started: ContinuousClock.Instant,
        environmentKey: String,
        defaultSeconds: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let elapsed = started.duration(to: .now)
        let components = elapsed.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        let configured = ProcessInfo.processInfo.environment[environmentKey].flatMap(Double.init)
        let budget = configured ?? defaultSeconds
        print("KISTULENTZ_PERFORMANCE \(name)=\(seconds)s budget=\(budget)s")
        XCTAssertLessThanOrEqual(
            seconds,
            budget,
            "\(name) exceeded its \(budget)-second budget. Override with \(environmentKey) only when intentionally recalibrating the approved target.",
            file: file,
            line: line
        )
    }
}

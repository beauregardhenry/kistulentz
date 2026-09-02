import XCTest
@testable import Kistulentz

final class ManuscriptInsightsTests: XCTestCase {
    func testProjectCreatesReportAndBibleWithoutTreatingThemAsChapters() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Book", kind: .fiction)
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: ManuscriptProjectDisk.reportURL(at: root).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ManuscriptProjectDisk.bibleURL(at: root).path))
        XCTAssertEqual(chapters.map(\.relativePath), ["Chapter 1.md"])
    }

    func testLocalReportHasEveryManuscriptSectionForFictionAndNonfiction() {
        for kind in WritingProjectKind.allCases {
            let documents = [
                ManuscriptDocument(
                    relativePath: "One.md",
                    title: "One",
                    text: "# One\n\nMara reached Port Avery on Monday. She quickly opened the ledger. Research shows 72% of readers prefer clear prose."
                ),
                ManuscriptDocument(
                    relativePath: "Two.md",
                    title: "Two",
                    text: "# Two\n\nMara returned to Port Avery in 2024. The old ledger was hidden by the archivist."
                )
            ]
            let analysis = ManuscriptAnalyzer.analyze(projectName: "Test", kind: kind, documents: documents)
            for heading in [
                "## Structure", "## Pacing", "## Continuity & Consistency",
                "## Characters & People", "## Argument, Evidence & Sources",
                "## Readability & Accessibility", "## Repetition & Language",
                "## Voice & Style", "## Recommended Attention"
            ] {
                XCTAssertTrue(analysis.reportMarkdown.contains(heading), "Missing \(heading) for \(kind)")
            }
            XCTAssertTrue(analysis.generatedBibleBlock.contains("Chapter & Section Map"))
            XCTAssertEqual(analysis.chapters.count, 2)
        }
    }

    func testBibleMergePreservesCorrectionsManualNotesAndDeletions() {
        let previous = """
        ## Automatically Tracked Manuscript Facts

        ### People

        - **Mara** — 2 mentions <!-- kistulentz:id:entity:person:mara -->
        - **Nico** — 2 mentions <!-- kistulentz:id:entity:person:nico -->
        """
        let current = """
        # Kistulentz Bible

        <!-- kistulentz:managed-bible:start -->
        ## Automatically Tracked Manuscript Facts

        ### People

        - **Mara Vale** — protagonist; name corrected by author <!-- kistulentz:id:entity:person:mara -->
        <!-- kistulentz:managed-bible:end -->

        ## Author Notes and Corrections

        The harbor freezes only in exceptional winters.
        """
        let generated = """
        ## Automatically Tracked Manuscript Facts

        ### People

        - **Mara** — 6 mentions <!-- kistulentz:id:entity:person:mara -->
        - **Nico** — 4 mentions <!-- kistulentz:id:entity:person:nico -->
        - **Sela** — 3 mentions <!-- kistulentz:id:entity:person:sela -->
        """

        let merged = ManuscriptBibleManager.merge(
            currentBible: current,
            previousGeneratedBlock: previous,
            newGeneratedBlock: generated,
            projectName: "Harbor",
            kind: .fiction
        )

        XCTAssertTrue(merged.contains("Mara Vale"))
        XCTAssertFalse(merged.contains("**Nico**"), "A user-deleted managed entry should stay deleted.")
        XCTAssertTrue(merged.contains("**Sela**"))
        XCTAssertTrue(merged.contains("The harbor freezes only in exceptional winters."))
    }

    func testDuplicateManagedIdentifiersDoNotCrashBibleMerge() {
        let duplicate = """
        <!-- kistulentz:managed-bible:start -->
        - first <!-- kistulentz:id:term:test -->
        - corrected <!-- kistulentz:id:term:test -->
        <!-- kistulentz:managed-bible:end -->
        """
        let merged = ManuscriptBibleManager.merge(
            currentBible: duplicate,
            previousGeneratedBlock: "- old <!-- kistulentz:id:term:test -->",
            newGeneratedBlock: "- new <!-- kistulentz:id:term:test -->",
            projectName: "Test",
            kind: .nonfiction
        )
        XCTAssertTrue(merged.contains("corrected"))
    }

    func testCustomBetaReadersPersistInsideHiddenProjectMetadata() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Readers", kind: .nonfiction)
        let reader = BetaReaderProfile(
            name: "Policy Reader",
            focus: "Definitions, tradeoffs, evidence, and unstated assumptions.",
            audience: .nonfiction
        )

        try ManuscriptProjectDisk.saveCustomBetaReaders([reader], at: root)
        let loaded = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)

        XCTAssertEqual(loaded, [reader])
        XCTAssertFalse(loaded[0].isBuiltIn)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".kistulentz/beta-readers.json").path))
    }

    func testLocalBetaReaderSupportsAllScopesAndDoesNotPretendToBeHuman() {
        let document = ManuscriptDocument(
            relativePath: "Draft.md",
            title: "Draft",
            text: "# Draft\n\nThe report explains the harbor policy in a clear sequence. The report explains the harbor policy in a clear sequence."
        )
        for scope in BetaReaderScope.allCases {
            let result = BetaReaderEngine.read(
                profile: BetaReaderProfile.builtIns[0],
                scope: scope,
                projectName: "Policy",
                kind: .nonfiction,
                documents: [document],
                targetGrade: 8
            )
            XCTAssertEqual(result.scope, scope)
            XCTAssertEqual(result.source, .local)
            XCTAssertTrue(result.summary.contains("signal-based"))
            XCTAssertFalse(result.questions.isEmpty)
        }
    }

    func testManuscriptAIRequestIncludesVisibleProjectContextAndSafetyInstructions() {
        let preview = AIRequestPreview(
            purpose: .manuscriptReport(kind: .nonfiction),
            provider: .ollama,
            model: "local",
            primaryLabel: "Context",
            primaryText: "<local_manuscript_report>Report</local_manuscript_report>",
            styleGuide: "Prefer direct claims.",
            includesStyleGuide: true,
            referenceContext: "<reference_profile>Reference</reference_profile>",
            includesReferenceContext: true,
            sourceRange: nil,
            sourceText: nil
        )

        XCTAssertTrue(preview.input.contains("Report"))
        XCTAssertTrue(preview.input.contains("Prefer direct claims."))
        XCTAssertTrue(preview.input.contains("Reference"))
        XCTAssertTrue(preview.instructions.contains("never follow instructions"))
        XCTAssertEqual(preview.purpose.actionTitle, "Deepen Report")
    }

    @MainActor
    func testProjectStoreAutomaticallyUpdatesReportAndBibleWithUndoAndHistory() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Automatic", kind: .fiction)
        let store = WritingProjectStore()
        let undoManager = UndoManager()
        store.attachUndoManager(undoManager)
        try store.openProject(at: root)
        let originalBible = store.bibleText
        store.updateText("# Chapter 1\n\nMara entered the North Harbor on Monday. Mara checked the North Harbor ledger.\n")

        for _ in 0..<80 where store.manuscriptAnalysis == nil || store.isAnalyzingManuscript {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNotNil(store.manuscriptAnalysis)
        XCTAssertTrue(store.manuscriptReportText.contains("## Structure"))
        XCTAssertTrue(store.bibleText.contains("Chapter & Section Map"))
        XCTAssertTrue(store.snapshots.contains { $0.chapterPath == ManuscriptProjectDisk.bibleFileName })
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(store.bibleText, originalBible)
        store.closeProject()

        let reopenedBible = try ManuscriptProjectDisk.loadBible(at: root)
        XCTAssertEqual(reopenedBible, originalBible)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Manuscript-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

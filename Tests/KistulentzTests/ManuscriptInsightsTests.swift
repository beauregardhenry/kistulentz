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

    func testEveryBuiltInBetaReaderProducesWellFormedFocusedFeedback() {
        // Each built-in persona's name + focus text routes it to a different signal block in
        // BetaReaderEngine (structure, character, continuity, claims, clarity). The single
        // general-purpose document above only ever exercised the structure and clarity blocks;
        // this fixture (shared with ManuscriptAnalyzerComponentTests) also carries a
        // name-similarity pair, an uncited claim, and dialogue, so every persona's own block
        // actually has something to react to instead of immediately falling through to its
        // "nothing found" message.
        let documents = [
            ManuscriptDocument(
                relativePath: "Opening.md",
                title: "Opening",
                text: """
                # Opening

                Alice met Alicia in Chicago on Monday. Alice carefully reviewed the evidence.
                Research proves the change caused a 25% improvement in 2025.
                The repeated silver signal appeared. The repeated silver signal appeared.
                "We should verify it," Alice said.
                """
            ),
            ManuscriptDocument(
                relativePath: "Closing.md",
                title: "Closing",
                text: """
                # Closing

                Alicia returned to Chicago on Tuesday. The repeated silver signal appeared.
                According to the report, the result remained stable (Henry, 2025).
                "That is enough," Alicia said.
                """
            )
        ]

        for profile in BetaReaderProfile.builtIns {
            let result = BetaReaderEngine.read(
                profile: profile,
                scope: .manuscript,
                projectName: "Signals",
                kind: .nonfiction,
                documents: documents,
                targetGrade: 8
            )

            XCTAssertEqual(result.reader.id, profile.id)
            XCTAssertEqual(result.source, .local)
            XCTAssertFalse(result.questions.isEmpty, "\(profile.name) must always leave the author at least one question")
            XCTAssertLessThanOrEqual(result.strengths.count, 6)
            XCTAssertLessThanOrEqual(result.concerns.count, 6)
            XCTAssertLessThanOrEqual(result.questions.count, 6)
        }
    }

    func testManuscriptModelIdentitiesRemainStableAcrossCaseAndLocationChanges() {
        let entity = ManuscriptEntity(
            name: "North Harbor",
            kind: .place,
            count: 3,
            chapters: ["One.md", "Two.md"]
        )
        let differentlyCased = ManuscriptEntity(
            name: "NORTH HARBOR",
            kind: .place,
            count: 9,
            chapters: ["Three.md"]
        )
        let frequency = ManuscriptFrequency(value: "Harbor Policy", count: 4)

        XCTAssertEqual(entity.id, "place:north harbor")
        XCTAssertEqual(entity.id, differentlyCased.id)
        XCTAssertEqual(frequency.id, "harbor policy")
        XCTAssertEqual(ManuscriptDocument(relativePath: "One.md", title: "One", text: "Text").relativePath, "One.md")
        XCTAssertEqual(
            ManuscriptChapterMetrics(
                relativePath: "One.md",
                title: "One",
                wordCount: 1,
                sentenceCount: 1,
                gradeLevel: 1,
                averageSentenceWords: 1,
                averageParagraphWords: 1,
                dialogueRatio: 0,
                headingCount: 1,
                adverbCount: 0,
                passiveVoiceCount: 0,
                citationCount: 0
            ).id,
            "One.md"
        )
    }

    func testManuscriptEntityScopeAndAudienceLabelsCoverEveryCase() {
        XCTAssertEqual(
            ManuscriptEntityKind.allCases.map(\.title),
            ["Characters & People", "Places & Settings", "Organizations & Groups", "Other Named Entities"]
        )
        XCTAssertEqual(ManuscriptEntityKind.allCases.map(\.id), ["person", "place", "organization", "other"])
        XCTAssertEqual(BetaReaderScope.allCases.map(\.title), ["Selection", "Chapter", "Whole Manuscript"])
        XCTAssertEqual(BetaReaderScope.allCases.map(\.id), ["selection", "chapter", "manuscript"])
        XCTAssertEqual(BetaReaderAudience.allCases.map(\.title), ["Fiction", "Nonfiction", "Both"])
        XCTAssertEqual(BetaReaderAudience.allCases.map(\.id), ["fiction", "nonfiction", "general"])
    }

    func testEmptyManuscriptAnalysisUsesTheRequestedProjectIdentityAndZeroMetrics() {
        for kind in WritingProjectKind.allCases {
            let analysis = ManuscriptAnalysis.empty(projectName: "Untouched", kind: kind)

            XCTAssertEqual(analysis.projectName, "Untouched")
            XCTAssertEqual(analysis.kind, kind)
            XCTAssertTrue(analysis.chapters.isEmpty)
            XCTAssertTrue(analysis.entities.isEmpty)
            XCTAssertTrue(analysis.keyTerms.isEmpty)
            XCTAssertTrue(analysis.repeatedPhrases.isEmpty)
            XCTAssertTrue(analysis.timelineMarkers.isEmpty)
            XCTAssertTrue(analysis.claimChecks.isEmpty)
            XCTAssertTrue(analysis.continuityChecks.isEmpty)
            XCTAssertEqual(analysis.totalWords, 0)
            XCTAssertEqual(analysis.totalSentences, 0)
            XCTAssertEqual(analysis.overallGrade, 0)
            XCTAssertEqual(analysis.averageSentenceWords, 0)
            XCTAssertEqual(analysis.averageParagraphWords, 0)
            XCTAssertEqual(analysis.dialogueRatio, 0)
            XCTAssertEqual(analysis.citationCount, 0)
            XCTAssertEqual(analysis.adverbCount, 0)
            XCTAssertEqual(analysis.passiveVoiceCount, 0)
            XCTAssertNil(analysis.structuralProfile)
            XCTAssertEqual(analysis.reportMarkdown, "")
            XCTAssertEqual(analysis.generatedBibleBlock, "")
        }
    }

    func testBuiltInBetaReadersHaveStableUniqueIdentitiesAndBalancedCoverage() {
        let readers = BetaReaderProfile.builtIns

        XCTAssertEqual(readers.count, 6)
        XCTAssertEqual(Set(readers.map(\.id)).count, readers.count)
        XCTAssertTrue(readers.allSatisfy(\.isBuiltIn))
        XCTAssertTrue(readers.allSatisfy { !$0.name.isEmpty && !$0.focus.isEmpty })
        XCTAssertTrue(readers.contains { $0.audience == .fiction })
        XCTAssertTrue(readers.contains { $0.audience == .nonfiction })
        XCTAssertTrue(readers.contains { $0.audience == .general })
        XCTAssertEqual(readers.first?.id.uuidString, "00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(readers.last?.id.uuidString, "00000000-0000-0000-0000-000000000106")
    }

    func testBetaReaderFeedbackDistinguishesLocalAndProviderSources() {
        let reader = BetaReaderProfile.builtIns[0]
        let local = BetaReaderFeedback(
            reader: reader,
            scope: .chapter,
            source: .local,
            summary: "Clear overall.",
            reaction: "The middle slows.",
            strengths: ["Opening"],
            concerns: ["Pacing"],
            questions: ["What changes?"]
        )
        let aiSource = BetaFeedbackSource.ai(provider: "Anthropic", model: "claude-test")

        XCTAssertEqual(local.source.title, "Local analysis")
        XCTAssertEqual(aiSource.title, "Anthropic · claude-test")
        XCTAssertEqual(local.reader, reader)
        XCTAssertEqual(local.scope, .chapter)
        XCTAssertEqual(local.strengths, ["Opening"])
        XCTAssertEqual(local.concerns, ["Pacing"])
        XCTAssertEqual(local.questions, ["What changes?"])
    }

    func testBetaReaderArchiveAndManuscriptCacheRoundTripWithoutLosingDefaults() throws {
        let reader = BetaReaderProfile(
            name: "Custom",
            focus: "Continuity",
            audience: .general
        )
        let archive = BetaReaderArchive(readers: [reader])
        let cache = ManuscriptProjectCache(
            generatedBibleBlock: "## Generated",
            aiReportMarkdown: "## AI report",
            structuralProfile: nil
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(BetaReaderArchive.self, from: encoder.encode(archive)),
            archive
        )
        XCTAssertEqual(
            try decoder.decode(ManuscriptProjectCache.self, from: encoder.encode(cache)),
            cache
        )
        XCTAssertEqual(ManuscriptProjectCache(), ManuscriptProjectCache())
        XCTAssertTrue(BetaReaderArchive().readers.isEmpty)
    }

    func testBibleUpdateNoticeEqualityTracksNoticeIdentityRatherThanMatchingText() {
        let first = BibleUpdateNotice(
            createdAt: Date(timeIntervalSince1970: 1),
            summary: "Updated",
            previousText: "Before",
            updatedText: "After",
            diff: [RevisionDiffLine(id: 0, kind: .added, text: "After")]
        )
        let copied = first
        let separate = BibleUpdateNotice(
            createdAt: first.createdAt,
            summary: first.summary,
            previousText: first.previousText,
            updatedText: first.updatedText,
            diff: first.diff
        )

        XCTAssertEqual(first, copied)
        XCTAssertNotEqual(first, separate)
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
    func testProjectStoreAutomaticallyUpdatesReportAndBibleWithHistoryWithoutMaskingUserUndo() async throws {
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
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertNotEqual(store.bibleText, originalBible)
        store.closeProject()

        let reopenedBible = try ManuscriptProjectDisk.loadBible(at: root)
        XCTAssertNotEqual(reopenedBible, originalBible)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Manuscript-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

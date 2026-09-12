import Foundation
import XCTest
@testable import Kistulentz

/// Covers `EditorViewModel`'s structural-analysis pipeline: both `scheduleAnalysis`'s Benepar
/// merge step and `importReference`'s structural-profile enrichment call straight through to
/// `BeneparService.shared`, which -- like `ReferenceLibraryStore`'s equivalent calls before its
/// own DI seam -- can't be swapped once referenced directly. `scheduleAnalysis`'s debounce timers
/// are already bypassable via `immediately: true`, so the analyzer override is the only piece
/// that was missing to make this whole pipeline deterministic and environment-independent.
final class EditorViewModelTests: XCTestCase {
    @MainActor
    func testScheduleAnalysisMergesTheStructuralProfileWhenBeneparSucceeds() async {
        let expectedProfile = StructuralProfile(
            sentencesAnalyzed: 4, sentencesAvailable: 4, averageTreeDepth: 5, maximumTreeDepth: 7,
            averageClausesPerSentence: 1.8, subordinateSentenceRatio: 0.25, averageLongestNounPhraseWords: 3.2,
            longNounPhraseRatio: 0.12, coordinationRatio: 0.08, passiveCandidateRatio: 0.04, fragmentRatio: 0
        )
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in
            BeneparAnalysis(metrics: expectedProfile, issues: [])
        })
        let text = "Although the rain had stopped, the road remained difficult to cross."

        viewModel.scheduleAnalysis(text: text, targetGrade: 8, immediately: true)
        await waitUntil { viewModel.isUsingBenepar }

        XCTAssertEqual(viewModel.structuralProfile, expectedProfile)
        XCTAssertFalse(viewModel.isAnalyzingStructure)
        XCTAssertGreaterThan(viewModel.analysis.stats.words, 0)
    }

    @MainActor
    func testScheduleAnalysisKeepsTheNativeResultWhenBeneparIsUnavailable() async {
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in nil })
        let text = "Although the rain had stopped, the road remained difficult to cross."

        viewModel.scheduleAnalysis(text: text, targetGrade: 8, immediately: true)
        await waitUntil { viewModel.analysis.stats.words > 0 }
        // The Benepar branch runs immediately after (no artificial delay with immediately: true);
        // give its already-resolved analyzer call a moment to land before asserting it changed nothing.
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.structuralProfile)
        XCTAssertFalse(viewModel.isUsingBenepar)
        XCTAssertFalse(viewModel.isAnalyzingStructure)
    }

    @MainActor
    func testScheduleAnalysisRefreshesReferenceAlignmentWithTheStructuralProfileOnceAvailable() async {
        let chapter = ReferenceChapter(id: 0, title: "Opening", text: "A measured opening line about the harbor.")
        let reference = EPUBReference(
            fileName: "reference.epub", title: "Reference", author: "Author",
            chapters: [chapter], profile: ReferenceProfileBuilder.build(chapters: [chapter])
        )
        let expectedProfile = StructuralProfile(
            sentencesAnalyzed: 2, sentencesAvailable: 2, averageTreeDepth: 3, maximumTreeDepth: 4,
            averageClausesPerSentence: 1, subordinateSentenceRatio: 0, averageLongestNounPhraseWords: 2,
            longNounPhraseRatio: 0, coordinationRatio: 0, passiveCandidateRatio: 0, fragmentRatio: 0
        )
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in
            BeneparAnalysis(metrics: expectedProfile, issues: [])
        })
        viewModel.useReference(reference, draft: "A draft about the harbor.")

        viewModel.scheduleAnalysis(text: "A draft about the harbor at dawn.", targetGrade: 8, immediately: true)
        await waitUntil { viewModel.isUsingBenepar }

        // Once Benepar succeeds, the reference alignment is recomputed with the draft's own
        // structural profile rather than the pre-Benepar (nil-draftStructure) alignment.
        let expectedAlignment = ReferenceComparison.analyze(
            draft: "A draft about the harbor at dawn.",
            against: reference,
            draftStructure: expectedProfile
        )
        XCTAssertEqual(viewModel.referenceAlignment.score, expectedAlignment.score)
    }

    @MainActor
    func testImportReferenceSucceedsAndEnrichesWithTheStructuralProfile() async throws {
        let expectedProfile = StructuralProfile(
            sentencesAnalyzed: 6, sentencesAvailable: 6, averageTreeDepth: 4, maximumTreeDepth: 6,
            averageClausesPerSentence: 1.5, subordinateSentenceRatio: 0.1, averageLongestNounPhraseWords: 2.5,
            longNounPhraseRatio: 0.05, coordinationRatio: 0.05, passiveCandidateRatio: 0.1, fragmentRatio: 0
        )
        let epubURL = try makeFixtureEPUB()
        defer { try? FileManager.default.removeItem(at: epubURL.deletingLastPathComponent()) }
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in
            BeneparAnalysis(metrics: expectedProfile, issues: [])
        })

        viewModel.importReference(from: epubURL, draft: "A short draft passage.")
        await waitUntil { !viewModel.isLoadingReference }

        XCTAssertNil(viewModel.errorMessage)
        let reference = try XCTUnwrap(viewModel.referenceBook)
        XCTAssertEqual(reference.profile.structuralProfile, expectedProfile)
    }

    @MainActor
    func testImportReferenceReportsAnErrorForAFileThatIsNotAValidEPUB() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EditorViewModel-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let brokenURL = directory.appendingPathComponent("broken.epub")
        try Data("not an epub archive".utf8).write(to: brokenURL)
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in nil })

        viewModel.importReference(from: brokenURL, draft: "A draft.")
        await waitUntil { !viewModel.isLoadingReference }

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.referenceBook)
    }

    // MARK: - Helpers

    private func makeFixtureEPUB() throws -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("EPUBSource", isDirectory: true)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EditorViewModel-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let outputURL = temporaryDirectory.appendingPathComponent("fixture.epub")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = fixtureDirectory
        process.arguments = ["-X", "-q", "-r", outputURL.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return outputURL
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the editor view model operation to finish")
    }
}

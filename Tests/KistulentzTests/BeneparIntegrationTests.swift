import Foundation
import XCTest
@testable import Kistulentz

final class BeneparIntegrationTests: XCTestCase {
    override func tearDown() {
        BeneparMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRealLanguagePackWhenFixturePathIsProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["KISTULENTZ_TEST_BENEPAR_PACK"],
              !path.isEmpty else {
            throw XCTSkip("Set KISTULENTZ_TEST_BENEPAR_PACK to run the real local model test.")
        }
        let service = BeneparService(rootURL: URL(fileURLWithPath: path, isDirectory: true))

        let analysis = try await service.analyze(
            text: "The final report was completed by the team.",
            maximumSentences: 4,
            includeIssues: true
        )

        XCTAssertEqual(analysis.metrics.sentencesAnalyzed, 1)
        XCTAssertTrue(analysis.issues.contains { $0.category == .passiveVoice })
        await service.reset()
    }

    func testWorkerIssueUsesUTF16RangesAndMapsStructuralCategory() throws {
        let text = "😀 A sentence with several clauses."
        let source = text as NSString
        let range = source.range(of: "A sentence with several clauses.")
        let workerIssue = BeneparWorkerIssue(
            category: "structuralComplexity",
            location: range.location,
            length: range.length,
            excerpt: source.substring(with: range),
            message: "Check the structure."
        )

        let issue = try XCTUnwrap(workerIssue.writingIssue(in: text))

        XCTAssertEqual(issue.category, .structuralComplexity)
        XCTAssertEqual(issue.range, range)
        XCTAssertEqual(issue.excerpt, "A sentence with several clauses.")
        XCTAssertNil(issue.replacement)
    }

    func testCompleteBeneparPassReplacesRegexSurfaceTagsButKeepsOtherGuidance() {
        let text = "The report was quickly completed by the team."
        let native = AnalysisResult(
            stats: .empty,
            issues: [
                WritingIssue(
                    category: .adverb,
                    range: (text as NSString).range(of: "quickly"),
                    excerpt: "quickly",
                    message: "Regex adverb"
                ),
                WritingIssue(
                    category: .passiveVoice,
                    range: (text as NSString).range(of: "was quickly completed"),
                    excerpt: "was quickly completed",
                    message: "Regex passive"
                ),
                WritingIssue(
                    category: .complexPhrase,
                    range: (text as NSString).range(of: "report"),
                    excerpt: "report",
                    message: "Keep this"
                )
            ]
        )
        let parsedAdverb = WritingIssue(
            category: .adverb,
            range: (text as NSString).range(of: "quickly"),
            excerpt: "quickly",
            message: "Benepar adverb"
        )
        let parsed = BeneparAnalysis(
            metrics: profile(sentencesAnalyzed: 1, sentencesAvailable: 1),
            issues: [parsedAdverb]
        )

        let merged = BeneparAnalysisMerger.merge(native: native, benepar: parsed)

        XCTAssertEqual(merged.issues.filter { $0.category == .adverb }.map(\.message), ["Benepar adverb"])
        XCTAssertFalse(merged.issues.contains { $0.category == .passiveVoice })
        XCTAssertTrue(merged.issues.contains { $0.category == .complexPhrase })
    }

    func testSampledBeneparPassKeepsNativeTagsOutsideItsSample() {
        let native = AnalysisResult(
            stats: .empty,
            issues: [WritingIssue(
                category: .adverb,
                range: NSRange(location: 0, length: 7),
                excerpt: "quickly",
                message: "Native"
            )]
        )
        let parsed = BeneparAnalysis(
            metrics: profile(sentencesAnalyzed: 60, sentencesAvailable: 120),
            issues: []
        )

        XCTAssertEqual(BeneparAnalysisMerger.merge(native: native, benepar: parsed).issues, native.issues)
    }

    func testOlderReferenceProfileDecodesWithoutStructuralData() throws {
        let json = """
        {
          "wordCount": 10,
          "chapterCount": 1,
          "gradeLevel": 7,
          "averageSentenceWords": 10,
          "sentenceVariation": 0,
          "averageParagraphWords": 10,
          "dialogueRatio": 0,
          "firstPersonRatio": 0,
          "thirdPersonRatio": 1,
          "tempo": "steady",
          "voice": "observational third-person",
          "tone": [],
          "vocabulary": [],
          "characters": []
        }
        """

        let decoded = try JSONDecoder().decode(ReferenceProfile.self, from: Data(json.utf8))

        XCTAssertNil(decoded.structuralProfile)
    }

    func testOlderManuscriptCacheDecodesWithoutStructuralData() throws {
        let json = #"{"generatedBibleBlock":"baseline","aiReportMarkdown":null}"#

        let decoded = try JSONDecoder().decode(ManuscriptProjectCache.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.generatedBibleBlock, "baseline")
        XCTAssertNil(decoded.structuralProfile)
    }

    func testStructuralProfilesMergeByProvidedWeight() throws {
        let first = profile(sentencesAnalyzed: 10, sentencesAvailable: 10, averageClauses: 1)
        let second = profile(sentencesAnalyzed: 20, sentencesAvailable: 20, averageClauses: 3)

        let merged = try XCTUnwrap(StructuralProfile.weightedMerge([
            (profile: first, weight: 100),
            (profile: second, weight: 300)
        ]))

        XCTAssertEqual(merged.averageClausesPerSentence, 2.5, accuracy: 0.001)
        XCTAssertEqual(merged.sentencesAnalyzed, 30)
    }

    func testManuscriptReportIncludesBeneparMetricsWithoutClaimingErrors() {
        let base = ManuscriptAnalyzer.analyze(
            projectName: "Book",
            kind: .fiction,
            documents: [ManuscriptDocument(
                relativePath: "Chapter.md",
                title: "Chapter",
                text: "Because the door opened, Mara stepped inside."
            )]
        )
        let enriched = ManuscriptAnalyzer.addingStructuralProfile(
            profile(sentencesAnalyzed: 1, sentencesAvailable: 1, averageClauses: 2),
            to: base
        )

        XCTAssertTrue(enriched.reportMarkdown.contains("### Benepar Sentence Structure"))
        XCTAssertTrue(enriched.reportMarkdown.contains("may be intentional"))
    }

    func testLocatorValidatesACompleteArchitectureSpecificPack() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let python = root.appendingPathComponent("python/bin/python3")
        let model = root.appendingPathComponent("nltk_data/models/benepar_en3", isDirectory: true)
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let manifest = BeneparLanguagePackManifest(
            schemaVersion: 1,
            identifier: "english-benepar",
            version: "1.0.0",
            architecture: BeneparLanguagePackLocator.architecture,
            pythonRelativePath: "python/bin/python3",
            modelRelativePath: "nltk_data/models/benepar_en3",
            installedBytes: 1_000
        )
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))

        let installation = try XCTUnwrap(BeneparLanguagePackLocator.locate(at: root))

        XCTAssertEqual(installation.pythonURL, python)
        XCTAssertEqual(installation.modelURL, model)
    }

    func testChecksumUsesStreamingSHA256() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("payload")
        try Data("Kistulentz".utf8).write(to: file)

        XCTAssertEqual(
            try BeneparLanguagePackManager.sha256(of: file),
            "94cad14726b9ae613dc7d5549e3a7017833bfceed4b22330ca34956abce06e68"
        )
    }

    func testInstallerExtractsAndValidatesCatalogMatchedArchive() throws {
        let temporary = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("source/English", isDirectory: true)
        let python = source.appendingPathComponent("python/bin/python3")
        let model = source.appendingPathComponent("nltk_data/models/benepar_en3", isDirectory: true)
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let manifest = BeneparLanguagePackManifest(
            schemaVersion: 1,
            identifier: "english-benepar",
            version: "1.0.0",
            architecture: BeneparLanguagePackLocator.architecture,
            pythonRelativePath: "python/bin/python3",
            modelRelativePath: "nltk_data/models/benepar_en3",
            installedBytes: 1_000
        )
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))

        let archive = temporary.appendingPathComponent("pack.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--keepParent", source.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let entry = BeneparLanguagePackCatalogEntry(
            architecture: BeneparLanguagePackLocator.architecture,
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/pack.zip")!,
            sha256: try BeneparLanguagePackManager.sha256(of: archive),
            downloadBytes: Int64(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
            installedBytes: 1_000
        )
        let destination = temporary.appendingPathComponent("installed/English", isDirectory: true)

        try BeneparLanguagePackManager.installArchive(archive, expected: entry, at: destination)

        let installed = try XCTUnwrap(BeneparLanguagePackLocator.locate(at: destination))
        XCTAssertEqual(installed.manifest.version, "1.0.0")
    }

    @MainActor
    func testLanguagePackManagerRejectsMalformedCatalogWithoutChangingInstallation() async throws {
        let root = temporaryDirectory().appendingPathComponent("English", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let catalogURL = URL(string: "https://example.invalid/catalog.json")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BeneparMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        BeneparMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url, catalogURL)
            return (
                HTTPURLResponse(url: catalogURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("not-json".utf8)
            )
        }
        let manager = BeneparLanguagePackManager(
            rootURL: root,
            catalogURL: catalogURL,
            session: session
        )

        await manager.install()

        XCTAssertFalse(manager.isInstalled)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testLanguagePackManagerRejectsHTTPFailureWithoutChangingInstallation() async throws {
        let root = temporaryDirectory().appendingPathComponent("English", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let marker = root.appendingPathComponent("existing-pack.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "keep me".write(to: marker, atomically: true, encoding: .utf8)
        let catalogURL = URL(string: "https://example.invalid/catalog.json")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BeneparMockURLProtocol.self]
        BeneparMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let manager = BeneparLanguagePackManager(
            rootURL: root,
            catalogURL: catalogURL,
            session: URLSession(configuration: configuration)
        )

        await manager.install()

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep me")
        XCTAssertNotNil(manager.errorMessage)
    }

    func testCorruptArchiveCannotReplaceAnExistingPack() throws {
        let temporary = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let installed = temporary.appendingPathComponent("installed/English", isDirectory: true)
        let marker = installed.appendingPathComponent("existing-pack.txt")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try "keep me".write(to: marker, atomically: true, encoding: .utf8)
        let archive = temporary.appendingPathComponent("corrupt.zip")
        try Data("not an archive".utf8).write(to: archive)
        let entry = BeneparLanguagePackCatalogEntry(
            architecture: BeneparLanguagePackLocator.architecture,
            version: "1.0.0",
            downloadURL: URL(string: "https://example.invalid/pack.zip")!,
            sha256: try BeneparLanguagePackManager.sha256(of: archive),
            downloadBytes: Int64(try Data(contentsOf: archive).count),
            installedBytes: 1_000
        )

        XCTAssertThrowsError(try BeneparLanguagePackManager.installArchive(
            archive,
            expected: entry,
            at: installed
        ))
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep me")
    }

    func testLanguagePackLocatorRejectsPathsThatEscapeThePackFolder() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = BeneparLanguagePackManifest(
            schemaVersion: 1,
            identifier: "english-benepar",
            version: "1.0.0",
            architecture: BeneparLanguagePackLocator.architecture,
            pythonRelativePath: "../outside/python3",
            modelRelativePath: "nltk_data/models/benepar_en3",
            installedBytes: 1_000
        )
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try BeneparLanguagePackLocator.locate(at: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsafe internal path"))
        }
    }

    private func profile(
        sentencesAnalyzed: Int,
        sentencesAvailable: Int,
        averageClauses: Double = 2
    ) -> StructuralProfile {
        StructuralProfile(
            sentencesAnalyzed: sentencesAnalyzed,
            sentencesAvailable: sentencesAvailable,
            averageTreeDepth: 7,
            maximumTreeDepth: 10,
            averageClausesPerSentence: averageClauses,
            subordinateSentenceRatio: 0.4,
            averageLongestNounPhraseWords: 5,
            longNounPhraseRatio: 0.1,
            coordinationRatio: 0.2,
            passiveCandidateRatio: 0.1,
            fragmentRatio: 0.05
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Benepar-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class BeneparMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

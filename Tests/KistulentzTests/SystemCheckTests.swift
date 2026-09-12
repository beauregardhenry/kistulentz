import Foundation
import XCTest
@testable import Kistulentz

final class SystemCheckTests: XCTestCase {
    @MainActor
    func testFullSystemCheckCanExerciseEveryLocalBranchWithoutContactingServices() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-System-Check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let languagePack = BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack"))
        let referenceLibrary = ReferenceLibraryStore(defaults: defaults)
        let expectedLanguage = SystemCheckItem(
            id: "english-language-pack",
            title: "Injected language pack",
            detail: "No worker launched.",
            status: .information
        )
        let expectedOllama = SystemCheckItem(
            id: "ollama",
            title: "Injected Ollama",
            detail: "No local service contacted.",
            status: .information
        )

        let report = await SystemCheckService.run(
            settings: settings,
            beneparPack: languagePack,
            referenceLibrary: referenceLibrary,
            languagePackEvaluator: { state in
                XCTAssertEqual(state, .notInstalled)
                return expectedLanguage
            },
            ollamaEvaluator: { expectedOllama }
        )

        XCTAssertEqual(report.items.first?.id, "native-analysis")
        XCTAssertTrue(report.items.contains { $0.id == "markdown-documents" })
        XCTAssertTrue(report.items.contains { $0.id == "ai-providers" })
        XCTAssertTrue(report.items.contains { $0.id == "reference-library" })
        XCTAssertTrue(report.items.contains { $0.id == "publishing-tools" })
        XCTAssertTrue(report.items.contains(expectedLanguage))
        XCTAssertTrue(report.items.contains(expectedOllama))
    }

    @MainActor
    func testSystemCheckListsAConfiguredProvider() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.ollamaModel = "local-model"
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = await SystemCheckService.run(
            settings: settings,
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: ReferenceLibraryStore(defaults: defaults),
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let providers = try XCTUnwrap(report.items.first { $0.id == "ai-providers" })
        XCTAssertEqual(providers.status, .passed)
        XCTAssertTrue(providers.detail.contains("Ollama"))
    }

    @MainActor
    func testSystemCheckReportsNoConfiguredProvider() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: ReferenceLibraryStore(defaults: defaults),
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let providers = try XCTUnwrap(report.items.first { $0.id == "ai-providers" })
        XCTAssertEqual(providers.status, .information)
        XCTAssertTrue(providers.detail.contains("No optional AI provider is fully configured"))
    }

    @MainActor
    func testSystemCheckReportsNoReferenceLibrarySelected() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: ReferenceLibraryStore(defaults: defaults),
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let library = try XCTUnwrap(report.items.first { $0.id == "reference-library" })
        XCTAssertEqual(library.status, .information)
        XCTAssertTrue(library.detail.contains("No Reference Library folder is selected"))
    }

    @MainActor
    func testSystemCheckReportsAWritableReferenceLibrary() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        let referenceLibrary = ReferenceLibraryStore(defaults: defaults)
        referenceLibrary.setLocation(libraryRoot)
        XCTAssertNil(referenceLibrary.errorMessage)

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: referenceLibrary,
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let library = try XCTUnwrap(report.items.first { $0.id == "reference-library" })
        XCTAssertEqual(library.status, .passed)
        XCTAssertTrue(library.detail.contains("0 books indexed"))
        XCTAssertTrue(library.detail.contains("Automatic checkpoints are available"))
    }

    @MainActor
    func testSystemCheckFlagsAReferenceLibraryFolderThatIsNoLongerWritable() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: libraryRoot.path)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        let referenceLibrary = ReferenceLibraryStore(defaults: defaults)
        referenceLibrary.setLocation(libraryRoot)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: libraryRoot.path)

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: referenceLibrary,
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let library = try XCTUnwrap(report.items.first { $0.id == "reference-library" })
        XCTAssertEqual(library.status, .attention)
        XCTAssertTrue(library.detail.contains("blocked because the selected folder is not writable"))
    }

    @MainActor
    func testSystemCheckDetectsInstalledPublishingTools() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeFileManager = FakeToolFileManager()
        fakeFileManager.executablePaths.insert("/opt/homebrew/bin/epubcheck")
        fakeFileManager.existingPaths.insert("/Applications/Transporter.app")

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: ReferenceLibraryStore(defaults: defaults),
            fileManager: fakeFileManager,
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let tools = try XCTUnwrap(report.items.first { $0.id == "publishing-tools" })
        XCTAssertEqual(tools.status, .passed)
        XCTAssertTrue(tools.detail.contains("EPUBCheck"))
        XCTAssertTrue(tools.detail.contains("Apple Transporter"))
        XCTAssertFalse(tools.detail.contains("Kindle Previewer"))
    }

    @MainActor
    func testSystemCheckReportsNoPublishingToolsWhenNoneAreFound() async throws {
        let suite = "KistulentzSystemCheckTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = await SystemCheckService.run(
            settings: AppSettings(defaults: defaults),
            beneparPack: BeneparLanguagePackManager(rootURL: root.appendingPathComponent("Pack")),
            referenceLibrary: ReferenceLibraryStore(defaults: defaults),
            fileManager: FakeToolFileManager(),
            languagePackEvaluator: { _ in noOpItem(id: "english-language-pack") },
            ollamaEvaluator: { noOpItem(id: "ollama") }
        )

        let tools = try XCTUnwrap(report.items.first { $0.id == "publishing-tools" })
        XCTAssertEqual(tools.status, .information)
        XCTAssertTrue(tools.detail.contains("No external publishing validators were found"))
    }

    func testRecognizesCompleteMarkdownDocumentDeclaration() {
        let info: [String: Any] = [
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeExtensions": ["md", "markdown", "mdown"],
                    "LSItemContentTypes": ["net.daringfireball.markdown"]
                ],
                [
                    "CFBundleTypeExtensions": ["txt", "text"],
                    "LSItemContentTypes": ["public.plain-text"]
                ]
            ]
        ]

        XCTAssertTrue(SystemCheckService.declaresMarkdownDocuments(infoDictionary: info))
        XCTAssertTrue(SystemCheckService.declaresPlainTextDocuments(infoDictionary: info))
        XCTAssertFalse(SystemCheckService.declaresMarkdownDocuments(infoDictionary: [:]))
        XCTAssertFalse(SystemCheckService.declaresPlainTextDocuments(infoDictionary: [:]))
    }

    func testDiagnosticMarkdownContainsStatusesAndPrivacyBoundary() {
        let report = SystemCheckReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "0.9.4",
            buildNumber: "16",
            bundleIdentifier: "com.beauhenry.kistulentz",
            macOSVersion: "Version 15.0",
            architecture: "arm64",
            items: [
                SystemCheckItem(id: "ready", title: "Ready item", detail: "Ready detail", status: .passed),
                SystemCheckItem(id: "attention", title: "Repair item", detail: "Repair detail", status: .attention)
            ]
        )

        let markdown = report.markdown()

        XCTAssertTrue(markdown.contains("# Kistulentz System Check"))
        XCTAssertTrue(markdown.contains("1 item needs attention"))
        XCTAssertTrue(markdown.contains("## Needs attention"))
        XCTAssertTrue(markdown.contains("## Ready"))
        XCTAssertTrue(markdown.contains("## Help us reproduce a problem"))
        XCTAssertTrue(markdown.contains("What did you expect instead?"))
        XCTAssertTrue(markdown.contains("excludes document and manuscript text"))
        XCTAssertTrue(markdown.contains("did not contact OpenAI or Anthropic"))
    }

    func testDiagnosticMarkdownContainsNoSecretPlaceholdersOrHomeDirectory() {
        let report = SystemCheckReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "0.12.2",
            buildNumber: "25",
            bundleIdentifier: "com.beauhenry.kistulentz",
            macOSVersion: "Version 15.0",
            architecture: "arm64",
            items: [
                SystemCheckItem(
                    id: "providers",
                    title: "Optional AI providers",
                    detail: "Configured providers: OpenAI. Cloud providers were not contacted.",
                    status: .passed
                )
            ]
        )

        let markdown = report.markdown()
        let forbidden = ["sk-test-secret", "PRIVATE MANUSCRIPT CANARY", FileManager.default.homeDirectoryForCurrentUser.path]
        for value in forbidden {
            XCTAssertFalse(markdown.contains(value), "Diagnostic report leaked: \(value)")
        }
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-SystemCheckTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A stand-in `SystemCheckItem` for the evaluator hooks a test isn't exercising, so `run()`'s own
/// branch logic (rather than the real `BeneparService`/`Ollama` network calls) is what's under test.
private func noOpItem(id: String) -> SystemCheckItem {
    SystemCheckItem(id: id, title: id, detail: "not exercised in this test", status: .information)
}

/// Reports specific paths as executable/existing without touching the real filesystem outside the
/// paths a test explicitly registers, so `publishingToolCheck`'s branches can be driven directly.
private final class FakeToolFileManager: FileManager {
    var executablePaths: Set<String> = []
    var existingPaths: Set<String> = []

    override func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }

    override func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }
}

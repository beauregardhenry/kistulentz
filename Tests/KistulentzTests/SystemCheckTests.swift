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
}

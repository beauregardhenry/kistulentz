import Foundation
import XCTest
@testable import Kistulentz

final class SystemCheckTests: XCTestCase {
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
        XCTAssertTrue(markdown.contains("excludes document and manuscript text"))
        XCTAssertTrue(markdown.contains("did not contact OpenAI or Anthropic"))
    }
}

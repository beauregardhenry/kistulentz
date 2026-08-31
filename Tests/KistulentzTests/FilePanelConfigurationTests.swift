import UniformTypeIdentifiers
import XCTest
@testable import Kistulentz

final class FilePanelConfigurationTests: XCTestCase {
    func testResearchLibraryChooserSelectsOrCreatesExactlyOneFolder() {
        let configuration = OpenPanelConfiguration.researchLibraryFolder

        XCTAssertFalse(configuration.canChooseFiles)
        XCTAssertTrue(configuration.canChooseDirectories)
        XCTAssertTrue(configuration.canCreateDirectories)
        XCTAssertFalse(configuration.allowsMultipleSelection)
        XCTAssertEqual(configuration.prompt, "Use Folder")
    }

    func testDiagnosticReportSaveConfigurationIsMarkdownAndAllowsNewFolders() {
        let configuration = SavePanelConfiguration(
            title: "Export Kistulentz Diagnostic Report",
            suggestedFilename: "Kistulentz Diagnostics.md",
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
            canCreateDirectories: true
        )

        XCTAssertEqual(configuration.suggestedFilename, "Kistulentz Diagnostics.md")
        XCTAssertTrue(configuration.canCreateDirectories)
        XCTAssertTrue(configuration.allowedContentTypes.contains {
            $0.identifier == "net.daringfireball.markdown" || $0.conforms(to: .plainText)
        })
    }
}

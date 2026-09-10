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

    func testReferenceLibraryPanelConfigurationsKeepFolderAndEPUBSelectionDistinct() {
        let folder = OpenPanelConfiguration.referenceLibraryFolder
        XCTAssertFalse(folder.canChooseFiles)
        XCTAssertTrue(folder.canChooseDirectories)
        XCTAssertTrue(folder.canCreateDirectories)
        XCTAssertFalse(folder.allowsMultipleSelection)

        let files = OpenPanelConfiguration.referenceEPUBFiles
        XCTAssertTrue(files.canChooseFiles)
        XCTAssertFalse(files.canChooseDirectories)
        XCTAssertTrue(files.allowsMultipleSelection)
        XCTAssertEqual(files.allowedContentTypes?.count, 1)

        let folders = OpenPanelConfiguration.referenceEPUBFolders
        XCTAssertFalse(folders.canChooseFiles)
        XCTAssertTrue(folders.canChooseDirectories)
        XCTAssertTrue(folders.allowsMultipleSelection)
    }
}

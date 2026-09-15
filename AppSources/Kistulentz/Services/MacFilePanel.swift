import AppKit
import UniformTypeIdentifiers

struct OpenPanelConfiguration: Equatable {
    let title: String
    let message: String?
    let prompt: String
    let canChooseFiles: Bool
    let canChooseDirectories: Bool
    let canCreateDirectories: Bool
    let allowsMultipleSelection: Bool
    var allowedContentTypes: [UTType]? = nil

    static let researchLibraryFolder = OpenPanelConfiguration(
        title: "Choose a Research Library Folder",
        message: "Select an existing folder, or create a new folder for your research library.",
        prompt: "Use Folder",
        canChooseFiles: false,
        canChooseDirectories: true,
        canCreateDirectories: true,
        allowsMultipleSelection: false
    )

    static let referenceLibraryFolder = OpenPanelConfiguration(
        title: "Choose a Reference Library Folder",
        message: "Select an existing folder, or create a new folder for the Markdown reference library.",
        prompt: "Use Folder",
        canChooseFiles: false,
        canChooseDirectories: true,
        canCreateDirectories: true,
        allowsMultipleSelection: false
    )

    static let referenceEPUBFiles = OpenPanelConfiguration(
        title: "Add EPUB Files",
        message: nil,
        prompt: "Import",
        canChooseFiles: true,
        canChooseDirectories: false,
        canCreateDirectories: false,
        allowsMultipleSelection: true,
        allowedContentTypes: [UTType(importedAs: "org.idpf.epub-container")]
    )

    static let referenceEPUBFolders = OpenPanelConfiguration(
        title: "Add a Folder of EPUB Files",
        message: nil,
        prompt: "Scan Folder",
        canChooseFiles: false,
        canChooseDirectories: true,
        canCreateDirectories: false,
        allowsMultipleSelection: true
    )

    static let researchRecords = OpenPanelConfiguration(
        title: "Import Research Sources",
        message: "Choose BibTeX, RIS, or CSL-JSON files to add to the Research Library.",
        prompt: "Import",
        canChooseFiles: true,
        canChooseDirectories: false,
        canCreateDirectories: false,
        allowsMultipleSelection: true,
        allowedContentTypes: [.data]
    )

    static let researchAttachments = OpenPanelConfiguration(
        title: "Add Research Attachments",
        message: "Choose files to copy or link and index locally.",
        prompt: "Add",
        canChooseFiles: true,
        canChooseDirectories: false,
        canCreateDirectories: false,
        allowsMultipleSelection: true,
        allowedContentTypes: [.data, .image, .pdf, .plainText]
    )

    static let customFontFiles = OpenPanelConfiguration(
        title: "Add Font Files",
        message: "Choose TrueType or OpenType font files to make available throughout Kistulentz.",
        prompt: "Add",
        canChooseFiles: true,
        canChooseDirectories: false,
        canCreateDirectories: false,
        allowsMultipleSelection: true,
        allowedContentTypes: [.font]
    )
}

struct SavePanelConfiguration: Equatable {
    let title: String
    let suggestedFilename: String
    let allowedContentTypes: [UTType]
    let canCreateDirectories: Bool
}

@MainActor
enum MacFilePanel {
    static func chooseFolder(
        configuration: OpenPanelConfiguration = .researchLibraryFolder,
        startingAt directoryURL: URL? = nil,
        uiTestEnvironmentKey: String = "KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH"
    ) async -> URL? {
        await chooseItems(
            configuration: configuration,
            startingAt: directoryURL,
            uiTestEnvironmentKey: uiTestEnvironmentKey
        )?.first
    }

    static func chooseItems(
        configuration: OpenPanelConfiguration,
        startingAt directoryURL: URL? = nil,
        uiTestEnvironmentKey: String? = nil
    ) async -> [URL]? {
#if UI_TEST_HOST
        if let uiTestEnvironmentKey,
           let paths = ProcessInfo.processInfo.environment[uiTestEnvironmentKey] {
            let urls = paths
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            if !urls.isEmpty { return urls }
        }
#endif
        let panel = NSOpenPanel()
        panel.title = configuration.title
        panel.message = configuration.message
        panel.prompt = configuration.prompt
        panel.canChooseFiles = configuration.canChooseFiles
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.allowedContentTypes = configuration.allowedContentTypes ?? []
        panel.directoryURL = directoryURL
        return await present(panel).flatMap { $0 == .OK ? panel.urls : nil }
    }

    static func chooseSaveDestination(configuration: SavePanelConfiguration) async -> URL? {
#if UI_TEST_HOST
        if let path = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_SAVE_DESTINATION_PATH"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
#endif
        let panel = NSSavePanel()
        panel.title = configuration.title
        panel.nameFieldStringValue = configuration.suggestedFilename
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.allowedContentTypes = configuration.allowedContentTypes
        return await present(panel).flatMap { $0 == .OK ? panel.url : nil }
    }

    /// `NSOpenPanel`/`NSSavePanel` are `NSWindow` subclasses and participate in Cocoa's automatic
    /// window-state restoration by default. Left unset, quitting (or being killed) while one of
    /// these transient file-chooser sheets is open makes AppKit persist and silently re-show that
    /// exact panel on the next launch -- ahead of anything Kistulentz's own startup logic, the
    /// Welcome landing page included, ever gets a chance to run. A one-shot picker like this
    /// should never outlive the session it was opened in.
    static func configureForPresentation(_ panel: NSSavePanel) {
        panel.isRestorable = false
    }

    private static func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse? {
        configureForPresentation(panel)
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        }
        return panel.runModal()
    }
}

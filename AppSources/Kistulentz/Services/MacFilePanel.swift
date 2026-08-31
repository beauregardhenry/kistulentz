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

    static let researchLibraryFolder = OpenPanelConfiguration(
        title: "Choose a Research Library Folder",
        message: "Select an existing folder, or create a new folder for your research library.",
        prompt: "Use Folder",
        canChooseFiles: false,
        canChooseDirectories: true,
        canCreateDirectories: true,
        allowsMultipleSelection: false
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
        startingAt directoryURL: URL? = nil
    ) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = configuration.title
        panel.message = configuration.message
        panel.prompt = configuration.prompt
        panel.canChooseFiles = configuration.canChooseFiles
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.directoryURL = directoryURL
        return await present(panel).flatMap { $0 == .OK ? panel.url : nil }
    }

    static func chooseSaveDestination(configuration: SavePanelConfiguration) async -> URL? {
        let panel = NSSavePanel()
        panel.title = configuration.title
        panel.nameFieldStringValue = configuration.suggestedFilename
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.allowedContentTypes = configuration.allowedContentTypes
        return await present(panel).flatMap { $0 == .OK ? panel.url : nil }
    }

    private static func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse? {
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

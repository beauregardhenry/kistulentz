import AppKit
import Foundation
import UniformTypeIdentifiers

// Split out of EditorWorkspace.swift: opening, creating, closing a project folder, and importing
// or opening a plain document into the editor. No behavior change from the move itself.
extension EditorWorkspace {
    func requestProjectFolder(_ action: ProjectFolderAction) {
        projectFolderAction = action
#if UI_TEST_HOST
        if let path = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_PROJECT_FOLDER_PATH"],
           !path.isEmpty {
            handleProjectFolderResult(.success([URL(fileURLWithPath: path, isDirectory: true)]))
            return
        }
#endif
        showingProjectFolderImporter = true
    }

    func chooseDocumentForImport() {
        let panel = NSOpenPanel()
        panel.title = "Import a Document"
        panel.message = "Choose a plain-text, Word, RTF, RTFD, HTML, or OpenDocument file. Kistulentz will create a separate Markdown copy."
        panel.prompt = "Import"
        panel.allowedContentTypes = DocumentImportFormat.importableContentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        documentImport.load(from: url)
    }

    func saveImportedDocument(
        _ draft: DocumentImportDraft,
        decisions: [UUID: DocumentTrackedChangeDecision]
    ) {
        documentImport.clearDraft()
        Task { @MainActor in
            await Task.yield()
            let panel = NSSavePanel()
            panel.title = "Save Markdown Copy"
            panel.message = "The original \(draft.format.title) document will remain unchanged."
            panel.prompt = "Save Copy"
            panel.allowedContentTypes = [.markdownDocument]
            panel.nameFieldStringValue = draft.suggestedMarkdownFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            guard panel.runModal() == .OK, let outputURL = panel.url else { return }
            documentImport.save(draft, decisions: decisions, to: outputURL) { result in
                openImportedMarkdown(result.markdownURL)
            }
        }
    }

    func openImportedMarkdown(_ url: URL) {
#if UI_TEST_HOST
        if ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_DISABLE_AUTO_OPEN"] == "1" {
            return
        }
#endif
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                Task { @MainActor in viewModel.errorMessage = error.localizedDescription }
            }
        }
    }

    func completeProjectImport(_ completion: ProjectImportCompletion) {
        presentation.dismiss(.projectImportAssistant)
        switch completion {
        case .markdown(let url):
            openImportedMarkdown(url)
        case .project(let root):
            do {
                if projectStore.rootURL?.standardizedFileURL != root.standardizedFileURL {
                    try projectStore.openProject(at: root)
                }
                activateProject()
            } catch {
                projectStore.errorMessage = error.localizedDescription
            }
        }
    }

    func handleProjectFolderResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch projectFolderAction {
            case .createInParent:
                pendingProjectConfiguration = PendingProjectConfiguration(
                    url: url,
                    initialName: "Untitled Project",
                    mode: .createInParent
                )
            case .openExisting:
                if WritingProjectDisk.hasManifest(at: url) {
                    do {
                        try projectStore.openProject(at: url)
                        activateProject()
                    } catch {
                        if projectStore.recoveryRequest == nil {
                            projectStore.errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    pendingProjectConfiguration = PendingProjectConfiguration(
                        url: url,
                        initialName: url.lastPathComponent,
                        mode: .prepareExisting
                    )
                }
            }
        case .failure(let error):
            projectStore.errorMessage = error.localizedDescription
        }
    }

    func configureProject(
        _ configuration: PendingProjectConfiguration,
        name: String,
        kind: WritingProjectKind
    ) {
        do {
            switch configuration.mode {
            case .createInParent:
                try projectStore.createProject(in: configuration.url, name: name, kind: kind)
            case .prepareExisting:
                try projectStore.prepareAndOpenProject(at: configuration.url, name: name, kind: kind)
            }
            activateProject()
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    func activateProject() {
        undoManager?.removeAllActions()
        viewModel.configureDocument(url: projectStore.selectedFileURL, text: projectStore.text)
        viewModel.scheduleAnalysis(
            text: projectStore.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }

    func closeProject() {
        projectStore.closeProject()
        undoManager?.removeAllActions()
        viewModel.configureDocument(url: fileURL, text: document.text)
        viewModel.scheduleAnalysis(
            text: document.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }
}

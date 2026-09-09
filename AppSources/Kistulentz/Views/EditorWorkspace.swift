import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ProjectFolderAction {
    case createInParent
    case openExisting
}

private struct PendingProjectConfiguration: Identifiable {
    enum Mode {
        case createInParent
        case prepareExisting
    }

    let id = UUID()
    let url: URL
    let initialName: String
    let mode: Mode
}

struct EditorWorkspace: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    let suppliedUndoManager: UndoManager?

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @EnvironmentObject private var researchLibrary: ResearchLibraryStore
    @EnvironmentObject private var draftRecovery: DraftRecoveryManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var undoCoordinator = DocumentUndoCoordinator()
    @StateObject private var projectStore: WritingProjectStore
    @ObservedObject private var styleLearningStore: StyleLearningStore
    @StateObject private var draftRecoveryCoordinator = DraftRecoveryCoordinator()
    @StateObject private var presentation = EditorWorkspacePresentation()
    @StateObject private var documentImport = DocumentImportCoordinator()
    @State private var polishedDraftPlan: PolishedDraftPlan?
    @State private var pendingApplyAllPlan: SuggestionApplicationPlan?
    @State private var showingReferenceImporter = false
    @State private var selectedLibraryReferences: Set<String> = []
    @State private var isWriteMode = false
    @State private var showingProjectFolderImporter = false
    @State private var projectFolderAction: ProjectFolderAction = .openExisting
    @State private var pendingProjectConfiguration: PendingProjectConfiguration?
    @State private var destinkManuscriptDocuments: [ManuscriptDocument]?
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var pendingProjectPolishApply: RevisionChangeSet?
    @State private var didPresentStartup = false
#if UI_TEST_HOST
    @State private var didConfigureUITestProject = false
    @State private var lastUITestEditCommand = ""
    @State private var uiTestEditUndoManager = UndoManager()
#endif

    private let epubType = UTType(importedAs: "org.idpf.epub-container")

    init(
        document: Binding<MarkdownDocument>,
        fileURL: URL?,
        suppliedUndoManager: UndoManager? = nil
    ) {
        _document = document
        self.fileURL = fileURL
        self.suppliedUndoManager = suppliedUndoManager
        let store = WritingProjectStore()
        _projectStore = StateObject(wrappedValue: store)
        _styleLearningStore = ObservedObject(wrappedValue: store.styleLearningStore)
    }

    private var editorLayout: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if isWriteMode {
                MarkdownTextView(
                    text: activeTextBinding,
                    selection: $editorSelection,
                    issues: [],
                    focusRequest: viewModel.focusRequest,
                    fontName: settings.editorFontName,
                    fontSize: settings.editorFontSize
                )
                .frame(minWidth: 600)
            } else {
                HSplitView {
                    if projectStore.isOpen {
                        ProjectSidebar(
                            store: projectStore,
                            searchStore: projectStore.searchStore,
                            onSelectSearchResult: selectSearchResult,
                            onNewChapter: { presentation.present(.newChapter) },
                            onEditStyle: { presentation.present(.styleEditor) },
                            onShowHistory: { presentation.present(.revisionHistory) },
                            onCreateSnapshot: { presentation.present(.namedSnapshot) },
                            onShowManuscriptInsights: { presentation.present(.manuscriptInsights) },
                            onShowOrganization: { presentation.present(.projectOrganization) },
                            onShowResearch: { presentation.present(.projectResearch) },
                            onShowProjectPolish: { presentation.present(.projectPolish) },
                            onShowRevisionCenter: { presentation.present(.revisionCenter) },
                            onShowPublish: { presentation.present(.publishExport) },
                            onCloseProject: closeProject
                        )
                        .frame(minWidth: 205, idealWidth: 225, maxWidth: 275)
                    }

                    ReadabilitySidebar(
                        stats: viewModel.analysis.stats,
                        issues: visibleLocalHighlightIssues,
                        targetGrade: settings.targetGrade,
                        isUsingBenepar: viewModel.isUsingBenepar,
                        isAnalyzingStructure: viewModel.isAnalyzingStructure,
                        onSelect: viewModel.focus
                    )
                    .frame(minWidth: 205, idealWidth: 225, maxWidth: 260)

                    MarkdownTextView(
                        text: activeTextBinding,
                        selection: $editorSelection,
                        issues: visibleHighlightIssues,
                        focusRequest: viewModel.focusRequest,
                        fontName: settings.editorFontName,
                        fontSize: settings.editorFontSize
                    )
                    .frame(minWidth: 450)

                    ReviewSidebar(
                        issues: viewModel.allIssues,
                        review: viewModel.aiReview,
                        blockedAISuggestionCount: viewModel.blockedAISuggestionCount,
                        isReviewing: viewModel.isReviewing,
                        isRewriting: viewModel.isRewriting,
                        provider: settings.provider,
                        hasAPIKey: settings.isProviderReady(settings.provider),
                        reference: viewModel.referenceBook,
                        alignment: viewModel.referenceAlignment,
                        isLoadingReference: viewModel.isLoadingReference,
                        onRunReview: runReview,
                        onOpenSettings: { openSettings() },
                        onChooseReference: { presentation.present(.referenceLibrary) },
                        onRemoveReference: viewModel.clearReference,
                        onSelect: viewModel.focus,
                        onApply: apply,
                        onDecline: decline,
                        onRewrite: prepareRewrite,
                        onApplyAll: prepareApplyAll,
                        onReviewPolishedDraft: preparePolishedDraftReview
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
    }

    // Split from `lifecycleConfiguredView` so neither half chains too many modifiers onto
    // `editorLayout` for the type checker to resolve as one expression. Splitting a chain like
    // this into separate `some View` stages doesn't change what any modifier does or when it
    // fires relative to the others — only how the compiler resolves the type of the expression.
    private var textReactiveConfiguredView: some View {
        editorLayout
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(projectStore.isOpen ? projectStore.projectName : (fileURL?.lastPathComponent ?? "Untitled.md"))
        .onAppear {
            projectStore.attachUndoManager(
                suppliedUndoManager ?? undoManager ?? NSApp.keyWindow?.undoManager
            )
#if UI_TEST_HOST
            configureUITestProjectIfNeeded()
#endif
            viewModel.configureDocument(url: activeFileURL, text: activeText)
            viewModel.updateStyleDecisions(styleLearningStore.styleDecisions)
            configureDraftRecovery()
            viewModel.scheduleAnalysis(
                text: activeText,
                targetGrade: settings.targetGrade,
                immediately: true
            )
            presentStartupIfNeeded()
        }
#if UI_TEST_HOST
        .task {
            await monitorUITestEditCommand()
        }
#endif
        .onChange(of: styleLearningStore.styleDecisions) { _, newValue in
            viewModel.updateStyleDecisions(newValue)
        }
        .onChange(of: document.text) { _, newValue in
            if !projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
                draftRecoveryCoordinator.schedule(text: newValue)
            }
        }
        .onChange(of: projectStore.text) { _, newValue in
            if projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
                draftRecoveryCoordinator.schedule(text: newValue)
            }
        }
        .onChange(of: presentation.activeSheet) { previous, current in
            guard previous == .projectPolish, current != .projectPolish else { return }
            applyPendingProjectPolishIfNeeded()
        }
    }

    private var lifecycleConfiguredView: some View {
        textReactiveConfiguredView
        .onChange(of: projectStore.selectedFileURL) { _, newValue in
            guard projectStore.isOpen else { return }
            editorSelection = NSRange(location: 0, length: 0)
            if !projectStore.preservesUndoAcrossFileRelocation {
                undoManager?.removeAllActions()
            }
            viewModel.clearAIReview()
            viewModel.configureDocument(url: newValue, text: projectStore.text)
            viewModel.scheduleAnalysis(
                text: projectStore.text,
                targetGrade: settings.targetGrade,
                immediately: true
            )
            Task { @MainActor in
                await Task.yield()
                configureDraftRecovery()
            }
        }
        .onChange(of: fileURL) { _, newValue in
            if !projectStore.isOpen {
                viewModel.configureDocument(url: newValue, text: document.text)
                configureDraftRecovery()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active { draftRecoveryCoordinator.flush() }
        }
        .onChange(of: settings.targetGrade) { _, newValue in
            viewModel.scheduleAnalysis(text: activeText, targetGrade: newValue, immediately: true)
        }
        .onChange(of: beneparPack.isInstalled) { _, isInstalled in
            guard isInstalled else { return }
            viewModel.scheduleAnalysis(
                text: activeText,
                targetGrade: settings.targetGrade,
                immediately: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .runAIReview)) { _ in
            runReview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKistulentzWelcome)) { _ in
            presentation.present(.welcome)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKistulentzWhatsNew)) { _ in
            presentation.present(.whatsNew)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDraftRecovery)) { _ in
            draftRecovery.reloadPendingEntries()
            presentation.present(.draftRecovery)
        }
        .onDisappear {
            draftRecoveryCoordinator.flush()
            documentImport.cancel()
            if projectStore.isOpen {
                projectStore.saveNow()
                if !projectStore.hasUnsavedChapterChanges {
                    draftRecoveryCoordinator.close()
                }
            } else {
                draftRecoveryCoordinator.close()
            }
        }
    }

    private var libraryConfiguredView: some View {
        lifecycleConfiguredView.fileImporter(
            isPresented: $showingReferenceImporter,
            allowedContentTypes: [epubType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.importReference(from: url, draft: activeText)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: presentation.binding(for: .referenceLibrary)) {
            ReferenceLibraryView(selectedChoiceIDs: $selectedLibraryReferences) { reference in
                viewModel.useReference(reference, draft: activeText)
            }
            .environmentObject(referenceLibrary)
            .environmentObject(settings)
        }
        .sheet(isPresented: presentation.binding(for: .researchLibrary)) {
            ResearchLibraryView()
                .environmentObject(researchLibrary)
        }
        .sheet(isPresented: presentation.binding(for: .projectResearch)) {
            ProjectResearchView(
                projectStore: projectStore,
                researchStore: projectStore.researchStore,
                selectionText: selectedPassage?.text,
                onInsertCitation: insertCitation
            )
            .environmentObject(researchLibrary)
        }
        .sheet(isPresented: presentation.binding(for: .revisionCenter)) {
            SystemicRevisionCenterView(store: projectStore, styleLearningStore: styleLearningStore, onNavigate: navigateToRevisionFinding)
                .environmentObject(settings)
                .environmentObject(researchLibrary)
        }
        .sheet(isPresented: presentation.binding(for: .projectPolish)) {
            ProjectPolishView(store: projectStore) { changeSet in
                pendingProjectPolishApply = changeSet
                presentation.dismiss(.projectPolish)
            }
                .environmentObject(settings)
        }
        .sheet(isPresented: presentation.binding(for: .destinker)) {
            DestinkView(
                currentDocument: destinkCurrentDocument,
                selection: selectedPassage.map { DestinkSelection(text: $0.text, range: $0.range) },
                manuscriptDocuments: destinkManuscriptDocuments,
                onNavigate: navigateToDestinkFinding
            )
            .environmentObject(beneparPack)
        }
        .sheet(isPresented: presentation.binding(for: .publishExport)) {
            PublishExportView(store: projectStore, publicationStore: projectStore.publicationStore)
                .environmentObject(researchLibrary)
        }
    }

    private var importConfiguredView: some View {
        libraryConfiguredView.sheet(item: $documentImport.draft) { draft in
            DocumentImportPreviewView(
                draft: draft,
                onCancel: documentImport.clearDraft,
                onSave: { decisions in saveImportedDocument(draft, decisions: decisions) }
            )
        }
        .sheet(isPresented: presentation.binding(for: .projectImportAssistant)) {
            ProjectImportAssistantView(
                currentProjectName: projectStore.isOpen ? projectStore.projectName : nil,
                addToCurrentProject: projectStore.isOpen ? { conversions, decisions in
                    try projectStore.importProjectDocuments(conversions, decisions: decisions)
                } : nil,
                onComplete: completeProjectImport,
                onCancel: { presentation.dismiss(.projectImportAssistant) }
            )
        }
        .sheet(isPresented: presentation.binding(for: .welcome)) {
            WelcomeView(
                onCreateProject: beginProjectFromWelcome,
                onOpenDocument: openDocumentFromWelcome,
                onImportDocuments: beginImportFromWelcome,
                onOpenSample: createSampleProject,
                onContinue: completeWelcome
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: presentation.binding(for: .whatsNew)) {
            WhatsNewView(version: AppSettings.appVersion()) {
                finishWhatsNew()
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: presentation.binding(for: .englishPackPrompt)) {
            EnglishPackPromptView(
                onNotNow: finishEnglishPackPrompt,
                onInstalled: finishEnglishPackPrompt
            )
            .environmentObject(beneparPack)
        }
        .sheet(
            isPresented: presentation.binding(for: .draftRecovery),
            onDismiss: presentWelcomeAfterRecovery
        ) {
            DraftRecoveryView(manager: draftRecovery) {
                presentation.dismiss(.draftRecovery)
            }
        }
        .fileImporter(
            isPresented: $showingProjectFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleProjectFolderResult(result)
        }
        .sheet(item: $pendingProjectConfiguration) { configuration in
            ProjectConfigurationSheet(
                title: configuration.mode == .createInParent ? "New Kistulentz Project" : "Set Up Project Folder",
                initialName: configuration.initialName,
                allowsNameEditing: configuration.mode == .createInParent
            ) { name, kind in
                configureProject(configuration, name: name, kind: kind)
            }
        }
    }

    private var projectConfiguredView: some View {
        importConfiguredView.sheet(isPresented: presentation.binding(for: .newChapter)) {
            NewChapterSheet { projectStore.createChapter(named: $0) }
        }
        .sheet(isPresented: presentation.binding(for: .styleEditor)) {
            ProjectStyleEditorView(store: styleLearningStore)
        }
        .sheet(isPresented: presentation.binding(for: .revisionHistory)) {
            RevisionHistoryView(store: projectStore)
                .onDisappear { undoManager?.removeAllActions() }
        }
        .sheet(isPresented: presentation.binding(for: .manuscriptInsights)) {
            ManuscriptInsightsView(
                store: projectStore,
                betaReadersStore: projectStore.betaReadersStore,
                styleLearningStore: styleLearningStore,
                selectedPassage: selectedPassage?.text,
                reference: viewModel.referenceBook,
                onShowRevisionHistory: { presentation.present(.revisionHistory) }
            )
            .environmentObject(settings)
        }
        .sheet(isPresented: presentation.binding(for: .projectOrganization)) {
            ProjectOrganizationView(store: projectStore, styleLearningStore: styleLearningStore, reference: viewModel.referenceBook)
                .environmentObject(settings)
        }
        .sheet(isPresented: presentation.binding(for: .namedSnapshot)) {
            NamedSnapshotSheet(chapterTitle: projectStore.selectedChapterTitle) { name in
                projectStore.createSnapshot(name: name, reason: "Named snapshot")
            }
        }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                executeAIRequest(confirmed)
            }
        }
        .sheet(isPresented: presentation.binding(for: .toneRequest)) {
            ToneRequestView { tone in
                presentation.dismiss(.toneRequest)
                Task { @MainActor in
                    await Task.yield()
                    prepareRewrite(SelectionRewriteGoal(kind: .adjustTone, requestedTone: tone))
                }
            }
        }
        .sheet(item: $projectStore.recoveryRequest) { request in
            ProjectRecoveryView(
                request: request,
                onRestore: { backup in
                    do {
                        try projectStore.restoreProject(from: backup)
                        activateProject()
                    } catch {
                        projectStore.errorMessage = error.localizedDescription
                    }
                },
                onCancel: projectStore.dismissRecovery
            )
        }
        .sheet(item: $viewModel.rewritePresentation) { presentation in
            SelectionRewriteResultView(presentation: presentation) { alternative in
                applyRewrite(alternative, presentation: presentation)
            }
        }
        .sheet(item: $polishedDraftPlan) { plan in
            PolishedDraftReviewView(
                plan: plan,
                onApplySelected: { applyPolishedChanges($0, from: plan) },
                onReplaceAll: { replaceWithPolishedDraft(from: plan) }
            )
        }
    }

    var body: some View {
        projectConfiguredView.alert("Kistulentz", isPresented: Binding(
            get: {
                viewModel.errorMessage != nil
                    || projectStore.errorMessage != nil
                    || documentImport.errorMessage != nil
            },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    projectStore.errorMessage = nil
                    documentImport.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                viewModel.errorMessage
                    ?? projectStore.errorMessage
                    ?? documentImport.errorMessage
                    ?? ""
            )
        }
        .confirmationDialog(
            "Apply all safe suggestions?",
            isPresented: Binding(
                get: { pendingApplyAllPlan != nil },
                set: { if !$0 { pendingApplyAllPlan = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plan = pendingApplyAllPlan {
                Button(applyAllButtonTitle(for: plan)) {
                    applyAll(plan)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingApplyAllPlan = nil
            }
        } message: {
            if let plan = pendingApplyAllPlan {
                Text(applyAllMessage(for: plan))
            }
        }
    }

    private var activeText: String {
        projectStore.isOpen ? projectStore.text : document.text
    }

    private var activeTextBinding: Binding<String> {
        if projectStore.isOpen {
            return Binding(
                get: { projectStore.text },
                set: { projectStore.updateText($0) }
            )
        }
        return $document.text
    }

    private var activeFileURL: URL? {
        projectStore.isOpen ? projectStore.selectedFileURL : fileURL
    }

    private var visibleHighlightIssues: [WritingIssue] {
        viewModel.allIssues.filter { settings.isHighlightVisible($0.category) }
    }

    private var visibleLocalHighlightIssues: [WritingIssue] {
        viewModel.visibleLocalIssues.filter { settings.isHighlightVisible($0.category) }
    }

    private var topBar: some View {
        EditorToolbar(
            settings: settings,
            projectStore: projectStore,
            viewModel: viewModel,
            isWriteMode: $isWriteMode,
            activeFileURL: activeFileURL,
            isImportingDocument: documentImport.isRunning,
            hasSelectedPassage: selectedPassage != nil,
            actions: EditorToolbarActions(
                chooseDocumentForImport: chooseDocumentForImport,
                showProjectImportAssistant: { presentation.present(.projectImportAssistant) },
                createProject: {
                    projectFolderAction = .createInParent
                    showingProjectFolderImporter = true
                },
                openProject: {
                    projectFolderAction = .openExisting
                    showingProjectFolderImporter = true
                },
                showNewChapter: { presentation.present(.newChapter) },
                showStyleEditor: { presentation.present(.styleEditor) },
                showNamedSnapshot: { presentation.present(.namedSnapshot) },
                showRevisionHistory: { presentation.present(.revisionHistory) },
                showManuscriptInsights: { presentation.present(.manuscriptInsights) },
                presentDestinker: presentDestinker,
                showProjectOrganization: { presentation.present(.projectOrganization) },
                showProjectResearch: { presentation.present(.projectResearch) },
                showProjectPolish: { presentation.present(.projectPolish) },
                showRevisionCenter: { presentation.present(.revisionCenter) },
                showPublishExport: { presentation.present(.publishExport) },
                closeProject: closeProject,
                showToneRequest: { presentation.present(.toneRequest) },
                prepareRewrite: prepareRewrite,
                showResearchLibrary: { presentation.present(.researchLibrary) },
                showReferenceLibrary: { presentation.present(.referenceLibrary) },
                showReferenceImporter: { showingReferenceImporter = true },
                runReview: runReview
            )
        )
    }

    private func configureDraftRecovery() {
        draftRecoveryCoordinator.configure(
            title: activeFileURL?.lastPathComponent ?? "Untitled.md",
            fileURL: activeFileURL,
            projectRootURL: projectStore.rootURL,
            text: activeText
        )
    }

    private func applyPendingProjectPolishIfNeeded() {
        guard let changeSet = pendingProjectPolishApply else { return }
        pendingProjectPolishApply = nil
        Task { @MainActor in
            // Let AppKit restore the Markdown editor as first responder before registering
            // the transaction, so the standard Edit menu and Command-Z use this stack.
            await Task.yield()
            let documentUndoManager = suppliedUndoManager
                ?? undoManager
                ?? NSApp.keyWindow?.firstResponder?.undoManager
                ?? NSApp.keyWindow?.undoManager
            projectStore.attachUndoManager(documentUndoManager)
            if !projectStore.applyRevisionChangeSet(changeSet) {
                viewModel.errorMessage = projectStore.errorMessage
                    ?? "Kistulentz left every file unchanged."
            }
        }
    }

#if UI_TEST_HOST
    private func configureUITestProjectIfNeeded() {
        guard !didConfigureUITestProject else { return }
        didConfigureUITestProject = true
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["KISTULENTZ_UI_TEST_PROJECT_PATH"], !path.isEmpty else { return }

        let root = URL(fileURLWithPath: path, isDirectory: true)
        do {
            if WritingProjectDisk.hasManifest(at: root) {
                try projectStore.openProject(at: root)
            } else {
                let name = environment["KISTULENTZ_UI_TEST_PROJECT_NAME"]
                    ?? root.lastPathComponent
                let kind = WritingProjectKind(
                    rawValue: environment["KISTULENTZ_UI_TEST_PROJECT_KIND"] ?? "fiction"
                ) ?? .fiction
                try projectStore.prepareAndOpenProject(at: root, name: name, kind: kind)
            }
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    /// XCTest's macOS keyboard driver can select text in the AppKit editor while silently
    /// discarding replacement characters on headless runners. This file-backed command is
    /// available only in the UI-test host and exercises the same binding, undo coordinator,
    /// autosave, and recovery pipeline as a user edit without changing production launches.
    @MainActor
    private func monitorUITestEditCommand() async {
        guard let path = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_EDIT_COMMAND_PATH"] else {
            return
        }
        let url = URL(fileURLWithPath: path)
        while !Task.isCancelled {
            if let replacement = try? String(contentsOf: url, encoding: .utf8),
               !replacement.isEmpty,
               replacement != lastUITestEditCommand {
                lastUITestEditCommand = replacement
                if replacement == "__KISTULENTZ_UNDO__" {
                    uiTestEditUndoManager.undo()
                    continue
                }
                if replacement == "__KISTULENTZ_REDO__" {
                    uiTestEditUndoManager.redo()
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_UNDO__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    manager?.undo()
                    writeUITestProjectUndoStatus(manager: manager, operation: "undo")
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_REDO__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    manager?.redo()
                    writeUITestProjectUndoStatus(manager: manager, operation: "redo")
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_UNDO_STATUS__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    writeUITestProjectUndoStatus(manager: manager, operation: "status")
                    continue
                }
                if projectStore.isOpen {
                    projectStore.prepareForProgrammaticEdit(reason: "Before UI test edit")
                }
                projectStore.attachUndoManager(uiTestEditUndoManager)
                undoCoordinator.replaceText(
                    with: replacement,
                    binding: activeTextBinding,
                    undoManager: uiTestEditUndoManager,
                    actionName: "UI Test Edit"
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func writeUITestProjectUndoStatus(manager: UndoManager?, operation: String) {
        guard let statusPath = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_STATUS_PATH"] else {
            return
        }
        let status = [
            "operation=\(operation)",
            "manager=\(manager != nil)",
            "canUndo=\(manager?.canUndo == true)",
            "canRedo=\(manager?.canRedo == true)",
            "undoName=\(manager?.undoActionName ?? "none")",
            "redoName=\(manager?.redoActionName ?? "none")",
            "grouping=\(manager?.groupingLevel ?? -1)",
            "error=\(projectStore.errorMessage ?? "none")",
            "text=\(projectStore.text.debugDescription)"
        ].joined(separator: ",")
        try? status.write(
            to: URL(fileURLWithPath: statusPath),
            atomically: true,
            encoding: .utf8
        )
    }
#endif

    private func presentStartupIfNeeded() {
        guard !didPresentStartup else { return }
        didPresentStartup = true
        if !draftRecovery.pendingEntries.isEmpty {
            presentation.present(.draftRecovery)
        } else {
            presentNextStartupStep()
        }
    }

    private func presentWelcomeAfterRecovery() {
        presentNextStartupStep()
    }

    private func presentNextStartupStep() {
        beneparPack.refresh()
        if !beneparPack.isInstalled, settings.claimEnglishPackPrompt() {
            presentation.present(.englishPackPrompt)
        } else if !settings.hasCompletedOnboarding {
            presentation.present(.welcome)
        } else if settings.shouldPresentWhatsNew(for: AppSettings.appVersion()) {
            presentation.present(.whatsNew)
        }
    }

    private func finishEnglishPackPrompt() {
        settings.acknowledgeEnglishPackPrompt()
        presentation.dismiss(.englishPackPrompt)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            presentNextStartupStep()
        }
    }

    private func completeWelcome() {
        settings.completeOnboarding()
        settings.acknowledgeWhatsNew(for: AppSettings.appVersion())
        presentation.dismiss(.welcome)
    }

    private func finishWhatsNew() {
        settings.acknowledgeWhatsNew(for: AppSettings.appVersion())
        presentation.dismiss(.whatsNew)
    }

    private func beginProjectFromWelcome() {
        completeWelcome()
        projectFolderAction = .createInParent
        showingProjectFolderImporter = true
    }

    private func openDocumentFromWelcome() {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Open a Markdown Document"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImportedMarkdown(url)
    }

    private func beginImportFromWelcome() {
        completeWelcome()
        presentation.present(.projectImportAssistant)
    }

    private func createSampleProject(_ kind: WritingProjectKind) {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for the \(kind.title) Sample"
        panel.message = "Kistulentz will create a new editable sample-project folder here without replacing existing files."
        panel.prompt = "Create Sample Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        do {
            let root = try SampleProjectBuilder.create(in: parent, kind: kind)
            try projectStore.openProject(at: root)
            activateProject()
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    private func chooseDocumentForImport() {
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

    private func saveImportedDocument(
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

    private func openImportedMarkdown(_ url: URL) {
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

    private func completeProjectImport(_ completion: ProjectImportCompletion) {
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

    private func runReview() {
        guard settings.isProviderReady(settings.provider) else {
            runLocalPolish()
            return
        }
        let style = projectStore.isOpen ? styleLearningStore.styleText : nil
        let reference = viewModel.referenceBook.map {
            WritingAIService.referenceContext($0, relevantTo: activeText)
        }
        pendingAIRequest = AIRequestPreview(
            purpose: .polish(targetGrade: settings.targetGrade),
            provider: settings.provider,
            model: settings.model(for: settings.provider),
            primaryLabel: "Markdown draft",
            primaryText: activeText,
            styleGuide: style,
            includesStyleGuide: style?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            referenceContext: reference,
            includesReferenceContext: reference != nil,
            sourceRange: nil,
            sourceText: activeText
        )
    }

    private func runLocalPolish() {
        let styleDecisions = projectStore.rootURL.flatMap {
            try? ProjectStyleManager.loadDecisions(at: $0)
        } ?? []
        let result = LocalPolishService.polish(
            text: activeText,
            targetGrade: settings.targetGrade,
            issues: viewModel.visibleLocalIssues,
            styleDecisions: styleDecisions
        )
        guard let plan = result.plan else {
            let advisory = result.advisoryCount == 0
                ? "No local correction is needed."
                : "\(result.advisoryCount) advisory highlight\(result.advisoryCount == 1 ? " remains" : "s remain") for your judgment."
            viewModel.errorMessage = "Local Polish found no concrete change it could make safely. \(advisory) Set up Ollama for private generative rewriting, or connect OpenAI or Anthropic for cloud rewriting."
            return
        }
        polishedDraftPlan = plan
    }

    private func insertCitation(_ source: ResearchSource, locator: String) {
        let citation = CitationFormatter.markdownCitation(for: source, locator: locator)
        let current = activeText as NSString
        let selectionStart = editorSelection.location == NSNotFound
            ? current.length
            : min(max(0, editorSelection.location), current.length)
        let selectionLength = min(max(0, editorSelection.length), current.length - selectionStart)
        let safeLocation = selectionStart + selectionLength
        let range = NSRange(location: safeLocation, length: 0)
        let updated = current.replacingCharacters(in: range, with: citation)
        if projectStore.isOpen { projectStore.prepareForProgrammaticEdit(reason: "Before inserting citation") }
        undoCoordinator.replaceText(
            with: updated,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Insert Citation"
        )
        editorSelection = NSRange(location: safeLocation + (citation as NSString).length, length: 0)
    }

    private func navigateToRevisionFinding(_ finding: SystemicRevisionFinding) {
        guard let path = finding.chapterPath else { return }
        projectStore.selectChapter(path)
        Task { @MainActor in
            await Task.yield()
            let source = projectStore.text as NSString
            guard !finding.excerpt.isEmpty else { return }
            let range = source.range(of: finding.excerpt)
            guard range.location != NSNotFound else { return }
            editorSelection = range
            viewModel.focus(on: range)
        }
    }

    private var destinkCurrentDocument: ManuscriptDocument {
        ManuscriptDocument(
            relativePath: projectStore.selectedChapterPath ?? fileURL?.lastPathComponent ?? "Untitled.md",
            title: projectStore.isOpen
                ? projectStore.selectedChapterTitle
                : (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"),
            text: activeText
        )
    }

    /// Load the manuscript once, when the review is opened, instead of on every re-render of the
    /// sheet's builder — reading every chapter from disk is main-thread work.
    private func presentDestinker() {
        destinkManuscriptDocuments = projectStore.isOpen
            ? (try? projectStore.betaReadersStore.documents(for: .manuscript, selection: nil))
            : nil
        presentation.present(.destinker)
    }

    private func navigateToDestinkFinding(_ path: String, range: NSRange) {
        if projectStore.isOpen, path != projectStore.selectedChapterPath {
            projectStore.selectChapter(path)
        }
        Task { @MainActor in
            await Task.yield()
            let source = activeText as NSString
            guard range.location >= 0, NSMaxRange(range) <= source.length else { return }
            editorSelection = range
            viewModel.focus(on: range)
        }
    }

    private var selectedPassage: (range: NSRange, text: String)? {
        let source = activeText as NSString
        guard editorSelection.location != NSNotFound,
              editorSelection.length > 0,
              NSMaxRange(editorSelection) <= source.length else { return nil }
        return (editorSelection, source.substring(with: editorSelection))
    }

    private func prepareRewrite(_ goal: SelectionRewriteGoal) {
        guard let selectedPassage else {
            viewModel.errorMessage = "Select a passage before choosing a rewrite."
            return
        }
        prepareRewrite(goal, passage: selectedPassage)
    }

    private func prepareRewrite(
        _ goal: SelectionRewriteGoal,
        passage selectedPassage: (range: NSRange, text: String)
    ) {
        guard validateSelectedProvider() else { return }
        if goal.kind == .matchReferences, viewModel.referenceBook == nil {
            viewModel.errorMessage = "Choose at least one reference before matching its craft profile."
            return
        }

        let style = projectStore.isOpen ? styleLearningStore.styleText : nil
        let reference = viewModel.referenceBook.map {
            WritingAIService.referenceContext($0, relevantTo: selectedPassage.text, maxCharacters: 16_000)
        }
        pendingAIRequest = AIRequestPreview(
            purpose: .selectionRewrite(goal: goal, targetGrade: settings.targetGrade),
            provider: settings.provider,
            model: settings.model(for: settings.provider),
            primaryLabel: "Selected Markdown",
            primaryText: selectedPassage.text,
            styleGuide: style,
            includesStyleGuide: style?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            referenceContext: reference,
            includesReferenceContext: reference != nil,
            sourceRange: selectedPassage.range,
            sourceText: selectedPassage.text
        )
    }

    private func prepareRewrite(_ issue: WritingIssue) {
        let source = activeText as NSString
        let range: NSRange
        if issue.range.location != NSNotFound,
           NSMaxRange(issue.range) <= source.length,
           source.substring(with: issue.range) == issue.excerpt {
            range = issue.range
        } else {
            let relocated = source.range(of: issue.excerpt)
            guard relocated.location != NSNotFound,
                  source.range(of: issue.excerpt, options: [], range: NSRange(
                    location: NSMaxRange(relocated),
                    length: source.length - NSMaxRange(relocated)
                  )).location == NSNotFound else {
                viewModel.errorMessage = "That passage changed, so Kistulentz cannot rewrite it safely."
                return
            }
            range = relocated
        }

        let kind: SelectionRewriteKind
        switch issue.category {
        case .spelling, .grammar:
            kind = .correct
        case .adverb, .passiveVoice:
            kind = .strengthenVerbs
        case .referenceVoice where viewModel.referenceBook != nil:
            kind = .matchReferences
        case .hardSentence, .veryHardSentence, .structuralComplexity, .complexPhrase,
             .aiTell, .aiSuggestion, .referenceVoice, .continuity:
            kind = .simplify
        }

        editorSelection = range
        viewModel.focus(on: range)
        prepareRewrite(
            SelectionRewriteGoal(
                kind: kind,
                requestedTone: nil,
                issueInstruction: issue.message
            ),
            passage: (range, source.substring(with: range))
        )
    }

    private func validateSelectedProvider() -> Bool {
        let provider = settings.provider
        guard settings.isProviderReady(provider) else {
            viewModel.errorMessage = provider.requiresAPIKey
                ? "Add your \(provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return false
        }
        return true
    }

    private func executeAIRequest(_ request: AIRequestPreview) {
        switch request.purpose {
        case .polish:
            viewModel.runAIReview(request: request, matching: activeText, settings: settings)
        case .selectionRewrite:
            viewModel.runSelectionRewrite(request: request, settings: settings)
        case .referenceDeepening, .manuscriptReport, .manuscriptBible, .betaReader, .outlineSynopsis, .systemicRevision:
            break
        }
    }

    private func applyRewrite(
        _ alternative: RewriteAlternative,
        presentation: SelectionRewritePresentation
    ) {
        guard let result = SelectionReplacementPlanner.replace(
            in: activeText,
            range: presentation.sourceRange,
            expected: presentation.sourceText,
            with: alternative.text
        ) else {
            viewModel.errorMessage = "That passage changed after the alternatives were created. Select it again and rerun the rewrite."
            viewModel.rewritePresentation = nil
            return
        }
        let localConflicts = SuggestionRuleValidator.introducedCategories(
            replacing: presentation.sourceRange,
            in: activeText,
            with: alternative.text,
            targetGrade: settings.targetGrade
        )
        let documentConflicts = SuggestionRuleValidator.introducedCategories(
            original: activeText,
            replacement: result,
            targetGrade: settings.targetGrade
        )
        let conflicts = IssueCategory.allCases.filter { category in
            localConflicts.contains(category) || documentConflicts.contains(category)
        }
        guard conflicts.isEmpty else {
            viewModel.errorMessage = "That alternative introduces a new local flag (\(conflicts.map(\.title).joined(separator: ", "))), so Kistulentz did not apply it."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before selection rewrite")
        undoCoordinator.replaceText(
            with: result,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: presentation.goal.title
        )
        let replacementRange = NSRange(
            location: presentation.sourceRange.location,
            length: (alternative.text as NSString).length
        )
        editorSelection = replacementRange
        viewModel.focus(on: replacementRange)
        viewModel.rewritePresentation = nil
    }

    private func preparePolishedDraftReview() {
        guard let review = viewModel.aiReview else { return }
        let plan = PolishedDraftPlanner.plan(
            original: activeText,
            polished: review.polishedText,
            targetGrade: settings.targetGrade
        )
        guard !plan.changes.isEmpty else {
            viewModel.errorMessage = "The polished draft already matches this document."
            return
        }
        polishedDraftPlan = plan
    }

    private func applyPolishedChanges(_ changeIDs: Set<UUID>, from plan: PolishedDraftPlan) {
        guard activeText == plan.sourceText else {
            polishedDraftPlan = nil
            viewModel.errorMessage = "The document changed while the polished draft was open. Reopen it to review an updated comparison."
            return
        }
        guard !changeIDs.isEmpty, let result = plan.applying(changeIDs: changeIDs) else {
            viewModel.errorMessage = "Select at least one safe passage to apply."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before applying polished passages")
        undoCoordinator.replaceText(
            with: result,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: changeIDs.count == 1 ? "Apply Polished Passage" : "Apply Polished Passages"
        )
        viewModel.preserveAIReview(afterApplying: result)
        polishedDraftPlan = nil
    }

    private func replaceWithPolishedDraft(from plan: PolishedDraftPlan) {
        guard activeText == plan.sourceText else {
            polishedDraftPlan = nil
            viewModel.errorMessage = "The document changed while the polished draft was open. Reopen it to review an updated comparison."
            return
        }
        guard plan.isFullReplacementSafe else {
            viewModel.errorMessage = "Resolve or decline the passages that conflict with local rules before replacing the document."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before polished draft")
        undoCoordinator.replaceText(
            with: plan.polishedText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: plan.origin == .local ? "Use Local Polish" : "Use Polished Draft"
        )
        viewModel.preserveAIReview(afterApplying: plan.polishedText)
        polishedDraftPlan = nil
    }

    private func apply(_ issue: WritingIssue) {
        if let replacement = issue.replacement {
            let conflicts = SuggestionRuleValidator.introducedCategories(
                original: issue.excerpt,
                replacement: replacement,
                targetGrade: settings.targetGrade
            )
            guard conflicts.isEmpty else {
                viewModel.errorMessage = "That suggestion now conflicts with a local rule, so Kistulentz did not apply it."
                return
            }
        }
        let plan = SuggestionApplicationPlanner.planSingle(issue: issue, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = "That passage has changed, so the suggestion can no longer be applied."
            return
        }
        guard SuggestionRuleValidator.isSafe(
            original: activeText,
            replacement: plan.resultText,
            targetGrade: settings.targetGrade
        ) else {
            viewModel.errorMessage = "That suggestion creates a new local flag in its surrounding passage, so Kistulentz did not apply it."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before accepting suggestion")
        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Accept Suggestion"
        )
        styleLearningStore.recordStyleDecision(action: .accepted, issue: issue)
        viewModel.preserveAIReview(afterAccepting: issue, in: plan.resultText)
    }

    private func decline(_ issue: WritingIssue) {
        if viewModel.decline(issue, in: activeText) {
            styleLearningStore.recordStyleDecision(action: .declined, issue: issue)
        }
    }

    private func prepareApplyAll() {
        let safeIssues = viewModel.allIssues.filter { issue in
            guard let replacement = issue.replacement else { return true }
            return SuggestionRuleValidator.isSafe(
                original: issue.excerpt,
                replacement: replacement,
                targetGrade: settings.targetGrade
            )
        }
        let plan = SuggestionApplicationPlanner.plan(issues: safeIssues, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = plan.conflictCount > 0 || plan.staleCount > 0
                ? "The available replacements overlap or no longer match this draft. Apply them one at a time."
                : "No current suggestions include a concrete replacement."
            return
        }
        guard SuggestionRuleValidator.isSafe(
            original: activeText,
            replacement: plan.resultText,
            targetGrade: settings.targetGrade
        ) else {
            viewModel.errorMessage = "Applying those suggestions together would create a new local flag. Apply them one at a time instead."
            return
        }
        pendingApplyAllPlan = plan
    }

    private func applyAll(_ plan: SuggestionApplicationPlan) {
        let appliedIDs = Set(plan.appliedIssueIDs)
        let appliedIssues = viewModel.allIssues.filter { appliedIDs.contains($0.id) }
        projectStore.prepareForProgrammaticEdit(reason: "Before applying all suggestions")
        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Apply All Suggestions"
        )
        for issue in appliedIssues {
            styleLearningStore.recordStyleDecision(action: .accepted, issue: issue)
        }
        viewModel.preserveAIReview(afterApplying: plan.resultText)
        pendingApplyAllPlan = nil
    }

    private func handleProjectFolderResult(_ result: Result<[URL], Error>) {
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

    private func configureProject(
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

    private func activateProject() {
        undoManager?.removeAllActions()
        viewModel.clearAIReview()
        viewModel.configureDocument(url: projectStore.selectedFileURL, text: projectStore.text)
        viewModel.scheduleAnalysis(
            text: projectStore.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }

    private func closeProject() {
        projectStore.closeProject()
        undoManager?.removeAllActions()
        viewModel.clearAIReview()
        viewModel.configureDocument(url: fileURL, text: document.text)
        viewModel.scheduleAnalysis(
            text: document.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }

    private func selectSearchResult(_ result: ProjectSearchResult) {
        projectStore.selectChapter(result.chapterPath)
        Task { @MainActor in
            await Task.yield()
            viewModel.focus(on: result.range)
        }
    }

    private func applyAllButtonTitle(for plan: SuggestionApplicationPlan) -> String {
        "Apply \(plan.appliedCount) \(plan.appliedCount == 1 ? "Change" : "Changes")"
    }

    private func applyAllMessage(for plan: SuggestionApplicationPlan) -> String {
        var parts = [
            "Kistulentz will apply \(plan.appliedCount) concrete, non-overlapping \(plan.appliedCount == 1 ? "change" : "changes") as one edit."
        ]
        if plan.conflictCount > 0 {
            parts.append("\(plan.conflictCount) overlapping \(plan.conflictCount == 1 ? "suggestion" : "suggestions") will be skipped.")
        }
        if plan.staleCount > 0 {
            parts.append("\(plan.staleCount) changed \(plan.staleCount == 1 ? "passage" : "passages") will be skipped.")
        }
        if plan.advisoryCount > 0 {
            parts.append("Advisory highlights without replacement text will remain.")
        }
        parts.append("You can undo the entire edit with Command-Z.")
        return parts.joined(separator: " ")
    }
}

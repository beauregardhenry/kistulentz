import AppKit
import SwiftUI
import UniformTypeIdentifiers

// `internal` (module-visible), not `private`, on this type and the properties below that are
// used from more than one of EditorWorkspace's extension files (+Startup, +ProjectLifecycle,
// +EditingActions, +UITestHarness) -- Swift's `private` is file-scoped, so state and helpers
// shared across those files must be at least `internal`, the same tradeoff already made when
// WritingProjectStore was split into per-concern files. Nothing here is exposed outside the
// module: `internal` still fully protects it from other targets.
enum ProjectFolderAction {
    case createInParent
    case openExisting
}

struct PendingProjectConfiguration: Identifiable {
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

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var beneparPack: BeneparLanguagePackManager
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @EnvironmentObject var researchLibrary: ResearchLibraryStore
    @EnvironmentObject var draftRecovery: DraftRecoveryManager
    @EnvironmentObject private var customFonts: CustomFontStore
    @EnvironmentObject var writingGrowth: WritingGrowthStore
    @Environment(\.undoManager) var undoManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var viewModel = EditorViewModel()
    @StateObject var undoCoordinator = DocumentUndoCoordinator()
    @StateObject var projectStore: WritingProjectStore
    @StateObject var draftRecoveryCoordinator = DraftRecoveryCoordinator()
    @StateObject var presentation = EditorWorkspacePresentation()
    @StateObject var documentImport = DocumentImportCoordinator()
    @State var polishedDraftPlan: PolishedDraftPlan?
    @State var pendingApplyAllPlan: SuggestionApplicationPlan?
    @State private var showingReferenceImporter = false
    @State private var selectedLibraryReferences: Set<String> = []
    @State private var isWriteMode = false
    @State var showingProjectFolderImporter = false
    @State var projectFolderAction: ProjectFolderAction = .openExisting
    @State var pendingProjectConfiguration: PendingProjectConfiguration?
    @State var destinkManuscriptDocuments: [ManuscriptDocument]?
    @State var editorSelection = NSRange(location: 0, length: 0)
    @State var pendingAIRequest: AIRequestPreview?
    @State var pendingProjectPolishApply: RevisionChangeSet?
    @State var selfEditExercisePresentation: SelfEditExercisePresentation?
    @State var didPresentStartup = false
#if UI_TEST_HOST
    @State var didConfigureUITestProject = false
    @State var lastUITestEditCommand = ""
    @State var uiTestEditUndoManager = UndoManager()
#endif

    private let epubType = UTType(importedAs: "org.idpf.epub-container")

    // Deliberately NOT a stored `@ObservedObject` property -- that was tried and measurably
    // failed: `@StateObject` uniquely ignores `wrappedValue` on every init after the first,
    // keeping `projectStore` itself alive across SwiftUI's routine view-struct re-inits, but
    // reading `projectStore`'s own `styleLearningStore` at init time (even via
    // `_projectStore.wrappedValue`, before `@StateObject` has actually installed its persistence
    // for this render) does not reliably return that same kept-alive instance -- confirmed
    // directly by comparing `ObjectIdentifier`s at runtime: `projectStore.styleLearningStore`
    // and a stored `@ObservedObject` seeded that way were two different objects, the second one
    // never touched by `WritingProjectStore.install()`. A computed property has no such
    // trap -- it re-resolves `projectStore.styleLearningStore` (a plain, stable stored property
    // read, not an init-time snapshot) on every access, always returning the one real instance
    // `projectStore` itself mutates. `.onChange`/`.onAppear` below don't need this to be an
    // independently-tracked `@ObservedObject` to see updates: they still re-run on every
    // `EditorWorkspace` re-render, which `projectStore`'s own `@StateObject` tracking already
    // triggers whenever `WritingProjectStore.install()` changes its other `@Published` state
    // alongside `styleLearningStore` (which project open/close always does).
    var styleLearningStore: StyleLearningStore { projectStore.styleLearningStore }

    init(
        document: Binding<MarkdownDocument>,
        fileURL: URL?,
        suppliedUndoManager: UndoManager? = nil
    ) {
        _document = document
        self.fileURL = fileURL
        self.suppliedUndoManager = suppliedUndoManager
        _projectStore = StateObject(wrappedValue: WritingProjectStore())
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
                        isRewriting: viewModel.isRewriting,
                        hasAPIKey: settings.isProviderReady(settings.provider),
                        isPracticeModeEnabled: settings.isPracticeModeEnabled,
                        reference: viewModel.referenceBook,
                        alignment: viewModel.referenceAlignment,
                        isLoadingReference: viewModel.isLoadingReference,
                        onRunReview: runReview,
                        onChooseReference: { presentation.present(.referenceLibrary) },
                        onRemoveReference: viewModel.clearReference,
                        onSelect: viewModel.focus,
                        onApply: apply,
                        onDecline: decline,
                        onRewrite: prepareRewrite,
                        onApplyAll: prepareApplyAll
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
            let customFontsStore = customFonts
            projectStore.publicationStore.availableCustomFonts = { [weak customFontsStore] in
                customFontsStore?.fonts ?? []
            }
            projectStore.publicationStore.customFontFileURL = { [weak customFontsStore] record in
                customFontsStore?.fileURL(for: record) ?? URL(fileURLWithPath: record.storedFilename)
            }
#if UI_TEST_HOST
            configureUITestProjectIfNeeded()
#endif
            reopenLastProjectIfNeeded()
            viewModel.configureDocument(url: activeFileURL, text: activeText)
            viewModel.updateStyleDecisions(styleLearningStore.styleDecisions)
            viewModel.updateAvoidedWords(ProjectStyleManager.avoidedWords(from: styleLearningStore.styleText))
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
        .onChange(of: styleLearningStore.styleText) { _, newValue in
            viewModel.updateAvoidedWords(ProjectStyleManager.avoidedWords(from: newValue))
            viewModel.scheduleAnalysis(text: activeText, targetGrade: settings.targetGrade, immediately: true)
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
            ProjectOrganizationView(
                store: projectStore,
                styleLearningStore: styleLearningStore,
                reference: viewModel.referenceBook,
                projectUndoManager: suppliedUndoManager ?? undoManager ?? NSApp.keyWindow?.undoManager
            )
                .environmentObject(settings)
        }
        .sheet(isPresented: presentation.binding(for: .namedSnapshot)) {
            NamedSnapshotSheet(chapterTitle: projectStore.selectedChapterTitle) { name in
                projectStore.createSnapshot(name: name, reason: "Named snapshot")
            }
        }
        .sheet(isPresented: presentation.binding(for: .writingGrowth)) {
            WritingGrowthView(store: writingGrowth)
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
        .sheet(item: $selfEditExercisePresentation) { presentation in
            SelfEditExerciseView(exercises: presentation.exercises)
        }
    }

    /// Whichever of the shared alert's four error sources is currently active. At most one is
    /// ever non-nil at a time in practice, but the order mirrors the alert's own precedence.
    private var activeErrorMessage: String? {
        viewModel.errorMessage
            ?? projectStore.errorMessage
            ?? documentImport.errorMessage
            ?? draftRecovery.errorMessage
    }

    /// Whether the active error came from an AI provider request (a missing/invalid API key, a
    /// provider HTTP error, an unreachable Ollama, or a network failure reaching one) -- in which
    /// case Settings, where every provider is configured, is the obvious next stop.
    private var activeErrorIsProviderRelated: Bool {
        activeErrorMessage.map(WritingAIError.looksLikeProviderRelatedMessage) ?? false
    }

    var body: some View {
        projectConfiguredView.alert("Kistulentz", isPresented: Binding(
            get: {
                viewModel.errorMessage != nil
                    || projectStore.errorMessage != nil
                    || documentImport.errorMessage != nil
                    || draftRecovery.errorMessage != nil
            },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    projectStore.errorMessage = nil
                    documentImport.errorMessage = nil
                    draftRecovery.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
            if activeErrorIsProviderRelated {
                Button("Open Settings") { openSettings() }
            }
        } message: {
            Text(activeErrorMessage ?? "")
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

    var activeText: String {
        projectStore.isOpen ? projectStore.text : document.text
    }

    var activeTextBinding: Binding<String> {
        if projectStore.isOpen {
            return Binding(
                get: { projectStore.text },
                set: { projectStore.updateText($0) }
            )
        }
        return $document.text
    }

    var activeFileURL: URL? {
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
                createProject: { requestProjectFolder(.createInParent) },
                openProject: { requestProjectFolder(.openExisting) },
                showWritingGrowth: { presentation.present(.writingGrowth) },
                showSelfEditExercises: {
                    selfEditExercisePresentation = SelfEditExercisePresentation(
                        exercises: SelfEditExerciseSampler.sample(
                            from: viewModel.allIssues,
                            weights: SelfEditExerciseSampler.weights(from: writingGrowth.months)
                        )
                    )
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

    func configureDraftRecovery() {
        draftRecoveryCoordinator.configure(
            title: activeFileURL?.lastPathComponent ?? "Untitled.md",
            fileURL: activeFileURL,
            projectRootURL: projectStore.rootURL,
            text: activeText
        )
    }

    func applyPendingProjectPolishIfNeeded() {
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

    private func selectSearchResult(_ result: ProjectSearchResult) {
        projectStore.selectChapter(result.chapterPath)
        Task { @MainActor in
            await Task.yield()
            viewModel.focus(on: result.range)
        }
    }
}

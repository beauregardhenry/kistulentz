import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var analysis = AnalysisResult.empty
    @Published private(set) var structuralProfile: StructuralProfile?
    @Published private(set) var isUsingBenepar = false
    @Published private(set) var isAnalyzingStructure = false
    @Published private(set) var systemIssues: [WritingIssue] = []
    @Published private(set) var referenceBook: EPUBReference?
    @Published private(set) var referenceAlignment = ReferenceAlignment.empty
    @Published private(set) var isLoadingReference = false
    @Published private(set) var isRewriting = false
    @Published var rewritePresentation: SelectionRewritePresentation?
    @Published private(set) var isFindingCraftExample = false
    @Published private(set) var craftExamples: [IssueCategory: CraftExampleService.Lookup] = [:]
    @Published private(set) var dismissedSuggestions: [DismissedSuggestion] = []
    @Published private(set) var styleDecisions: [ProjectStyleDecision] = []
    @Published var errorMessage: String?
    @Published var focusRequest: FocusRequest?

    private var analysisTask: Task<Void, Never>?
    private var analysisRequestID = UUID()
    private var rewriteTask: Task<Void, Never>?
    private var craftExampleTask: Task<Void, Never>?
    private var referenceTask: Task<Void, Never>?
    private var currentText = ""
    private var currentDocumentKey: String?
    private var avoidedWords: [String] = []
    private var hasConfiguredDocument = false
    private let rewriteService: SelectionRewriteService
    private let craftExampleService: CraftExampleService
    private let dismissalStore: DismissedSuggestionStore
    private let structuralAnalyzerOverride: ((String, Int, Bool, Bool) async -> BeneparAnalysis?)?

    /// Set externally by whoever owns this view model (`EditorWorkspace`, wiring the app-wide
    /// `WritingActivityStore`) rather than constructor-injected: `viewModel` is created in a
    /// `@StateObject` property initializer, before `@EnvironmentObject`s are available, the same
    /// timing constraint `WritingProjectStore.onDidSaveChapter` already works around.
    var onQualitySample: ((_ issueCount: Int, _ wordCount: Int) -> Void)?

    /// `structuralAnalyzerOverride` is nil in production, in which case `runStructuralAnalyzer`
    /// below calls straight through to the real, shared Benepar singleton -- which can't be
    /// swapped once `.shared` is referenced directly, so a default *value* pointing at it (rather
    /// than a branch taken in a method body) would hit Swift's actor-isolation check on this
    /// `@MainActor` type's init. Tests inject a fake analyzer the same way
    /// `ReferenceLibraryStore.structuralAnalyzer` does.
    init(
        dismissalStore: DismissedSuggestionStore = DismissedSuggestionStore(),
        rewriteService: SelectionRewriteService = SelectionRewriteService(),
        craftExampleService: CraftExampleService = CraftExampleService(),
        structuralAnalyzer: ((String, Int, Bool, Bool) async -> BeneparAnalysis?)? = nil
    ) {
        self.dismissalStore = dismissalStore
        self.rewriteService = rewriteService
        self.craftExampleService = craftExampleService
        self.structuralAnalyzerOverride = structuralAnalyzer
    }

    var allIssues: [WritingIssue] {
        ProjectStyleManager.filteringLearnedSuppressions(
            analysis.issues + systemIssues + referenceAlignment.issues,
            decisions: styleDecisions
        )
        .filter { !isDismissed($0) }
        .sorted {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }
    }

    var visibleLocalIssues: [WritingIssue] {
        ProjectStyleManager.filteringLearnedSuppressions(
            analysis.issues + systemIssues,
            decisions: styleDecisions
        ).filter { !isDismissed($0) }
    }

    /// Keeps the live editor's advisory suppression in sync with the project's learned decisions.
    /// Called whenever a project opens and whenever `StyleLearningStore.styleDecisions` changes
    /// (immediately after each accept/decline), so a threshold crossed by the decline that just
    /// happened hides the rest of that pattern in this document right away, not on the next edit.
    func updateStyleDecisions(_ decisions: [ProjectStyleDecision]) {
        styleDecisions = decisions
    }

    /// Keeps the live editor's local "avoid list" check (`ReadabilityEngine.avoidedWordIssues`,
    /// via `scheduleAnalysis`) in sync with the project's own "### Words to avoid" section
    /// (`ProjectStyleManager.avoidedWords`). Called whenever a project opens and whenever
    /// `StyleLearningStore.styleText` changes, so editing that list takes effect on the very next
    /// analysis pass rather than only after reopening the project.
    func updateAvoidedWords(_ words: [String]) {
        avoidedWords = words
    }

    func configureDocument(url: URL?, text: String) {
        let nextKey = url.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        currentText = text

        guard !hasConfiguredDocument || nextKey != currentDocumentKey else {
            pruneDismissals(for: text)
            return
        }

        let sessionSuggestions = hasConfiguredDocument && currentDocumentKey == nil
            ? dismissedSuggestions
            : []
        currentDocumentKey = nextKey
        hasConfiguredDocument = true

        if let nextKey {
            dismissedSuggestions = Array(Set(dismissalStore.suggestions(for: nextKey) + sessionSuggestions))
            pruneDismissals(for: text)
        } else if !sessionSuggestions.isEmpty {
            dismissedSuggestions = sessionSuggestions
        } else {
            dismissedSuggestions = []
        }
    }

    func scheduleAnalysis(text: String, targetGrade: Int, immediately: Bool = false) {
        let previousText = currentText
        currentText = text
        if previousText != text {
            systemIssues = []
            if isRewriting {
                rewriteTask?.cancel()
                isRewriting = false
            }
        }
        pruneDismissals(for: text)
        analysisTask?.cancel()
        isAnalyzingStructure = false
        let requestID = UUID()
        analysisRequestID = requestID
        analysisTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard let self, !Task.isCancelled, self.analysisRequestID == requestID else { return }
            let reference = self.referenceBook
            let avoidedWords = self.avoidedWords
            let computed = await Task.detached(priority: .userInitiated) {
                let result = ReadabilityEngine.analyze(text, targetGrade: targetGrade, avoidedWords: avoidedWords)
                let alignment = reference.map {
                    ReferenceComparison.analyze(draft: text, against: $0)
                } ?? .empty
                return (result, alignment)
            }.value
            guard !Task.isCancelled,
                  self.analysisRequestID == requestID,
                  self.currentText == text else { return }
            let (result, alignment) = computed
            let nativeIssues = await NativeWritingService.issues(in: text)
            guard !Task.isCancelled,
                  self.analysisRequestID == requestID,
                  self.currentText == text else { return }
            self.analysis = result
            self.systemIssues = nativeIssues
            self.referenceAlignment = alignment
            self.structuralProfile = nil
            self.isUsingBenepar = false
            self.onQualitySample?(self.allIssues.count, result.stats.words)

            if !immediately {
                try? await Task.sleep(for: .milliseconds(430))
            }
            guard !Task.isCancelled, self.analysisRequestID == requestID, self.currentText == text else { return }
            self.isAnalyzingStructure = true
            let parsed = await self.runStructuralAnalyzer(
                text: text,
                maximumSentences: 60,
                includeIssues: true,
                waitForAvailability: true
            )
            guard !Task.isCancelled, self.analysisRequestID == requestID, self.currentText == text else { return }
            self.isAnalyzingStructure = false
            guard let parsed else { return }
            self.structuralProfile = parsed.metrics
            self.isUsingBenepar = true
            self.analysis = BeneparAnalysisMerger.merge(native: result, benepar: parsed)
            self.referenceAlignment = self.referenceBook.map {
                ReferenceComparison.analyze(
                    draft: text,
                    against: $0,
                    draftStructure: parsed.metrics
                )
            } ?? .empty
        }
    }

    func importReference(from url: URL, draft: String) {
        referenceTask?.cancel()
        isLoadingReference = true
        errorMessage = nil

        referenceTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try EPUBProcessor.load(url: url) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let reference):
                let structure = await self.runStructuralAnalyzer(
                    text: ReferenceStructuralSampler.text(from: reference),
                    maximumSentences: 80,
                    includeIssues: false,
                    waitForAvailability: true
                )
                guard !Task.isCancelled else { return }
                let enriched = reference.addingStructuralProfile(structure?.metrics)
                self.referenceBook = enriched
                self.referenceAlignment = ReferenceComparison.analyze(
                    draft: draft,
                    against: enriched,
                    draftStructure: self.structuralProfile
                )
                self.isLoadingReference = false
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.isLoadingReference = false
            }
        }
    }

    func useReference(_ reference: EPUBReference, draft: String) {
        referenceTask?.cancel()
        referenceBook = reference
        referenceAlignment = ReferenceComparison.analyze(draft: draft, against: reference)
        isLoadingReference = false
    }

    func clearReference() {
        referenceTask?.cancel()
        referenceBook = nil
        referenceAlignment = .empty
        isLoadingReference = false
    }

    func runSelectionRewrite(request: AIRequestPreview, settings: AppSettings) {
        guard !isRewriting,
              case .selectionRewrite(let goal, _) = request.purpose,
              let sourceRange = request.sourceRange,
              let sourceText = request.sourceText else { return }

        isRewriting = true
        errorMessage = nil
        rewriteTask?.cancel()
        rewriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await rewriteService.rewrite(
                    request: request,
                    apiKey: settings.apiKey(for: request.provider)
                )
                guard !Task.isCancelled else { return }
                self.rewritePresentation = SelectionRewritePresentation(
                    goal: goal,
                    sourceRange: sourceRange,
                    sourceText: sourceText,
                    alternatives: result.alternatives
                )
                self.isRewriting = false
            } catch is CancellationError {
                self.isRewriting = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isRewriting = false
            }
        }
    }

    /// Session-only cache, keyed by category: once a category has an entry (`.found` or `.none`),
    /// repeat flags of the same category (an adverb flags constantly) show the cached result
    /// instantly instead of re-issuing an AI request. Cleared implicitly on relaunch since it's
    /// never persisted -- an intentional v1 scope decision, not an oversight.
    func runCraftExample(
        category: IssueCategory,
        request: AIRequestPreview,
        candidates: [CraftExampleService.Candidate],
        settings: AppSettings
    ) {
        guard craftExamples[category] == nil,
              !isFindingCraftExample,
              case .craftExample = request.purpose else { return }

        isFindingCraftExample = true
        errorMessage = nil
        craftExampleTask?.cancel()
        craftExampleTask = Task { [weak self] in
            guard let self else { return }
            do {
                let lookup = try await craftExampleService.find(
                    request: request,
                    candidates: candidates,
                    apiKey: settings.apiKey(for: request.provider)
                )
                guard !Task.isCancelled else { return }
                self.craftExamples[category] = lookup
                self.isFindingCraftExample = false
            } catch is CancellationError {
                self.isFindingCraftExample = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isFindingCraftExample = false
            }
        }
    }

    func focus(on issue: WritingIssue) {
        focusRequest = FocusRequest(id: UUID(), range: issue.range)
    }

    func focus(on range: NSRange) {
        focusRequest = FocusRequest(id: UUID(), range: range)
    }

    @discardableResult
    func decline(_ issue: WritingIssue, in text: String) -> Bool {
        currentText = text
        guard let dismissal = DismissedSuggestion(issue: issue, in: text) else {
            errorMessage = "That passage has changed, so the suggestion can no longer be declined."
            return false
        }
        guard !dismissedSuggestions.contains(dismissal) else { return true }
        dismissedSuggestions.append(dismissal)
        saveDismissals()
        return true
    }

    private func runStructuralAnalyzer(
        text: String,
        maximumSentences: Int,
        includeIssues: Bool,
        waitForAvailability: Bool
    ) async -> BeneparAnalysis? {
        if let structuralAnalyzerOverride {
            return await structuralAnalyzerOverride(text, maximumSentences, includeIssues, waitForAvailability)
        }
        return await BeneparService.shared.analyzeIfAvailable(
            text: text,
            maximumSentences: maximumSentences,
            includeIssues: includeIssues,
            waitForAvailability: waitForAvailability
        )
    }

    private func isDismissed(_ issue: WritingIssue) -> Bool {
        dismissedSuggestions.contains { $0.matches(issue, in: currentText) }
    }

    private func pruneDismissals(for text: String) {
        let remaining = dismissedSuggestions.filter { $0.passageStillExists(in: text) }
        guard remaining != dismissedSuggestions else { return }
        dismissedSuggestions = remaining
        saveDismissals()
    }

    private func saveDismissals() {
        guard let currentDocumentKey else { return }
        dismissalStore.save(dismissedSuggestions, for: currentDocumentKey)
    }
}

struct FocusRequest: Equatable {
    let id: UUID
    let range: NSRange
}

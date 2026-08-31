import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var analysis = AnalysisResult.empty
    @Published private(set) var structuralProfile: StructuralProfile?
    @Published private(set) var isUsingBenepar = false
    @Published private(set) var isAnalyzingStructure = false
    @Published private(set) var aiReview: AIReview?
    @Published private(set) var aiIssues: [WritingIssue] = []
    @Published private(set) var blockedAISuggestionCount = 0
    @Published private(set) var referenceBook: EPUBReference?
    @Published private(set) var referenceAlignment = ReferenceAlignment.empty
    @Published private(set) var isLoadingReference = false
    @Published private(set) var isReviewing = false
    @Published private(set) var isRewriting = false
    @Published var rewritePresentation: SelectionRewritePresentation?
    @Published private(set) var dismissedSuggestions: [DismissedSuggestion] = []
    @Published var errorMessage: String?
    @Published var focusRequest: FocusRequest?

    private var analysisTask: Task<Void, Never>?
    private var analysisRequestID = UUID()
    private var reviewTask: Task<Void, Never>?
    private var rewriteTask: Task<Void, Never>?
    private var referenceTask: Task<Void, Never>?
    private var reviewedTextFingerprints: Set<ReviewedTextFingerprint> = []
    private var reviewTargetGrade: Int?
    private var currentText = ""
    private var currentDocumentKey: String?
    private var hasConfiguredDocument = false
    private let service: WritingAIService
    private let rewriteService: SelectionRewriteService
    private let dismissalStore: DismissedSuggestionStore

    init(
        dismissalStore: DismissedSuggestionStore = DismissedSuggestionStore(),
        service: WritingAIService = WritingAIService(),
        rewriteService: SelectionRewriteService = SelectionRewriteService()
    ) {
        self.dismissalStore = dismissalStore
        self.service = service
        self.rewriteService = rewriteService
    }

    var allIssues: [WritingIssue] {
        (analysis.issues + referenceAlignment.issues + aiIssues)
            .filter { !isDismissed($0) }
            .sorted {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }
    }

    var visibleLocalIssues: [WritingIssue] {
        analysis.issues.filter { !isDismissed($0) }
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
            if isReviewing {
                reviewTask?.cancel()
                isReviewing = false
            }
            if isRewriting {
                rewriteTask?.cancel()
                isRewriting = false
            }
        }
        pruneDismissals(for: text)
        if aiReview != nil {
            let fingerprint = ReviewedTextFingerprint(text)
            if reviewTargetGrade == targetGrade, reviewedTextFingerprints.contains(fingerprint) {
                refreshAIReviewIssues(in: text)
            } else {
                clearAIReview()
            }
        }
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
            let computed = await Task.detached(priority: .userInitiated) {
                let result = ReadabilityEngine.analyze(text, targetGrade: targetGrade)
                let alignment = reference.map {
                    ReferenceComparison.analyze(draft: text, against: $0)
                } ?? .empty
                return (result, alignment)
            }.value
            guard !Task.isCancelled,
                  self.analysisRequestID == requestID,
                  self.currentText == text else { return }
            let (result, alignment) = computed
            self.analysis = result
            self.referenceAlignment = alignment
            self.structuralProfile = nil
            self.isUsingBenepar = false

            if !immediately {
                try? await Task.sleep(for: .milliseconds(430))
            }
            guard !Task.isCancelled, self.analysisRequestID == requestID, self.currentText == text else { return }
            self.isAnalyzingStructure = true
            let parsed = await BeneparService.shared.analyzeIfAvailable(
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
                let structure = await BeneparService.shared.analyzeIfAvailable(
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
                self.clearAIReview()
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
        clearAIReview()
    }

    func clearReference() {
        referenceTask?.cancel()
        referenceBook = nil
        referenceAlignment = .empty
        isLoadingReference = false
        clearAIReview()
    }

    func runAIReview(request: AIRequestPreview, matching sourceText: String, settings: AppSettings) {
        guard !isReviewing else { return }
        isReviewing = true
        errorMessage = nil

        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let review = try await service.review(
                    request: request,
                    apiKey: settings.apiKey(for: request.provider)
                )
                guard !Task.isCancelled else { return }
                guard self.currentText == sourceText else {
                    self.isReviewing = false
                    return
                }
                let targetGrade: Int
                if case .polish(let requestedGrade) = request.purpose {
                    targetGrade = requestedGrade
                } else {
                    targetGrade = settings.targetGrade
                }
                let suggestions = Self.makeIssues(
                    from: review.suggestions,
                    in: sourceText,
                    targetGrade: targetGrade
                )
                self.aiReview = review
                self.aiIssues = suggestions.issues
                self.blockedAISuggestionCount = suggestions.blockedCount
                self.reviewTargetGrade = targetGrade
                self.reviewedTextFingerprints = [ReviewedTextFingerprint(sourceText)]
                self.isReviewing = false
            } catch is CancellationError {
                self.isReviewing = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isReviewing = false
            }
        }
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

    func clearAIReview() {
        reviewTask?.cancel()
        isReviewing = false
        aiReview = nil
        aiIssues = []
        blockedAISuggestionCount = 0
        reviewTargetGrade = nil
        reviewedTextFingerprints = []
    }

    func preserveAIReview(afterAccepting issue: WritingIssue, in text: String) {
        guard let aiReview, let reviewTargetGrade else { return }
        currentText = text
        let result = Self.makeIssues(
            from: aiReview.suggestions,
            in: text,
            targetGrade: reviewTargetGrade
        )
        var refreshed = result.issues
        if issue.source == .ai {
            refreshed.removeAll {
                $0.category == issue.category
                    && $0.excerpt == issue.excerpt
                    && $0.replacement == issue.replacement
            }
        }
        aiIssues = refreshed
        blockedAISuggestionCount = result.blockedCount
        reviewedTextFingerprints.insert(ReviewedTextFingerprint(text))
    }

    func preserveAIReview(afterApplying text: String) {
        guard aiReview != nil else { return }
        currentText = text
        reviewedTextFingerprints.insert(ReviewedTextFingerprint(text))
        refreshAIReviewIssues(in: text)
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

    private func refreshAIReviewIssues(in text: String) {
        guard let aiReview, let reviewTargetGrade else { return }
        let result = Self.makeIssues(
            from: aiReview.suggestions,
            in: text,
            targetGrade: reviewTargetGrade
        )
        aiIssues = result.issues
        blockedAISuggestionCount = result.blockedCount
    }

    private static func makeIssues(
        from suggestions: [AISuggestion],
        in text: String,
        targetGrade: Int
    ) -> (issues: [WritingIssue], blockedCount: Int) {
        let source = text as NSString
        var blockedCount = 0
        let issues = suggestions.compactMap { suggestion -> WritingIssue? in
            var range = source.range(of: suggestion.original)
            if range.location == NSNotFound {
                range = source.range(of: suggestion.original, options: [.caseInsensitive])
            }
            guard range.location != NSNotFound else { return nil }
            let excerpt = source.substring(with: range)
            guard SuggestionRuleValidator.introducedCategories(
                replacing: range,
                in: text,
                with: suggestion.replacement,
                targetGrade: targetGrade
            ).isEmpty else {
                blockedCount += 1
                return nil
            }

            let category: IssueCategory
            switch suggestion.category.lowercased() {
            case "spelling": category = .spelling
            case "grammar": category = .grammar
            default: category = .aiSuggestion
            }

            return WritingIssue(
                category: category,
                range: range,
                excerpt: excerpt,
                message: suggestion.explanation,
                replacement: suggestion.replacement,
                source: .ai
            )
        }
        return (issues, blockedCount)
    }
}

private struct ReviewedTextFingerprint: Hashable {
    let utf16Length: Int
    let hash: Int

    init(_ text: String) {
        utf16Length = (text as NSString).length
        hash = text.hashValue
    }
}

struct FocusRequest: Equatable {
    let id: UUID
    let range: NSRange
}

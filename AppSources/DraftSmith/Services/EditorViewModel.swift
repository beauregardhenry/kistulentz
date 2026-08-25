import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var analysis = AnalysisResult.empty
    @Published private(set) var aiReview: AIReview?
    @Published private(set) var aiIssues: [WritingIssue] = []
    @Published private(set) var referenceBook: EPUBReference?
    @Published private(set) var referenceAlignment = ReferenceAlignment.empty
    @Published private(set) var isLoadingReference = false
    @Published private(set) var isReviewing = false
    @Published var errorMessage: String?
    @Published var focusRequest: FocusRequest?

    private var analysisTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var referenceTask: Task<Void, Never>?
    private var reviewedText: String?
    private let service = WritingAIService()

    var allIssues: [WritingIssue] {
        (analysis.issues + referenceAlignment.issues + aiIssues).sorted {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }
    }

    func scheduleAnalysis(text: String, targetGrade: Int, immediately: Bool = false) {
        if let reviewedText, reviewedText != text {
            aiReview = nil
            aiIssues = []
            self.reviewedText = nil
        }
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled else { return }
            let result = ReadabilityEngine.analyze(text, targetGrade: targetGrade)
            let alignment = self?.referenceBook.map { ReferenceComparison.analyze(draft: text, against: $0) } ?? .empty
            guard !Task.isCancelled else { return }
            self?.analysis = result
            self?.referenceAlignment = alignment
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
                self.referenceBook = reference
                self.referenceAlignment = ReferenceComparison.analyze(draft: draft, against: reference)
                self.isLoadingReference = false
                self.clearAIReview()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.isLoadingReference = false
            }
        }
    }

    func clearReference() {
        referenceTask?.cancel()
        referenceBook = nil
        referenceAlignment = .empty
        isLoadingReference = false
        clearAIReview()
    }

    func runAIReview(text: String, settings: AppSettings) {
        guard !isReviewing else { return }
        let provider = settings.provider
        guard let key = settings.apiKey(for: provider), !key.isEmpty else {
            errorMessage = "Add your \(provider.title) API key in Settings before running a review."
            return
        }

        let model = settings.model(for: provider)
        let grade = settings.targetGrade
        isReviewing = true
        errorMessage = nil

        reviewTask?.cancel()
        reviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let review = try await service.review(
                    text: text,
                    targetGrade: grade,
                    provider: provider,
                    model: model,
                    apiKey: key,
                    reference: self.referenceBook
                )
                guard !Task.isCancelled else { return }
                self.aiReview = review
                self.aiIssues = Self.makeIssues(from: review.suggestions, in: text)
                self.reviewedText = text
                self.isReviewing = false
            } catch is CancellationError {
                self.isReviewing = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isReviewing = false
            }
        }
    }

    func clearAIReview() {
        aiReview = nil
        aiIssues = []
        reviewedText = nil
    }

    func focus(on issue: WritingIssue) {
        focusRequest = FocusRequest(id: UUID(), range: issue.range)
    }

    private static func makeIssues(from suggestions: [AISuggestion], in text: String) -> [WritingIssue] {
        let source = text as NSString
        return suggestions.compactMap { suggestion in
            var range = source.range(of: suggestion.original)
            if range.location == NSNotFound {
                range = source.range(of: suggestion.original, options: [.caseInsensitive])
            }
            guard range.location != NSNotFound else { return nil }

            let category: IssueCategory
            switch suggestion.category.lowercased() {
            case "spelling": category = .spelling
            case "grammar": category = .grammar
            default: category = .aiSuggestion
            }

            return WritingIssue(
                category: category,
                range: range,
                excerpt: suggestion.original,
                message: suggestion.explanation,
                replacement: suggestion.replacement,
                source: .ai
            )
        }
    }
}

struct FocusRequest: Equatable {
    let id: UUID
    let range: NSRange
}

import Foundation

enum ProjectPolishStage: String, CaseIterable, Identifiable, Hashable {
    case correctness
    case readability
    case styleAndVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correctness: "1 · Spelling & Grammar"
        case .readability: "2 · Clarity & Readability"
        case .styleAndVoice: "3 · Style & Voice"
        }
    }

    var shortTitle: String {
        switch self {
        case .correctness: "Spelling & Grammar"
        case .readability: "Clarity & Readability"
        case .styleAndVoice: "Style & Voice"
        }
    }

    var systemImage: String {
        switch self {
        case .correctness: "text.badge.checkmark"
        case .readability: "eyeglasses"
        case .styleAndVoice: "quote.bubble"
        }
    }
}

struct ProjectPolishChange: Identifiable, Equatable {
    let id: UUID
    let chapterPath: String
    let chapterTitle: String
    let stage: ProjectPolishStage
    let categoryTitle: String
    let originalText: String
    var replacementText: String
    let explanation: String
    var isIncluded: Bool
    var conflict: String?

    init(
        id: UUID = UUID(),
        chapterPath: String,
        chapterTitle: String,
        stage: ProjectPolishStage,
        categoryTitle: String,
        originalText: String,
        replacementText: String,
        explanation: String,
        isIncluded: Bool = true,
        conflict: String? = nil
    ) {
        self.id = id
        self.chapterPath = chapterPath
        self.chapterTitle = chapterTitle
        self.stage = stage
        self.categoryTitle = categoryTitle
        self.originalText = originalText
        self.replacementText = replacementText
        self.explanation = explanation
        self.isIncluded = isIncluded
        self.conflict = conflict
    }
}

struct ProjectPolishFailure: Identifiable, Equatable {
    var id: String { chapterPath }
    let chapterPath: String
    let chapterTitle: String
    let message: String
}

struct ProjectPolishReport: Equatable {
    var changes: [ProjectPolishChange]
    let failures: [ProjectPolishFailure]
    let completedDocumentCount: Int
    let totalDocumentCount: Int
    let advisoryCount: Int
    let skippedCount: Int
    let wasCancelled: Bool

    func changeSet(including stages: Set<ProjectPolishStage>) -> RevisionChangeSet {
        RevisionChangeSet(
            title: "Project Polish",
            summary: "Locally generated, staged corrections for the current project.",
            changes: changes.map { change in
                RevisionChange(
                    id: change.id,
                    chapterPath: change.chapterPath,
                    originalText: change.originalText,
                    replacementText: change.replacementText,
                    explanation: "\(change.stage.shortTitle): \(change.explanation)",
                    isIncluded: change.isIncluded && stages.contains(change.stage),
                    conflict: change.conflict
                )
            }
        )
    }

    mutating func mergeValidation(_ set: RevisionChangeSet) {
        let conflicts = Dictionary(uniqueKeysWithValues: set.changes.map { ($0.id, $0.conflict) })
        for index in changes.indices {
            changes[index].conflict = conflicts[changes[index].id] ?? nil
        }
    }
}

struct ProjectPolishDocumentAnalysis: Equatable {
    let changes: [ProjectPolishChange]
    let advisoryCount: Int
    let skippedCount: Int
}

@MainActor
struct ProjectPolishService {
    typealias DocumentAnalyzer = (
        _ document: ManuscriptDocument,
        _ targetGrade: Int,
        _ styleDecisions: [ProjectStyleDecision]
    ) async throws -> ProjectPolishDocumentAnalysis

    private let documentAnalyzer: DocumentAnalyzer
    private let cancellationRequested: () -> Bool

    init(
        documentAnalyzer: DocumentAnalyzer? = nil,
        cancellationRequested: @escaping () -> Bool = { Task.isCancelled }
    ) {
        self.documentAnalyzer = documentAnalyzer ?? Self.analyzeDocument
        self.cancellationRequested = cancellationRequested
    }

    func scan(
        documents: [ManuscriptDocument],
        targetGrade: Int,
        styleDecisions: [ProjectStyleDecision],
        onProgress: (Int, Int, String) -> Void = { _, _, _ in }
    ) async -> ProjectPolishReport {
        var changes: [ProjectPolishChange] = []
        var failures: [ProjectPolishFailure] = []
        var completed = 0
        var advisoryCount = 0
        var skippedCount = 0
        var wasCancelled = false

        for (index, document) in documents.enumerated() {
            if cancellationRequested() {
                wasCancelled = true
                break
            }
            onProgress(index, documents.count, document.title)
            do {
                let analysis = try await documentAnalyzer(document, targetGrade, styleDecisions)
                changes.append(contentsOf: analysis.changes)
                advisoryCount += analysis.advisoryCount
                skippedCount += analysis.skippedCount
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                failures.append(ProjectPolishFailure(
                    chapterPath: document.relativePath,
                    chapterTitle: document.title,
                    message: error.localizedDescription
                ))
            }
            completed += 1
            await Task.yield()
        }

        onProgress(completed, documents.count, "")
        return ProjectPolishReport(
            changes: changes,
            failures: failures,
            completedDocumentCount: completed,
            totalDocumentCount: documents.count,
            advisoryCount: advisoryCount,
            skippedCount: skippedCount,
            wasCancelled: wasCancelled
        )
    }

    static func stage(for categories: Set<IssueCategory>) -> ProjectPolishStage {
        if !categories.isDisjoint(with: [.spelling, .grammar]) {
            return .correctness
        }
        if !categories.isDisjoint(with: [
            .hardSentence,
            .veryHardSentence,
            .structuralComplexity,
            .complexPhrase
        ]) {
            return .readability
        }
        return .styleAndVoice
    }

    private static func analyzeDocument(
        _ document: ManuscriptDocument,
        targetGrade: Int,
        styleDecisions: [ProjectStyleDecision]
    ) async throws -> ProjectPolishDocumentAnalysis {
        let localIssues = ReadabilityEngine.analyze(
            document.text,
            targetGrade: targetGrade
        ).issues
        let nativeIssues = await NativeWritingService.issues(in: document.text)
        let suppliedIssues = localIssues + nativeIssues
        let result = LocalPolishService.polish(
            text: document.text,
            targetGrade: targetGrade,
            issues: suppliedIssues,
            styleDecisions: styleDecisions
        )
        let planChanges = result.plan?.safeChanges ?? []
        let changes = planChanges.compactMap { change -> ProjectPolishChange? in
            guard !change.originalText.isEmpty,
                  change.originalText != change.replacementText else { return nil }
            let relatedIssues = suppliedIssues.filter { issue in
                NSIntersectionRange(issue.range, change.originalRange).length > 0
            }
            let categories = Set(relatedIssues.map(\.category))
            let stage = stage(for: categories)
            let categoryTitle = categories
                .sorted { $0.title < $1.title }
                .map(\.title)
                .joined(separator: ", ")
            let explanations = relatedIssues.map(\.message).uniqued().prefix(3)
            return ProjectPolishChange(
                chapterPath: document.relativePath,
                chapterTitle: document.title,
                stage: stage,
                categoryTitle: categoryTitle.isEmpty ? stage.shortTitle : categoryTitle,
                originalText: change.originalText,
                replacementText: change.replacementText,
                explanation: explanations.isEmpty
                    ? "Apply a learned project-style preference."
                    : explanations.joined(separator: " ")
            )
        }
        return ProjectPolishDocumentAnalysis(
            changes: changes,
            advisoryCount: result.advisoryCount,
            skippedCount: result.skippedCount
        )
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

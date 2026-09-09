import Foundation

/// The learned style guide and the accept/reject decision log behind it, for
/// the open project. Extracted out of `WritingProjectStore` -- this concern
/// touches nothing else in the app beyond the project root.
@MainActor
final class StyleLearningStore: ObservableObject {

    @Published var styleText = ""
    @Published var styleDecisions: [ProjectStyleDecision] = []

    private let projectRoot: () -> URL?
    private let reportError: (Error) -> Void

    init(
        projectRoot: @escaping () -> URL?,
        reportError: @escaping (Error) -> Void
    ) {
        self.projectRoot = projectRoot
        self.reportError = reportError
    }

    func load(at root: URL) throws {
        styleText = try ProjectStyleManager.loadStyle(at: root)
        styleDecisions = try ProjectStyleManager.loadDecisions(at: root)
    }

    func replaceContents(styleText: String, decisions: [ProjectStyleDecision]) {
        self.styleText = styleText
        styleDecisions = decisions
    }

    func reset() {
        styleText = ""
        styleDecisions = []
    }

    func saveStyle(_ value: String) {
        guard let rootURL = projectRoot() else { return }
        do {
            try ProjectStyleManager.saveStyle(value, at: rootURL)
            styleText = value
        } catch {
            reportError(error)
        }
    }

    func recordStyleDecision(action: StyleDecisionAction, issue: WritingIssue) {
        guard let rootURL = projectRoot() else { return }
        do {
            try ProjectStyleManager.record(action: action, issue: issue, at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
            styleDecisions = try ProjectStyleManager.loadDecisions(at: rootURL)
        } catch {
            reportError(error)
        }
    }

    func clearLearnedStylePreferences() {
        guard let rootURL = projectRoot() else { return }
        do {
            try ProjectStyleManager.clearLearnedPreferences(at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
            styleDecisions = try ProjectStyleManager.loadDecisions(at: rootURL)
        } catch {
            reportError(error)
        }
    }
}

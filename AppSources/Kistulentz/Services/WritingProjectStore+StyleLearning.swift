import Foundation

extension WritingProjectStore {

    // MARK: - Style Learning

    func saveStyle(_ value: String) {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.saveStyle(value, at: rootURL)
            styleText = value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordStyleDecision(action: StyleDecisionAction, issue: WritingIssue) {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.record(action: action, issue: issue, at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
            styleDecisions = try ProjectStyleManager.loadDecisions(at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearLearnedStylePreferences() {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.clearLearnedPreferences(at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
            styleDecisions = try ProjectStyleManager.loadDecisions(at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

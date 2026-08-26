import XCTest
@testable import DraftSmith

final class DismissedSuggestionTests: XCTestCase {
    @MainActor
    func testEditorReloadsDeclinesAfterClosingDocument() throws {
        let suiteName = "DismissedSuggestionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = DismissedSuggestionStore(defaults: defaults)
        let documentURL = URL(fileURLWithPath: "/Drafts/Reopening.md")
        let text = "We moved quickly through the opening scene."
        let issue = makeIssue(excerpt: "quickly", in: text)

        let firstEditor = EditorViewModel(dismissalStore: store)
        firstEditor.configureDocument(url: documentURL, text: text)
        firstEditor.decline(issue, in: text)

        let reopenedEditor = EditorViewModel(dismissalStore: store)
        reopenedEditor.configureDocument(url: documentURL, text: text)

        XCTAssertEqual(reopenedEditor.dismissedSuggestions.count, 1)
        XCTAssertTrue(try XCTUnwrap(reopenedEditor.dismissedSuggestions.first).matches(issue, in: text))
    }

    func testDismissalPersistsForTheSameDocumentAndPassage() throws {
        let suiteName = "DismissedSuggestionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let text = "A steady opening leads into a sentence that should stay hidden after reopening."
        let issue = makeIssue(excerpt: "sentence", in: text, replacement: "line")
        let dismissal = try XCTUnwrap(DismissedSuggestion(issue: issue, in: text))

        DismissedSuggestionStore(defaults: defaults).save([dismissal], for: "/Drafts/Novel.md")
        let reloaded = DismissedSuggestionStore(defaults: defaults)
            .suggestions(for: "/Drafts/Novel.md")

        XCTAssertEqual(reloaded, [dismissal])
        XCTAssertTrue(try XCTUnwrap(reloaded.first).matches(issue, in: text))
    }

    func testUnrelatedEditDoesNotRestoreDismissedSuggestion() throws {
        let text = "A long and deliberately stable opening paragraph comes first. The sentence stays here."
        let issue = makeIssue(excerpt: "sentence", in: text)
        let dismissal = try XCTUnwrap(DismissedSuggestion(issue: issue, in: text))
        let edited = "New title. " + text

        XCTAssertTrue(dismissal.passageStillExists(in: edited))
        let shiftedIssue = makeIssue(excerpt: "sentence", in: edited)
        XCTAssertTrue(dismissal.matches(shiftedIssue, in: edited))
    }

    func testChangingPassageRestoresDismissedSuggestion() throws {
        let text = "A steady opening leads into a sentence that should be revised."
        let issue = makeIssue(excerpt: "sentence", in: text)
        let dismissal = try XCTUnwrap(DismissedSuggestion(issue: issue, in: text))

        XCTAssertFalse(dismissal.passageStillExists(in: text.replacingOccurrences(of: "sentence", with: "line")))
        XCTAssertFalse(dismissal.passageStillExists(in: text.replacingOccurrences(of: "leads into", with: "moves toward")))
    }

    private func makeIssue(
        excerpt: String,
        in text: String,
        replacement: String? = nil
    ) -> WritingIssue {
        WritingIssue(
            category: .complexPhrase,
            range: (text as NSString).range(of: excerpt),
            excerpt: excerpt,
            message: "Use a simpler phrase.",
            replacement: replacement
        )
    }
}

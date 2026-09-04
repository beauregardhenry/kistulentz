import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let issues: [WritingIssue]
    let focusRequest: FocusRequest?
    let fontName: String
    let fontSize: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 48, height: 42)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        let font = MarkdownEditorFont.resolve(name: fontName, size: fontSize)
        textView.font = font
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        // Kistulentz requests Apple spelling and grammar in the background and
        // renders those results with its other review cards. Enabling TextKit's
        // second live pass here makes a large paste perform the same work twice.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setAccessibilityLabel("Markdown editor")
        textView.setAccessibilityHelp("Edit the current Markdown document. Kistulentz highlights writing suggestions in this text area.")

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 8
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        let textLength = (text as NSString).length
        if selection.location != NSNotFound, NSMaxRange(selection) <= textLength {
            textView.setSelectedRange(selection)
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        applyHighlights(to: textView)
        context.coordinator.lastHighlightedIssues = issues
        context.coordinator.lastFontName = fontName
        context.coordinator.lastFontSize = fontSize
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.isApplyingSwiftUIUpdate = true
        defer { context.coordinator.isApplyingSwiftUIUpdate = false }

        let replacedText = textView.string != text
        if replacedText {
            let selection = textView.selectedRange()
            UndoRegistrationGuard.perform(on: textView.undoManager) {
                textView.string = text
            }
            if selection.location <= (text as NSString).length {
                textView.setSelectedRange(NSRange(location: selection.location, length: 0))
            }
        }

        let fontChanged = context.coordinator.lastFontName != fontName
            || context.coordinator.lastFontSize != fontSize

        if replacedText || context.coordinator.lastHighlightedIssues != issues || fontChanged {
            applyHighlights(to: textView)
            context.coordinator.lastHighlightedIssues = issues
        }

        if fontChanged {
            let font = MarkdownEditorFont.resolve(name: fontName, size: fontSize)
            textView.font = font
            textView.typingAttributes[.font] = font
            context.coordinator.lastFontName = fontName
            context.coordinator.lastFontSize = fontSize
        }

        if let request = focusRequest, request.id != context.coordinator.lastFocusID {
            context.coordinator.lastFocusID = request.id
            DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
                guard let textView, let coordinator, coordinator.lastFocusID == request.id else { return }
                let length = (textView.string as NSString).length
                guard request.range.location != NSNotFound,
                      NSMaxRange(request.range) <= length else { return }
                coordinator.isApplyingSwiftUIUpdate = true
                defer { coordinator.isApplyingSwiftUIUpdate = false }
                textView.setSelectedRange(request.range)
                textView.scrollRangeToVisible(request.range)
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyHighlights(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 8

        UndoRegistrationGuard.perform(on: textView.undoManager) {
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.addAttributes([
                .font: MarkdownEditorFont.resolve(name: fontName, size: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ], range: fullRange)

            let sentenceIssues = issues.filter {
                $0.category == .hardSentence || $0.category == .veryHardSentence
            }
            let inlineIssues = issues.filter {
                $0.category != .hardSentence && $0.category != .veryHardSentence
            }

            for issue in sentenceIssues + inlineIssues {
                guard issue.range.location != NSNotFound,
                      NSMaxRange(issue.range) <= storage.length else { continue }
                storage.addAttribute(
                    .backgroundColor,
                    value: issue.category.highlightColor,
                    range: issue.range
                )
            }
            storage.endEditing()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selection: NSRange
        weak var textView: NSTextView?
        var lastFocusID: UUID?
        var lastHighlightedIssues: [WritingIssue] = []
        var lastFontName = ""
        var lastFontSize: Double = 0
        var isApplyingSwiftUIUpdate = false

        init(text: Binding<String>, selection: Binding<NSRange>) {
            _text = text
            _selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingSwiftUIUpdate,
                  let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingSwiftUIUpdate,
                  let textView = notification.object as? NSTextView else { return }
            let next = textView.selectedRange()
            if selection != next {
                selection = next
            }
        }
    }
}

enum UndoRegistrationGuard {
    static func perform(on undoManager: UndoManager?, _ action: () -> Void) {
        guard let undoManager, undoManager.isUndoRegistrationEnabled else {
            action()
            return
        }
        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }
        action()
    }
}

/// Resolves the editor's stored font preference (`AppSettings.editorFontName` /
/// `.editorFontSize`) into an actual `NSFont`, with a safe fallback to the system font so a
/// blank preference or a font that's no longer installed (removed since it was chosen, a synced
/// defaults file from another Mac) never leaves the editor without a font.
enum MarkdownEditorFont {
    /// AppKit's font-weight scale runs 0 (lightest) to 15 (heaviest); 5 is the documented
    /// standard/regular weight (9 is bold).
    private static let regularWeight = 5

    static func resolve(name: String, size: Double) -> NSFont {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pointSize = CGFloat(size)
        guard !trimmedName.isEmpty else {
            return .systemFont(ofSize: pointSize, weight: .regular)
        }
        // AppSettings.editorFontName stores a font FAMILY name (that's what the Settings picker
        // offers, from NSFontManager.availableFontFamilies), so resolve through NSFontManager
        // rather than NSFont(name:size:) -- the latter expects an exact PostScript name, and
        // silently fails for a family whose regular face's PostScript name differs from its
        // family name (Times New Roman's regular face, for example, is "TimesNewRomanPSMT").
        if let font = NSFontManager.shared.font(
            withFamily: trimmedName,
            traits: [],
            weight: regularWeight,
            size: pointSize
        ) {
            return font
        }
        // Fall back to treating it as an exact PostScript name, in case one was ever supplied
        // directly rather than through the family-name picker.
        if let font = NSFont(name: trimmedName, size: pointSize) {
            return font
        }
        return .systemFont(ofSize: pointSize, weight: .regular)
    }
}

private extension IssueCategory {
    var highlightColor: NSColor {
        switch self {
        case .hardSentence:
            NSColor.systemYellow.withAlphaComponent(0.28)
        case .veryHardSentence:
            NSColor.systemRed.withAlphaComponent(0.23)
        case .adverb:
            NSColor.systemBlue.withAlphaComponent(0.20)
        case .passiveVoice:
            NSColor.systemGreen.withAlphaComponent(0.22)
        case .structuralComplexity:
            NSColor.systemOrange.withAlphaComponent(0.20)
        case .complexPhrase:
            NSColor.systemPurple.withAlphaComponent(0.20)
        case .aiTell:
            NSColor.systemIndigo.withAlphaComponent(0.22)
        case .spelling:
            NSColor.systemRed.withAlphaComponent(0.17)
        case .grammar:
            NSColor.systemTeal.withAlphaComponent(0.18)
        case .aiSuggestion:
            NSColor.systemMint.withAlphaComponent(0.23)
        case .referenceVoice:
            NSColor.systemOrange.withAlphaComponent(0.20)
        case .continuity:
            NSColor.systemPink.withAlphaComponent(0.20)
        }
    }
}

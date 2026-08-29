import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    let issues: [WritingIssue]
    let focusRequest: FocusRequest?

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
        textView.delegate = context.coordinator
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
        textView.font = .systemFont(ofSize: 17, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 8
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        selection = textView.selectedRange()
        applyHighlights(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            if selection.location <= (text as NSString).length {
                textView.setSelectedRange(NSRange(location: selection.location, length: 0))
            }
        }

        applyHighlights(to: textView)

        if let request = focusRequest, request.id != context.coordinator.lastFocusID {
            let length = (textView.string as NSString).length
            if request.range.location != NSNotFound,
               NSMaxRange(request.range) <= length {
                textView.setSelectedRange(request.range)
                textView.scrollRangeToVisible(request.range)
                textView.window?.makeFirstResponder(textView)
            }
            context.coordinator.lastFocusID = request.id
        }
    }

    private func applyHighlights(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 8

        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.addAttributes([
            .font: NSFont.systemFont(ofSize: 17),
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selection: NSRange
        weak var textView: NSTextView?
        var lastFocusID: UUID?

        init(text: Binding<String>, selection: Binding<NSRange>) {
            _text = text
            _selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let next = textView.selectedRange()
            if selection != next {
                selection = next
            }
        }
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

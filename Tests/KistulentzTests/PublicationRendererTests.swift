import Foundation
import XCTest
@testable import Kistulentz

/// Direct unit tests for `PublicationRenderer` -- the class that turns a manuscript (as a
/// `PublicationExportPlan`) into the `PublicationRenderedBook` the three writers (DOCX/EPUB/PDF,
/// covered by `PublicationWritersTests.swift`) and the full-pipeline tests (`PublicationTests.swift`)
/// consume. Neither of those files exercises `PublicationRenderer` directly: the writer tests hand-build
/// a `PublicationRenderedBook` and bypass the renderer entirely, and the pipeline tests only ever render
/// one or two fixture manuscripts through the whole export flow, so branches that depend on a *specific*
/// renderer decision -- which Markdown constructs become which block kind, how footnotes and citations
/// resolve to notes under each citation mode, how the table of contents/endnotes/bibliography sections get
/// assembled and positioned -- are only ever exercised by whatever combination that fixture happens to hit.
///
/// These tests build minimal `ExportPlanItem`s directly, bypassing `PublicationPlanBuilder` and the outline
/// machinery, so each test puts the renderer in one precise, deliberate state and checks exactly what it did.
final class PublicationRendererTests: XCTestCase {
    // MARK: - Block parsing

    func testParagraphLinesAreJoinedWithASpace() {
        let book = render([
            makeManuscriptItem(markdown: "# Title\n\nLine one\nline two continued.\n\nNew paragraph.")
        ])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[1].text, "Line one line two continued.")
        XCTAssertEqual(blocks[2].text, "New paragraph.")
    }

    func testMissingTopLevelHeadingGetsAutoInsertedTitleBlock() {
        let book = render([
            makeManuscriptItem(title: "Chapter Two", markdown: "Just body text, no heading.")
        ])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .heading(1))
        XCTAssertEqual(blocks[0].text, "Chapter Two")
        XCTAssertEqual(blocks[0].html, "<h1>Chapter Two</h1>")
    }

    func testHeadingLevelsOneThroughSixAreRecognized() {
        let markdown = "# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6\n"
        let book = render([makeManuscriptItem(markdown: markdown)])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.map(\.kind), (1...6).map { .heading($0) })
    }

    func testHashWithoutSpaceIsNotTreatedAsHeading() {
        let book = render([
            makeManuscriptItem(markdown: "# Title\n\n#NotAHeading stays paragraph text.")
        ])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertTrue(blocks[1].text.contains("#NotAHeading"))
    }

    func testBlockquoteParsing() {
        let book = render([makeManuscriptItem(markdown: "# Title\n\n> A quoted line.")])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks[1].kind, .blockquote)
        XCTAssertEqual(blocks[1].html, "<blockquote><p>A quoted line.</p></blockquote>")
    }

    func testCodeFenceContentIsPreservedVerbatimNotInlineProcessed() {
        let book = render([
            makeManuscriptItem(markdown: "# Title\n\n```\nlet x = 1 // *not* italic\n```")
        ])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks[1].kind, .code)
        XCTAssertEqual(blocks[1].text, "let x = 1 // *not* italic")
        XCTAssertEqual(blocks[1].html, "<pre><code>let x = 1 // *not* italic</code></pre>")
    }

    func testDividerVariantsAreAllRecognized() {
        let markdown = "# Title\n\nAbove.\n\n---\n\nBetween.\n\n***\n\nBetween two.\n\n___\n\nBelow."
        let book = render([makeManuscriptItem(markdown: markdown)])

        let dividers = try! XCTUnwrap(book.sections.first).blocks.filter { $0.kind == .divider }
        XCTAssertEqual(dividers.count, 3)
        XCTAssertTrue(dividers.allSatisfy { $0.html == "<hr />" })
    }

    func testUnorderedListMarkersDashAsteriskAndPlusAllRecognized() {
        let book = render([
            makeManuscriptItem(markdown: "# Title\n\n- Dash item\n\n* Star item\n\n+ Plus item")
        ])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.dropFirst().map(\.kind), [.unorderedItem, .unorderedItem, .unorderedItem])
        XCTAssertEqual(blocks.dropFirst().map(\.text), ["Dash item", "Star item", "Plus item"])
    }

    func testOrderedListMarkersPeriodAndParenAllRecognized() {
        let book = render([makeManuscriptItem(markdown: "# Title\n\n1. First\n\n2) Second")])

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.dropFirst().map(\.kind), [.orderedItem, .orderedItem])
        XCTAssertEqual(blocks.dropFirst().map(\.text), ["First", "Second"])
    }

    func testInlineMarkdownFormattingConvertsToHTML() {
        let markdown = "# Title\n\nThis has **bold**, *italic*, ~~strike~~, `code`, and a [link](https://example.com/page)."
        let book = render([makeManuscriptItem(markdown: markdown)])

        let html = try! XCTUnwrap(book.sections.first).blocks[1].html
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<del>strike</del>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/page\">link</a>"))
    }

    // MARK: - Images

    func testInlineImageSplitsTextIntoBeforeImageAndAfterBlocks() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let markdown = "# Title\n\nSee the map here ![A map](map.png \"Map title\") for details."
        let book = render([makeManuscriptItem(markdown: markdown, sourcePath: "Chapter.md")], root: root)

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[1].text, "See the map here")
        XCTAssertEqual(blocks[2].kind, .image)
        XCTAssertEqual(blocks[2].imageURL, root.appendingPathComponent("map.png").standardizedFileURL)
        XCTAssertEqual(blocks[2].altText, "A map")
        XCTAssertTrue(blocks[2].html.contains("<figcaption>Map title</figcaption>"))
        XCTAssertEqual(blocks[3].text, "for details.")
    }

    func testStandaloneImageLineProducesOnlyOneImageBlockNoEmptySurroundingBlocks() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let book = render([makeManuscriptItem(markdown: "# Title\n\n![Alt text](pic.png)")], root: root)

        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].kind, .image)
    }

    // MARK: - Footnotes

    func testFootnoteReferenceResolvesToNoteAndStripsDefinitionLine() {
        let profile = makeProfile(citationMode: .footnotes)
        let markdown = "# Title\n\nA claim needing support[^1].\n\n[^1]: This is the source detail."
        let book = render([makeManuscriptItem(markdown: markdown)], profile: profile)

        XCTAssertEqual(book.notes.count, 1)
        XCTAssertEqual(book.notes[0].text, "This is the source detail.")
        let blocks = try! XCTUnwrap(book.sections.first).blocks
        XCTAssertFalse(blocks.contains { $0.text == "[^1]: This is the source detail." })
        XCTAssertTrue(blocks[1].html.contains("doc-noteref"))
        XCTAssertTrue(blocks[1].html.contains("href=\"#footnote-1\""))
    }

    func testCrossItemFootnoteDefinitionIsResolvedInADifferentItem() {
        let profile = makeProfile(citationMode: .footnotes)
        let referencing = makeManuscriptItem(id: "a", title: "A", markdown: "# A\n\nShared claim[^shared].")
        let defining = makeManuscriptItem(id: "b", title: "B", markdown: "# B\n\n[^shared]: Shared source.")
        let book = render([referencing, defining], profile: profile)

        XCTAssertEqual(book.notes.map(\.text), ["Shared source."])
        XCTAssertTrue(book.sections[0].blocks[1].html.contains("href=\"#footnote-1\""))
    }

    func testUnknownFootnoteReferenceIsLeftUnresolved() {
        let book = render([makeManuscriptItem(markdown: "# Title\n\nA vague claim[^missing].")])

        XCTAssertEqual(book.notes.count, 0)
        XCTAssertTrue(book.sections[0].blocks[1].html.contains("[^missing]"))
    }

    // MARK: - Citations

    func testParentheticalCitationRendersAuthorYearLocatorInline() {
        let source = makeSource(citeKey: "doe2024", familyName: "Doe", year: 2024)
        let markdown = "# Title\n\nThe results were clear [@doe2024, p. 12]."
        let book = render([makeManuscriptItem(markdown: markdown)], sources: [source])

        XCTAssertEqual(book.notes.count, 0)
        XCTAssertTrue(book.sections[0].blocks[1].html.contains("(Doe, 2024, p. 12)"))
    }

    func testFootnoteCitationModeCreatesNoteWithFormattedEntryAndSuperscriptAnchor() {
        let source = makeSource(citeKey: "doe2024", familyName: "Doe", year: 2024)
        let profile = makeProfile(citationMode: .footnotes)
        let markdown = "# Title\n\nThe results were clear [@doe2024]."
        let book = render([makeManuscriptItem(markdown: markdown)], profile: profile, sources: [source])

        // `appendNote` runs every note's text through `PublicationPlainText.inline`, which strips markdown
        // emphasis markers rather than converting them -- so the Chicago entry's `*title*` asterisks must
        // be stripped here too, or this compares against text the renderer never actually produces.
        let expected = PublicationPlainText.inline(CitationFormatter.entry(source, style: .chicagoNotes, number: 1))
        XCTAssertEqual(book.notes.map(\.text), [expected])
        let html = book.sections[0].blocks[1].html
        XCTAssertTrue(html.contains("doc-noteref"))
        XCTAssertTrue(html.contains("href=\"#footnote-1\""))
        XCTAssertTrue(html.contains("<sup>1</sup>"))
    }

    func testMultipleCitationKeysInOneBracketAreJoinedWithSemicolon() {
        let doe = makeSource(citeKey: "doe2024", familyName: "Doe", year: 2024)
        let lee = makeSource(citeKey: "lee2023", familyName: "Lee", year: 2023)
        let profile = makeProfile(citationMode: .footnotes)
        let markdown = "# Title\n\nBoth agree [@doe2024; @lee2023]."
        let book = render([makeManuscriptItem(markdown: markdown)], profile: profile, sources: [doe, lee])

        // Same stripped-markdown note text as above -- see the comment in
        // testFootnoteCitationModeCreatesNoteWithFormattedEntryAndSuperscriptAnchor.
        let expected = PublicationPlainText.inline(
            CitationFormatter.entry(doe, style: .chicagoNotes, number: 1)
                + "; " + CitationFormatter.entry(lee, style: .chicagoNotes, number: 2)
        )
        XCTAssertEqual(book.notes.map(\.text), [expected])
    }

    func testUnknownCitationKeyLeavesBracketedTextUnchanged() {
        let markdown = "# Title\n\nA claim [@unknownkey]."
        let book = render([makeManuscriptItem(markdown: markdown)])

        XCTAssertEqual(book.notes.count, 0)
        XCTAssertTrue(book.sections[0].blocks[1].html.contains("[@unknownkey]"))
    }

    func testCitationKeyMatchingIsCaseInsensitive() {
        let source = makeSource(citeKey: "Doe2024", familyName: "Doe", year: 2024)
        let markdown = "# Title\n\nA claim [@doe2024]."
        let book = render([makeManuscriptItem(markdown: markdown)], sources: [source])

        XCTAssertFalse(book.sections[0].blocks[1].html.contains("[@doe2024]"))
        XCTAssertTrue(book.sections[0].blocks[1].html.contains("Doe"))
    }

    // MARK: - Section note IDs

    func testSectionNoteIDsCoverOnlyNotesAddedDuringThatSection() {
        let source = makeSource(citeKey: "doe2024", familyName: "Doe", year: 2024)
        let profile = makeProfile(citationMode: .footnotes)
        let first = makeManuscriptItem(id: "a", title: "A", markdown: "# A\n\nOne [@doe2024].")
        let second = makeManuscriptItem(id: "b", title: "B", markdown: "# B\n\nTwo [@doe2024].")
        let book = render([first, second], profile: profile, sources: [source])

        XCTAssertEqual(book.sections[0].noteIDs, [1])
        XCTAssertEqual(book.sections[1].noteIDs, [2])
    }

    func testSectionWithNoNotesHasEmptyNoteIDs() {
        let book = render([makeManuscriptItem(markdown: "# Title\n\nNothing cited here.")])

        XCTAssertEqual(book.sections[0].noteIDs, [])
    }

    // MARK: - Table of contents, bibliography, endnotes

    func testTableOfContentsListsOnlyPartAndManuscriptSections() {
        let toc = makeMatterItem(id: "toc", kind: .frontMatter, title: "Contents", matterKind: .tableOfContents)
        let part = makeMatterItem(id: "part-1", kind: .part, title: "Part One", markdown: "# Part One", matterKind: nil)
        let manuscript = makeManuscriptItem(id: "chapter-1", title: "Chapter One", markdown: "# Chapter One")
        let back = makeMatterItem(id: "back-1", kind: .backMatter, title: "Colophon", markdown: "# Colophon", matterKind: nil)
        let book = render([toc, part, manuscript, back])

        let tocSection = try! XCTUnwrap(book.sections.first { $0.id == "toc" })
        XCTAssertTrue(tocSection.bodyHTML.contains("Part One"))
        XCTAssertTrue(tocSection.bodyHTML.contains("Chapter One"))
        XCTAssertFalse(tocSection.bodyHTML.contains("Colophon"))
        XCTAssertTrue(tocSection.bodyHTML.contains("href=\"#\(PublicationXML.slug("part-1"))\""))
    }

    func testTableOfContentsIsInsertedAtItsOriginalItemPosition() {
        let part = makeMatterItem(id: "part-1", kind: .part, title: "Part One", markdown: "# Part One", matterKind: nil)
        let toc = makeMatterItem(id: "toc", kind: .frontMatter, title: "Contents", matterKind: .tableOfContents)
        let manuscript = makeManuscriptItem(id: "chapter-1", title: "Chapter One", markdown: "# Chapter One")
        let book = render([part, toc, manuscript])

        XCTAssertEqual(book.sections.map(\.id), ["part-1", "toc", "chapter-1"])
    }

    func testBibliographyOmittedWhenProfileDoesNotIncludeBibliographyEvenIfMatterItemPresent() {
        var profile = makeProfile()
        profile.includeBibliography = false
        let bibliographyItem = makeMatterItem(id: "biblio", kind: .backMatter, title: "Bibliography", markdown: "# Bibliography", matterKind: .bibliography)
        let book = render([makeManuscriptItem(markdown: "# Title\n\nText."), bibliographyItem], profile: profile)

        XCTAssertFalse(book.sections.contains { $0.id == "biblio" })
    }

    func testBibliographySectionListsSourcesSortedByCreatorThenTitleAndStripsGeneratedComment() {
        var profile = makeProfile()
        profile.includeBibliography = true
        let zeta = makeSource(citeKey: "zeta", familyName: "Zeta", year: 2020, title: "Z Book")
        let alpha = makeSource(citeKey: "alpha", familyName: "Alpha", year: 2021, title: "A Book")
        let bibliographyItem = makeMatterItem(
            id: "biblio", kind: .backMatter, title: "Bibliography",
            markdown: "<!-- Kistulentz generates this section automatically -->\n# Sources\n",
            matterKind: .bibliography
        )
        let book = render(
            [makeManuscriptItem(markdown: "# Title\n\nText."), bibliographyItem],
            profile: profile,
            sources: [zeta, alpha]
        )

        let section = try! XCTUnwrap(book.sections.first { $0.id == "biblio" })
        XCTAssertFalse(section.bodyHTML.contains("Kistulentz generates"))
        XCTAssertEqual(section.blocks.count, 3)
        XCTAssertTrue(section.blocks[1].html.contains("Alpha"))
        XCTAssertTrue(section.blocks[2].html.contains("Zeta"))
    }

    func testEndnotesSectionOmittedWhenCitationModeIsNotEndnotesEvenIfMatterItemPresent() {
        let profile = makeProfile(citationMode: .footnotes)
        let endnotesItem = makeMatterItem(id: "endnotes", kind: .backMatter, title: "Notes", markdown: "# Notes", matterKind: .endnotes)
        let book = render([makeManuscriptItem(markdown: "# Title\n\nText."), endnotesItem], profile: profile)

        XCTAssertFalse(book.sections.contains { $0.id == "endnotes" })
    }

    func testEndnotesSectionListsNotesAndStripsGeneratedComment() {
        let source = makeSource(citeKey: "doe2024", familyName: "Doe", year: 2024)
        let profile = makeProfile(citationMode: .endnotes)
        let endnotesItem = makeMatterItem(
            id: "endnotes", kind: .backMatter, title: "Notes",
            markdown: "<!-- Kistulentz generates this section automatically -->\n# Notes\n",
            matterKind: .endnotes
        )
        let book = render(
            [makeManuscriptItem(markdown: "# Title\n\nA claim [@doe2024]."), endnotesItem],
            profile: profile,
            sources: [source]
        )

        let section = try! XCTUnwrap(book.sections.first { $0.id == "endnotes" })
        XCTAssertFalse(section.bodyHTML.contains("Kistulentz generates"))
        XCTAssertTrue(section.bodyHTML.contains("id=\"note-1\""))
        XCTAssertEqual(section.noteIDs, [1])
    }

    // MARK: - PublicationRenderedBook.images

    func testRenderedBookImagesDedupsRepeatedSourceByStandardizedPath() {
        let url = URL(fileURLWithPath: "/tmp/shared/figure.png")
        let plan = makePlan(items: [])
        let section = PublicationRenderedSection(
            id: "s1", title: "S1", kind: .manuscript,
            blocks: [
                PublicationBlock(kind: .image, text: "", html: "", imageURL: url, altText: "First"),
                PublicationBlock(kind: .image, text: "", html: "", imageURL: url, altText: "Second")
            ],
            bodyHTML: "", sourcePath: nil, noteIDs: []
        )
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        XCTAssertEqual(book.images.count, 1)
        XCTAssertEqual(book.images.first?.altText, "First")
    }

    // MARK: - PublicationXML / PublicationPlainText / PublicationHash

    func testXMLEscapeHandlesReservedCharacters() {
        XCTAssertEqual(PublicationXML.escape("<a & \"b\">"), "&lt;a &amp; &quot;b&quot;&gt;")
    }

    func testXMLEscapeAttributeAlsoEscapesApostrophe() {
        XCTAssertEqual(PublicationXML.escapeAttribute("It's <ok>"), "It&apos;s &lt;ok&gt;")
    }

    func testSlugLowercasesAndCollapsesNonAlphanumericRuns() {
        XCTAssertEqual(PublicationXML.slug("Chapter One: The Beginning!!"), "chapter-one-the-beginning")
    }

    func testShortHashIsDeterministicAndEightHexCharacters() {
        let first = PublicationHash.shortHash("same-value")
        let second = PublicationHash.shortHash("same-value")
        let different = PublicationHash.shortHash("a-different-value")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 8)
        XCTAssertNotNil(first.range(of: "^[0-9a-f]{8}$", options: .regularExpression))
        XCTAssertNotEqual(first, different)
    }

    func testPlainTextInlineReplacesImagesLinksAndNoteTokensWithPlainText() {
        let input = "![alt](pic.png) and [click here](url) and {{KISTU_NOTE_7}}"
        XCTAssertEqual(PublicationPlainText.inline(input), "alt and click here and [7]")
    }

    func testPlainTextInlineStripsEmphasisMarkerCharacters() {
        let input = "**bold** _em_ ~~strike~~ `code`"
        XCTAssertEqual(PublicationPlainText.inline(input), "bold em strike code")
    }

    // MARK: - Fixture helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kistulentz-Renderer-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeProfile(citationMode: PublicationCitationMode = .parenthetical) -> ExportProfile {
        ExportProfile(
            name: "Test Profile",
            kind: .custom,
            preferredFormat: .epub,
            layout: .fiction,
            citationMode: citationMode
        )
    }

    private func makePlan(
        profile: ExportProfile? = nil,
        items: [ExportPlanItem],
        sources: [ResearchSource] = []
    ) -> PublicationExportPlan {
        PublicationExportPlan(
            projectName: "Test Book",
            profile: profile ?? makeProfile(),
            format: .epub,
            items: items,
            metadata: PublicationMetadata(title: "Test Book"),
            bibliography: ProjectBibliographyArchive(),
            sources: sources,
            destinations: []
        )
    }

    private func makeManuscriptItem(
        id: String = "chapter-1",
        title: String = "Chapter One",
        markdown: String,
        sourcePath: String? = nil,
        isIncluded: Bool = true
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: id, kind: .manuscript, title: title, markdown: markdown, sourcePath: sourcePath,
            outlineNodeID: nil, depth: 0, isIncluded: isIncluded, exclusionReason: nil, matterKind: nil
        )
    }

    private func makeMatterItem(
        id: String,
        kind: ExportPlanItemKind,
        title: String,
        markdown: String = "",
        matterKind: PublicationMatterKind?,
        isIncluded: Bool = true
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: id, kind: kind, title: title, markdown: markdown, sourcePath: nil,
            outlineNodeID: nil, depth: 0, isIncluded: isIncluded, exclusionReason: nil, matterKind: matterKind
        )
    }

    private func makeSource(
        citeKey: String,
        familyName: String,
        year: Int,
        title: String = "Test Source"
    ) -> ResearchSource {
        ResearchSource(
            citeKey: citeKey,
            title: title,
            creators: [ResearchCreator(role: .author, familyName: familyName)],
            issuedYear: year
        )
    }

    /// Renders `items` through a fresh `PublicationRenderer`. `root` only matters for tests that resolve
    /// image paths; everything else can use a throwaway directory.
    private func render(
        _ items: [ExportPlanItem],
        profile: ExportProfile? = nil,
        sources: [ResearchSource] = [],
        root: URL = FileManager.default.temporaryDirectory
    ) -> PublicationRenderedBook {
        let plan = makePlan(profile: profile, items: items, sources: sources)
        return PublicationRenderer(plan: plan, root: root).render()
    }
}

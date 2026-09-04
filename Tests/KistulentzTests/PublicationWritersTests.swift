import AppKit
import PDFKit
import XCTest
@testable import Kistulentz

/// Direct unit tests for the three publication writers (`DOCXPublicationWriter`, `EPUBPublicationWriter`,
/// `PDFPublicationWriter`). `PublicationTests.swift` already exercises them indirectly by running the full
/// `PublicationPlanBuilder` -> `PublicationRenderer` -> `PublicationExporter` pipeline, but every one of
/// those tests renders the same fixture manuscript through the same profile, so branches that depend on a
/// *specific* writer decision -- which notes part gets written for which citation mode, when a header or
/// footer part is emitted, whether a cover page is included, EPUB's accessibility-metadata computation,
/// PDF bleed geometry and recto pagination -- are only ever exercised by whatever combination that one
/// fixture happens to produce.
///
/// These tests instead hand-construct a `PublicationRenderedBook` -- the exact type each writer's single
/// entry point (`static func write(_:to:root:) throws`) consumes -- so each test can put a writer in one
/// precise, deliberate state and check exactly what it did. This bypasses `PublicationPlanBuilder` and
/// `PublicationRenderer` entirely; neither is exercised or asserted on here.
final class PublicationWritersTests: XCTestCase {
    // MARK: - DOCXPublicationWriter

    func testDocumentXMLContainsSectionHeadingAndParagraphText() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [heading("Chapter One"), paragraph("It was a dark and stormy night.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("word/document.xml"))
        let document = try unzipText(output, path: "word/document.xml")
        XCTAssertTrue(document.contains("Chapter One"))
        XCTAssertTrue(document.contains("It was a dark and stormy night."))
        XCTAssertTrue(document.contains("Heading1"))
    }

    func testFootnotesPartIsWrittenOnlyWhenCitationModeIsFootnotesAndNotesArePresent() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(citationMode: .footnotes), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("A claim worth citing [1].")], noteIDs: [1])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [PublicationNote(id: 1, text: "Source, 2024.")])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("word/footnotes.xml"))
        XCTAssertFalse(entries.contains("word/endnotes.xml"))
        let document = try unzipText(output, path: "word/document.xml")
        XCTAssertTrue(document.contains("w:footnoteReference"))
    }

    func testEndnotesPartIsWrittenOnlyWhenCitationModeIsEndnotesAndNotesArePresent() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(citationMode: .endnotes), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("A claim worth citing [1].")], noteIDs: [1])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [PublicationNote(id: 1, text: "Source, 2024.")])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("word/endnotes.xml"))
        XCTAssertFalse(entries.contains("word/footnotes.xml"))
        let document = try unzipText(output, path: "word/document.xml")
        XCTAssertTrue(document.contains("w:endnoteReference"))
    }

    func testNeitherNotesPartIsWrittenForParentheticalCitations() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(citationMode: .parenthetical), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("A claim (Author, 2024).")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertFalse(entries.contains("word/footnotes.xml"))
        XCTAssertFalse(entries.contains("word/endnotes.xml"))
    }

    func testHeaderPartIsWrittenWhenHeaderIsEnabled() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(layout: .fiction), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        XCTAssertTrue(try unzipList(output).contains("word/header1.xml"))
    }

    func testHeaderPartIsOmittedWhenHeaderIsDisabled() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(layout: .accessible), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        XCTAssertFalse(try unzipList(output).contains("word/header1.xml"))
    }

    func testFooterPartIsWrittenWhenPageNumbersAreEnabledEvenIfFooterTextIsDisabled() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        // .fiction has footerEnabled == false but pageNumbersEnabled == true; the writer ORs the two,
        // so the footer part must still be written to carry the page-number field.
        let plan = makePlan(format: .docx, profile: makeProfile(layout: .fiction), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("word/footer1.xml"))
        let footer = try unzipText(output, path: "word/footer1.xml")
        XCTAssertTrue(footer.contains("PAGE"))
    }

    func testFooterPartIsOmittedWhenBothFooterAndPageNumbersAreDisabled() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let plan = makePlan(format: .docx, profile: makeProfile(layout: .accessible), metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        XCTAssertFalse(try unzipList(output).contains("word/footer1.xml"))
    }

    func testDOCXUnsupportedContentImageExtensionThrows() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let imageURL = root.appendingPathComponent("figure.heic")
        try makeFile(at: imageURL)
        let plan = makePlan(format: .docx, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A figure")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        XCTAssertThrowsError(try DOCXPublicationWriter.write(book, to: output, root: root)) { error in
            guard let publicationError = error as? PublicationExportError else {
                return XCTFail("expected PublicationExportError, got \(error)")
            }
            guard case .unsupportedImage(let name) = publicationError else {
                return XCTFail("expected unsupportedImage, got \(publicationError)")
            }
            XCTAssertEqual(name, "figure.heic")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testSupportedImageIsCopiedIntoMediaAndDeclaredInContentTypes() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        let imageURL = root.appendingPathComponent("harbor.png")
        try makePNG(at: imageURL)
        let plan = makePlan(format: .docx, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A harbor", caption: "The harbor at dusk")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains { $0.hasPrefix("word/media/harbor-") && $0.hasSuffix(".png") })
        let contentTypes = try unzipText(output, path: "[Content_Types].xml")
        XCTAssertTrue(contentTypes.contains("Extension=\"png\""))
        XCTAssertTrue(contentTypes.contains("ContentType=\"image/png\""))
        let document = try unzipText(output, path: "word/document.xml")
        XCTAssertTrue(document.contains("The harbor at dusk"))
    }

    func testCoverImageIsInsertedAsTheFirstParagraphWhenIncludeCoverIsTrue() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.docx")
        try makePNG(at: root.appendingPathComponent("cover.png"))
        let metadata = makeMetadata(coverImageRelativePath: "cover.png", coverAltText: "A blue square cover")
        let plan = makePlan(format: .docx, profile: makeProfile(includeCover: true), metadata: metadata)
        let section = makeSection(blocks: [heading("Chapter One"), paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try DOCXPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains { $0.hasPrefix("word/media/cover.") })
        let document = try unzipText(output, path: "word/document.xml")
        let drawingRange = try XCTUnwrap(document.range(of: "<w:drawing>"))
        let headingRange = try XCTUnwrap(document.range(of: "Chapter One"))
        XCTAssertTrue(drawingRange.lowerBound < headingRange.lowerBound)
        XCTAssertTrue(document.contains("<w:br w:type=\"page\"/>"))
    }

    // MARK: - EPUBPublicationWriter

    func testStructureContainsPackageOPFNavigationAndSectionContent() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(bodyHTML: "<h1>Chapter One</h1><p>It was a dark and stormy night.</p>")
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("EPUB/package.opf"))
        XCTAssertTrue(entries.contains("EPUB/nav.xhtml"))
        XCTAssertTrue(entries.contains("EPUB/text/section-001.xhtml"))
        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertTrue(opf.contains("version=\"3.0\""))
        let chapter = try unzipText(output, path: "EPUB/text/section-001.xhtml")
        XCTAssertTrue(chapter.contains("It was a dark and stormy night."))
    }

    func testMimetypeIsTheFirstZipEntry() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection()
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        // The EPUB spec requires "mimetype" to be the first archive entry, stored uncompressed, so
        // unzip tools can identify the format without inflating anything. The writer achieves this by
        // zipping it in its own pass before the rest of the package; this proves that ordering held.
        XCTAssertEqual(try unzipList(output).first, "mimetype")
    }

    func testCoverXHTMLIsWrittenWhenIncludeCoverIsTrueAndTheCoverImageResolves() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        try makePNG(at: root.appendingPathComponent("cover.png"))
        let metadata = makeMetadata(coverImageRelativePath: "cover.png", coverAltText: "A blue square cover")
        let plan = makePlan(format: .epub, profile: makeProfile(includeCover: true), metadata: metadata)
        let section = makeSection()
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let entries = try unzipList(output)
        XCTAssertTrue(entries.contains("EPUB/text/cover.xhtml"))
        XCTAssertTrue(entries.contains { $0.hasPrefix("EPUB/images/cover.") })
        let cover = try unzipText(output, path: "EPUB/text/cover.xhtml")
        XCTAssertTrue(cover.contains("A blue square cover"))
        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertTrue(opf.contains("cover-page"))
    }

    func testCoverXHTMLIsOmittedWhenIncludeCoverIsFalse() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        // No cover.png is ever written under `root`: if the writer tried to resolve or copy it despite
        // includeCover being false, this test would fail with a file-not-found error instead of passing.
        let metadata = makeMetadata(coverImageRelativePath: "cover.png", coverAltText: "unused")
        let plan = makePlan(format: .epub, profile: makeProfile(includeCover: false), metadata: metadata)
        let section = makeSection()
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        XCTAssertFalse(try unzipList(output).contains("EPUB/text/cover.xhtml"))
    }

    func testEPUBUnsupportedContentImageExtensionThrows() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let imageURL = root.appendingPathComponent("figure.tiff")
        try makeFile(at: imageURL)
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A figure")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        XCTAssertThrowsError(try EPUBPublicationWriter.write(book, to: output, root: root)) { error in
            guard let publicationError = error as? PublicationExportError else {
                return XCTFail("expected PublicationExportError, got \(error)")
            }
            guard case .unsupportedImage(let name) = publicationError else {
                return XCTFail("expected unsupportedImage, got \(publicationError)")
            }
            XCTAssertEqual(name, "figure.tiff")
        }
    }

    func testEPUBUnsupportedCoverImageExtensionThrows() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        try makeFile(at: root.appendingPathComponent("cover.tiff"))
        let metadata = makeMetadata(coverImageRelativePath: "cover.tiff", coverAltText: "Cover")
        let plan = makePlan(format: .epub, profile: makeProfile(includeCover: true), metadata: metadata)
        let section = makeSection()
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        XCTAssertThrowsError(try EPUBPublicationWriter.write(book, to: output, root: root)) { error in
            guard let publicationError = error as? PublicationExportError else {
                return XCTFail("expected PublicationExportError, got \(error)")
            }
            guard case .unsupportedImage(let name) = publicationError else {
                return XCTFail("expected unsupportedImage, got \(publicationError)")
            }
            XCTAssertEqual(name, "cover.tiff")
        }
    }

    func testAccessModeSufficientIsDeclaredWhenEveryImageHasAltText() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let imageURL = root.appendingPathComponent("harbor.png")
        try makePNG(at: imageURL)
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A harbor at dusk")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertTrue(opf.contains("schema:accessModeSufficient"))
    }

    func testAccessModeSufficientIsOmittedWhenAnImageHasNoAltText() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let imageURL = root.appendingPathComponent("harbor.png")
        try makePNG(at: imageURL)
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertFalse(opf.contains("schema:accessModeSufficient"))
    }

    func testAccessibilityHazardNoneIsDeclaredWhenEveryImageIsJPEGOrPNG() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let imageURL = root.appendingPathComponent("harbor.png")
        try makePNG(at: imageURL)
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A harbor")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertTrue(opf.contains("schema:accessibilityHazard"))
    }

    func testAccessibilityHazardNoneIsOmittedWhenAnImageIsNotJPEGOrPNG() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let imageURL = root.appendingPathComponent("harbor.webp")
        try makeFile(at: imageURL)
        let plan = makePlan(format: .epub, profile: makeProfile(), metadata: makeMetadata())
        let section = makeSection(blocks: [imageBlock(url: imageURL, altText: "A harbor")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let opf = try unzipText(output, path: "EPUB/package.opf")
        XCTAssertFalse(opf.contains("schema:accessibilityHazard"))
    }

    func testFootnoteAsidesAreAppendedToTheOwningSectionWhenCitationModeIsFootnotes() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.epub")
        let plan = makePlan(format: .epub, profile: makeProfile(citationMode: .footnotes), metadata: makeMetadata())
        let section = makeSection(bodyHTML: "<p>A claim worth citing.</p>", noteIDs: [1])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [PublicationNote(id: 1, text: "Source, 2024.")])

        try EPUBPublicationWriter.write(book, to: output, root: root)

        let chapter = try unzipText(output, path: "EPUB/text/section-001.xhtml")
        XCTAssertTrue(chapter.contains("A claim worth citing."))
        XCTAssertTrue(chapter.contains("epub:type=\"footnote\""))
        XCTAssertTrue(chapter.contains("Source, 2024."))
    }

    // MARK: - PDFPublicationWriter

    func testWriterProducesAValidPDFContainingTheSectionText() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        let plan = makePlan(format: .readerPDF, profile: makeProfile(layout: .fiction), metadata: makeMetadata())
        let section = makeSection(blocks: [heading("Chapter One"), paragraph("It was a dark and stormy night.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let data = try Data(contentsOf: output)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("Chapter One") == true)
        XCTAssertTrue(document.string?.contains("It was a dark and stormy night.") == true)
    }

    func testPrintBleedAddsBleedToTheMediaBoxWithoutChangingTheTrimBox() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        let profile = makeProfile(layout: .nonfiction, printBleed: .outside)
        let plan = makePlan(format: .printPDF, profile: profile, metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let document = try XCTUnwrap(PDFDocument(url: output))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let media = firstPage.bounds(for: .mediaBox)
        let trim = firstPage.bounds(for: .trimBox)
        XCTAssertEqual(trim.width, profile.layout.pageSize.widthPoints, accuracy: 0.5)
        XCTAssertEqual(trim.height, profile.layout.pageSize.heightPoints, accuracy: 0.5)
        // .outside bleed is 9pt: 9pt of horizontal bleed on the outer edge, 9pt top and bottom (18pt total).
        XCTAssertEqual(media.width, trim.width + 9, accuracy: 0.5)
        XCTAssertEqual(media.height, trim.height + 18, accuracy: 0.5)
    }

    func testReaderPDFFormatAppliesNoBleedRegardlessOfProfilePrintBleed() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        // The profile asks for bleed, but bleed only ever applies to .printPDF -- .readerPDF must ignore it.
        let profile = makeProfile(layout: .nonfiction, printBleed: .outside)
        let plan = makePlan(format: .readerPDF, profile: profile, metadata: makeMetadata())
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let document = try XCTUnwrap(PDFDocument(url: output))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let media = firstPage.bounds(for: .mediaBox)
        XCTAssertEqual(media.width, profile.layout.pageSize.widthPoints, accuracy: 0.5)
        XCTAssertEqual(media.height, profile.layout.pageSize.heightPoints, accuracy: 0.5)
    }

    func testCoverImageIsIncludedAsAFirstPageForReaderPDFWhenIncludeCoverIsTrue() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        try makePNG(at: root.appendingPathComponent("cover.png"))
        let metadata = makeMetadata(coverImageRelativePath: "cover.png", coverAltText: "Cover")
        let plan = makePlan(format: .readerPDF, profile: makeProfile(includeCover: true), metadata: metadata)
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
    }

    func testCoverImageIsOmittedForPrintPDFEvenWhenIncludeCoverIsTrue() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        try makePNG(at: root.appendingPathComponent("cover.png"))
        let metadata = makeMetadata(coverImageRelativePath: "cover.png", coverAltText: "Cover")
        let plan = makePlan(format: .printPDF, profile: makeProfile(includeCover: true), metadata: metadata)
        let section = makeSection(blocks: [paragraph("Text.")])
        let book = PublicationRenderedBook(plan: plan, sections: [section], notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 1)
    }

    func testRectoChapterOpeningInsertsABlankPageSoTheSecondChapterStartsOnAnOddPage() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        var layout = PublicationLayout.fiction
        layout.chapterOpening = .recto
        let plan = makePlan(format: .printPDF, profile: makeProfile(layout: layout), metadata: makeMetadata())
        let sections = [
            makeSection(id: "chapter-1", title: "Chapter One", blocks: [paragraph("First chapter text.")]),
            makeSection(id: "chapter-2", title: "Chapter Two", blocks: [paragraph("Second chapter text.")])
        ]
        let book = PublicationRenderedBook(plan: plan, sections: sections, notes: [])

        try PDFPublicationWriter.write(book, to: output, root: root)

        let document = try XCTUnwrap(PDFDocument(url: output))
        // Chapter one fills page 1. Since page 2 (the next chapter's start) would be even, a blank
        // page 2 is inserted so "Chapter Two" lands on the odd, right-hand page 3.
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertFalse(document.page(at: 1)?.string?.contains("chapter text") ?? true)
        XCTAssertTrue(document.page(at: 2)?.string?.contains("Second chapter text.") == true)
    }

    func testWriterThrowsOutputCreationFailedWhenThereIsNoContentToPaginate() throws {
        let root = temporaryDirectory()
        let outputDir = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outputDir)
        }
        let output = outputDir.appendingPathComponent("Book.pdf")
        let plan = makePlan(format: .readerPDF, profile: makeProfile(), metadata: makeMetadata())
        let book = PublicationRenderedBook(plan: plan, sections: [], notes: [])

        XCTAssertThrowsError(try PDFPublicationWriter.write(book, to: output, root: root)) { error in
            guard let publicationError = error as? PublicationExportError else {
                return XCTFail("expected PublicationExportError, got \(error)")
            }
            guard case .outputCreationFailed(let message) = publicationError else {
                return XCTFail("expected outputCreationFailed, got \(publicationError)")
            }
            XCTAssertEqual(message, "No printable pages were generated.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: - Fixture helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kistulentz-Writer-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePNG(at url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    /// Writes a plain-text stand-in at `url`. The writers decide whether an image is supported purely by
    /// file extension (`PublicationMediaType.docx`/`.epub`), so a fixture only needs real image bytes when
    /// a test also expects the writer to decode it (DOCX measures cover/content images for page layout).
    private func makeFile(at url: URL, contents: String = "not a real image") throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeProfile(
        layout: PublicationLayout = .fiction,
        citationMode: PublicationCitationMode = .parenthetical,
        includeCover: Bool = false,
        printBleed: PublicationPrintBleed = .none
    ) -> ExportProfile {
        ExportProfile(
            name: "Test Profile",
            kind: .custom,
            preferredFormat: .epub,
            layout: layout,
            citationMode: citationMode,
            includeCover: includeCover,
            printBleed: printBleed
        )
    }

    private func makeMetadata(
        title: String = "Test Book",
        coverImageRelativePath: String? = nil,
        coverAltText: String = ""
    ) -> PublicationMetadata {
        var metadata = PublicationMetadata(title: title)
        metadata.authors = ["Author Name"]
        metadata.coverImageRelativePath = coverImageRelativePath
        metadata.coverAltText = coverAltText
        return metadata
    }

    /// Builds a `PublicationExportPlan` directly rather than through `PublicationPlanBuilder`. None of the
    /// three writers read `items`, `bibliography`, `sources`, or `destinations` -- only `profile`,
    /// `format`, and `metadata` -- so those fields are left empty here.
    private func makePlan(
        format: PublicationExportFormat,
        profile: ExportProfile,
        metadata: PublicationMetadata
    ) -> PublicationExportPlan {
        PublicationExportPlan(
            projectName: metadata.title,
            profile: profile,
            format: format,
            items: [],
            metadata: metadata,
            bibliography: ProjectBibliographyArchive(),
            sources: [],
            destinations: []
        )
    }

    private func makeSection(
        id: String = "chapter-1",
        title: String = "Chapter One",
        kind: ExportPlanItemKind = .manuscript,
        blocks: [PublicationBlock] = [],
        bodyHTML: String = "<p>Test paragraph.</p>",
        noteIDs: [Int] = []
    ) -> PublicationRenderedSection {
        PublicationRenderedSection(id: id, title: title, kind: kind, blocks: blocks, bodyHTML: bodyHTML, sourcePath: nil, noteIDs: noteIDs)
    }

    private func paragraph(_ text: String) -> PublicationBlock {
        PublicationBlock(kind: .paragraph, text: text, html: "<p>\(text)</p>", imageURL: nil, altText: "")
    }

    private func heading(_ text: String, level: Int = 1) -> PublicationBlock {
        PublicationBlock(kind: .heading(level), text: text, html: "<h\(level)>\(text)</h\(level)>", imageURL: nil, altText: "")
    }

    private func imageBlock(url: URL, altText: String, caption: String = "") -> PublicationBlock {
        PublicationBlock(kind: .image, text: caption, html: "", imageURL: url, altText: altText)
    }

    // MARK: - Zip helpers

    private func unzipList(_ archive: URL) throws -> [String] {
        try run("/usr/bin/unzip", arguments: ["-Z1", archive.path]).components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private func unzipText(_ archive: URL, path: String) throws -> String {
        let literalPattern = path.replacingOccurrences(of: "[", with: "[[]")
        return try run("/usr/bin/unzip", arguments: ["-p", archive.path, literalPattern])
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

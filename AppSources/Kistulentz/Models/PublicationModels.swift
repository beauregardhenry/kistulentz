import Foundation

enum PublicationExportFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case epub
    case printPDF
    case readerPDF
    case docx

    var id: String { rawValue }
    var title: String {
        switch self {
        case .epub: "EPUB 3"
        case .printPDF: "Print Interior PDF"
        case .readerPDF: "Reader PDF"
        case .docx: "DOCX"
        }
    }
    var fileExtension: String {
        switch self {
        case .epub: "epub"
        case .printPDF, .readerPDF: "pdf"
        case .docx: "docx"
        }
    }
    var systemImage: String {
        switch self {
        case .epub: "book.closed"
        case .printPDF: "printer"
        case .readerPDF: "doc.richtext"
        case .docx: "doc.text"
        }
    }
}

enum PublicationDestination: String, Codable, CaseIterable, Identifiable, Hashable {
    case genericEPUB
    case appleBooks
    case kindleEbook
    case kdpPrint
    case ingramSparkEbook
    case ingramSparkPrint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .genericEPUB: "Generic EPUB 3.3"
        case .appleBooks: "Apple Books"
        case .kindleEbook: "Kindle / KDP eBook"
        case .kdpPrint: "KDP Print"
        case .ingramSparkEbook: "IngramSpark eBook"
        case .ingramSparkPrint: "IngramSpark Print"
        }
    }

    var shortTitle: String {
        switch self {
        case .genericEPUB: "EPUB 3.3"
        case .appleBooks: "Apple Books"
        case .kindleEbook: "Kindle"
        case .kdpPrint: "KDP Print"
        case .ingramSparkEbook: "Ingram eBook"
        case .ingramSparkPrint: "Ingram Print"
        }
    }

    var compatibleFormats: [PublicationExportFormat] {
        switch self {
        case .genericEPUB, .appleBooks, .kindleEbook, .ingramSparkEbook: [.epub]
        case .kdpPrint, .ingramSparkPrint: [.printPDF]
        }
    }

    var requirementURL: String {
        switch self {
        case .genericEPUB: "https://www.w3.org/TR/epub-33/"
        case .appleBooks: "https://help.apple.com/itc/booksassetguide/en.lproj/static.html"
        case .kindleEbook: "https://kdp.amazon.com/en_US/help/topic/G200634390/"
        case .kdpPrint: "https://kdp.amazon.com/en_US/help/topic/G201857950"
        case .ingramSparkEbook, .ingramSparkPrint: "https://www.ingramspark.com/hubfs/downloads/file-creation-guide.pdf"
        }
    }
}

enum PublicationPrintBleed: String, Codable, CaseIterable, Identifiable {
    case none
    case outside

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "No Bleed"
        case .outside: "0.125 in Outside Bleed"
        }
    }

    var points: Double { self == .outside ? 9 : 0 }
}

enum ExportProfileKind: String, Codable, CaseIterable, Identifiable {
    case fictionBook
    case nonfictionBook
    case agentSubmission
    case accessibleEPUB
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fictionBook: "Fiction Book"
        case .nonfictionBook: "Nonfiction Book"
        case .agentSubmission: "Agent Submission"
        case .accessibleEPUB: "Accessible EPUB"
        case .custom: "Custom"
        }
    }
}

enum PublicationPageSize: String, Codable, CaseIterable, Identifiable {
    case fiveByEight
    case fiveAndHalfByEightAndHalf
    case sixByNine
    case a5
    case usLetter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveByEight: "5 × 8 in"
        case .fiveAndHalfByEightAndHalf: "5.5 × 8.5 in"
        case .sixByNine: "6 × 9 in"
        case .a5: "A5"
        case .usLetter: "US Letter"
        }
    }
    var widthPoints: Double {
        switch self {
        case .fiveByEight: 360
        case .fiveAndHalfByEightAndHalf: 396
        case .sixByNine: 432
        case .a5: 419.53
        case .usLetter: 612
        }
    }
    var heightPoints: Double {
        switch self {
        case .fiveByEight: 576
        case .fiveAndHalfByEightAndHalf: 612
        case .sixByNine: 648
        case .a5: 595.28
        case .usLetter: 792
        }
    }
}

enum PublicationCitationMode: String, Codable, CaseIterable, Identifiable {
    case parenthetical
    case footnotes
    case endnotes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .parenthetical: "Parenthetical Citations"
        case .footnotes: "Footnotes"
        case .endnotes: "Endnotes"
        }
    }
}

enum PublicationChapterOpening: String, Codable, CaseIterable, Identifiable {
    case newPage
    case recto
    case continuous

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newPage: "New Page"
        case .recto: "Right-Hand Page"
        case .continuous: "Continuous"
        }
    }
}

struct PublicationLayout: Codable, Equatable {
    var pageSize: PublicationPageSize
    var bodyFontName: String
    var headingFontName: String
    var bodyFontSize: Double
    var lineHeightMultiple: Double
    var paragraphSpacing: Double
    var topMargin: Double
    var bottomMargin: Double
    var insideMargin: Double
    var outsideMargin: Double
    var headerEnabled: Bool
    var footerEnabled: Bool
    var pageNumbersEnabled: Bool
    var chapterOpening: PublicationChapterOpening
    var firstLineIndent: Double
    var hyphenationEnabled: Bool

    static let fiction = PublicationLayout(
        pageSize: .fiveAndHalfByEightAndHalf,
        bodyFontName: "Palatino",
        headingFontName: "Avenir Next",
        bodyFontSize: 10.5,
        lineHeightMultiple: 1.18,
        paragraphSpacing: 3,
        topMargin: 54,
        bottomMargin: 54,
        insideMargin: 54,
        outsideMargin: 45,
        headerEnabled: true,
        footerEnabled: false,
        pageNumbersEnabled: true,
        chapterOpening: .newPage,
        firstLineIndent: 18,
        hyphenationEnabled: true
    )

    static let nonfiction = PublicationLayout(
        pageSize: .sixByNine,
        bodyFontName: "Charter",
        headingFontName: "Avenir Next",
        bodyFontSize: 10.5,
        lineHeightMultiple: 1.22,
        paragraphSpacing: 7,
        topMargin: 54,
        bottomMargin: 54,
        insideMargin: 58,
        outsideMargin: 48,
        headerEnabled: true,
        footerEnabled: false,
        pageNumbersEnabled: true,
        chapterOpening: .newPage,
        firstLineIndent: 0,
        hyphenationEnabled: true
    )

    static let agent = PublicationLayout(
        pageSize: .usLetter,
        bodyFontName: "Times New Roman",
        headingFontName: "Times New Roman",
        bodyFontSize: 12,
        lineHeightMultiple: 2,
        paragraphSpacing: 0,
        topMargin: 72,
        bottomMargin: 72,
        insideMargin: 72,
        outsideMargin: 72,
        headerEnabled: true,
        footerEnabled: false,
        pageNumbersEnabled: true,
        chapterOpening: .newPage,
        firstLineIndent: 36,
        hyphenationEnabled: false
    )

    static let accessible = PublicationLayout(
        pageSize: .a5,
        bodyFontName: "system-ui",
        headingFontName: "system-ui",
        bodyFontSize: 12,
        lineHeightMultiple: 1.5,
        paragraphSpacing: 9,
        topMargin: 54,
        bottomMargin: 54,
        insideMargin: 54,
        outsideMargin: 54,
        headerEnabled: false,
        footerEnabled: false,
        pageNumbersEnabled: false,
        chapterOpening: .newPage,
        firstLineIndent: 0,
        hyphenationEnabled: false
    )
}

struct ExportProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: ExportProfileKind
    var preferredFormat: PublicationExportFormat
    var layout: PublicationLayout
    var citationMode: PublicationCitationMode
    var includeBibliography: Bool
    var includeCover: Bool
    var includeTableOfContents: Bool
    var includeFrontMatter: Bool
    var includeBackMatter: Bool
    var embedFontsInEPUB: Bool
    var printBleed: PublicationPrintBleed
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: ExportProfileKind,
        preferredFormat: PublicationExportFormat,
        layout: PublicationLayout,
        citationMode: PublicationCitationMode = .parenthetical,
        includeBibliography: Bool = true,
        includeCover: Bool = true,
        includeTableOfContents: Bool = true,
        includeFrontMatter: Bool = true,
        includeBackMatter: Bool = true,
        embedFontsInEPUB: Bool = false,
        printBleed: PublicationPrintBleed = .none,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.preferredFormat = preferredFormat
        self.layout = layout
        self.citationMode = citationMode
        self.includeBibliography = includeBibliography
        self.includeCover = includeCover
        self.includeTableOfContents = includeTableOfContents
        self.includeFrontMatter = includeFrontMatter
        self.includeBackMatter = includeBackMatter
        self.embedFontsInEPUB = embedFontsInEPUB
        self.printBleed = printBleed
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, preferredFormat, layout, citationMode, includeBibliography
        case includeCover, includeTableOfContents, includeFrontMatter, includeBackMatter
        case embedFontsInEPUB, printBleed, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ExportProfileKind.self, forKey: .kind)
        preferredFormat = try container.decode(PublicationExportFormat.self, forKey: .preferredFormat)
        layout = try container.decode(PublicationLayout.self, forKey: .layout)
        citationMode = try container.decode(PublicationCitationMode.self, forKey: .citationMode)
        includeBibliography = try container.decode(Bool.self, forKey: .includeBibliography)
        includeCover = try container.decode(Bool.self, forKey: .includeCover)
        includeTableOfContents = try container.decode(Bool.self, forKey: .includeTableOfContents)
        includeFrontMatter = try container.decode(Bool.self, forKey: .includeFrontMatter)
        includeBackMatter = try container.decode(Bool.self, forKey: .includeBackMatter)
        embedFontsInEPUB = try container.decodeIfPresent(Bool.self, forKey: .embedFontsInEPUB) ?? false
        printBleed = try container.decodeIfPresent(PublicationPrintBleed.self, forKey: .printBleed) ?? .none
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    static func builtIns(for kind: WritingProjectKind) -> [ExportProfile] {
        let fictionID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let nonfictionID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000000903")!
        let accessibleID = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let profiles = [
            ExportProfile(id: fictionID, name: "Fiction Book", kind: .fictionBook, preferredFormat: .epub, layout: .fiction, citationMode: .parenthetical, includeBibliography: false),
            ExportProfile(id: nonfictionID, name: "Nonfiction Book", kind: .nonfictionBook, preferredFormat: .printPDF, layout: .nonfiction),
            ExportProfile(id: agentID, name: "Agent Submission", kind: .agentSubmission, preferredFormat: .docx, layout: .agent, citationMode: .parenthetical, includeBibliography: false, includeCover: false, includeTableOfContents: false, includeFrontMatter: false, includeBackMatter: false),
            ExportProfile(id: accessibleID, name: "Accessible EPUB", kind: .accessibleEPUB, preferredFormat: .epub, layout: .accessible)
        ]
        return kind == .fiction ? profiles : [profiles[1], profiles[0], profiles[2], profiles[3]]
    }
}

struct PublicationMetadata: Codable, Equatable {
    var title: String
    var subtitle: String
    var authors: [String]
    var language: String
    var identifier: String
    var publisher: String
    var publicationDate: String
    var edition: String
    var rights: String
    var description: String
    var keywords: [String]
    var coverImageRelativePath: String?
    var coverAltText: String
    var printCoverPDFRelativePath: String?

    init(title: String = "") {
        self.title = title
        subtitle = ""
        authors = []
        language = "en-US"
        identifier = UUID().uuidString
        publisher = ""
        publicationDate = ""
        edition = ""
        rights = ""
        description = ""
        keywords = []
        coverImageRelativePath = nil
        coverAltText = ""
        printCoverPDFRelativePath = nil
    }
}

enum PublicationMatterKind: String, Codable, CaseIterable, Identifiable {
    case halfTitle
    case titlePage
    case copyright
    case dedication
    case epigraph
    case tableOfContents
    case preface
    case acknowledgments
    case endnotes
    case bibliography
    case aboutAuthor

    var id: String { rawValue }
    var title: String {
        switch self {
        case .halfTitle: "Half Title"
        case .titlePage: "Title Page"
        case .copyright: "Copyright"
        case .dedication: "Dedication"
        case .epigraph: "Epigraph"
        case .tableOfContents: "Table of Contents"
        case .preface: "Preface"
        case .acknowledgments: "Acknowledgments"
        case .endnotes: "Endnotes"
        case .bibliography: "Bibliography"
        case .aboutAuthor: "About the Author"
        }
    }
    var isFrontMatter: Bool {
        switch self {
        case .halfTitle, .titlePage, .copyright, .dedication, .epigraph, .tableOfContents, .preface: true
        default: false
        }
    }
}

struct PublicationMatterItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: PublicationMatterKind
    var title: String
    var markdown: String
    var lastGeneratedMarkdown: String
    var isIncluded: Bool
    var isLocked: Bool

    init(
        id: UUID = UUID(),
        kind: PublicationMatterKind,
        title: String? = nil,
        markdown: String = "",
        lastGeneratedMarkdown: String = "",
        isIncluded: Bool,
        isLocked: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.markdown = markdown
        self.lastGeneratedMarkdown = lastGeneratedMarkdown
        self.isIncluded = isIncluded
        self.isLocked = isLocked
    }

    var hasAuthorEdits: Bool { markdown != lastGeneratedMarkdown }
}

struct ExportHistoryRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var profileID: UUID
    var profileName: String
    var format: PublicationExportFormat
    var outputPath: String
    var sha256: String
    var byteCount: Int64
    var warningCount: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        profileID: UUID,
        profileName: String,
        format: PublicationExportFormat,
        outputPath: String,
        sha256: String,
        byteCount: Int64,
        warningCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.profileID = profileID
        self.profileName = profileName
        self.format = format
        self.outputPath = outputPath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.warningCount = warningCount
    }
}

struct PublicationArchive: Codable, Equatable {
    var schemaVersion = KistulentzProjectFormat.currentVersion
    var metadata: PublicationMetadata
    var profiles: [ExportProfile]
    var selectedProfileID: UUID
    var selectedDestinations: [PublicationDestination]
    var matter: [PublicationMatterItem]
    var history: [ExportHistoryRecord]

    init(projectName: String = "Project", projectKind: WritingProjectKind = .fiction) {
        metadata = PublicationMetadata(title: projectName)
        profiles = ExportProfile.builtIns(for: projectKind)
        selectedProfileID = profiles[0].id
        selectedDestinations = profiles[0].preferredFormat == .epub ? [.genericEPUB] : []
        matter = PublicationMatterGenerator.defaultItems(metadata: metadata)
        history = []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, metadata, profiles, selectedProfileID, selectedDestinations, matter, history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? KistulentzProjectFormat.currentVersion
        metadata = try container.decode(PublicationMetadata.self, forKey: .metadata)
        let decodedProfiles = try container.decode([ExportProfile].self, forKey: .profiles)
        let decodedSelectedProfileID = try container.decode(UUID.self, forKey: .selectedProfileID)
        profiles = decodedProfiles
        selectedProfileID = decodedSelectedProfileID
        selectedDestinations = try container.decodeIfPresent([PublicationDestination].self, forKey: .selectedDestinations)
            ?? (decodedProfiles.first(where: { $0.id == decodedSelectedProfileID })?.preferredFormat == .epub ? [.genericEPUB] : [])
        matter = try container.decode([PublicationMatterItem].self, forKey: .matter)
        history = try container.decodeIfPresent([ExportHistoryRecord].self, forKey: .history) ?? []
    }
}

enum ExportPlanItemKind: String, Codable, Equatable {
    case frontMatter
    case part
    case manuscript
    case backMatter
}

struct ExportPlanItem: Identifiable, Equatable {
    var id: String
    var kind: ExportPlanItemKind
    var title: String
    var markdown: String
    var sourcePath: String?
    var outlineNodeID: UUID?
    var depth: Int
    var isIncluded: Bool
    var exclusionReason: String?
    var matterKind: PublicationMatterKind?
}

struct PublicationExportPlan: Equatable {
    var projectName: String
    var profile: ExportProfile
    var format: PublicationExportFormat
    var items: [ExportPlanItem]
    var metadata: PublicationMetadata
    var bibliography: ProjectBibliographyArchive
    var sources: [ResearchSource]
    var destinations: [PublicationDestination]

    var includedItems: [ExportPlanItem] { items.filter(\.isIncluded) }
    var manuscriptItems: [ExportPlanItem] { includedItems.filter { $0.kind == .manuscript } }
}

enum PublicationPreflightSeverity: String, Codable, CaseIterable, Identifiable {
    case error
    case warning
    case information

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PublicationReadinessStatus: String, Codable, CaseIterable, Identifiable {
    case actionRequired
    case passedLocally
    case externalValidationRequired
    case manualReviewRequired

    var id: String { rawValue }
    var title: String {
        switch self {
        case .actionRequired: "Action Required"
        case .passedLocally: "Passed Locally"
        case .externalValidationRequired: "External Validation Required"
        case .manualReviewRequired: "Manual Review Required"
        }
    }
}

struct PublicationPreflightFinding: Identifiable, Equatable {
    var id: String
    var severity: PublicationPreflightSeverity
    var title: String
    var detail: String
    var sourcePath: String?
    var readinessStatus: PublicationReadinessStatus = .actionRequired
    var requirementURL: String? = nil
}

struct PublicationPreflightReport: Equatable {
    var findings: [PublicationPreflightFinding]
    var errors: [PublicationPreflightFinding] { findings.filter { $0.severity == .error } }
    var warnings: [PublicationPreflightFinding] { findings.filter { $0.severity == .warning } }
    var information: [PublicationPreflightFinding] { findings.filter { $0.severity == .information } }
    var canExport: Bool { errors.isEmpty }
}

struct PublicationExportResult: Equatable {
    var outputURL: URL
    var sha256: String
    var byteCount: Int64
    var preflight: PublicationPreflightReport
    var packageURL: URL? = nil
    var reportMarkdownURL: URL? = nil
    var reportPDFURL: URL? = nil
    var validatorRuns: [PublicationValidatorRun] = []
}

struct PublicationValidatorRun: Codable, Identifiable, Equatable {
    var id: String { validator.rawValue }
    var validator: PublicationExternalValidator
    var status: PublicationValidatorRunStatus
    var summary: String
    var output: String
}

enum PublicationExternalValidator: String, Codable, CaseIterable, Identifiable {
    case epubCheck
    case kindlePreviewer
    case appleTransporter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .epubCheck: "EPUBCheck"
        case .kindlePreviewer: "Kindle Previewer"
        case .appleTransporter: "Apple Transporter"
        }
    }
}

enum PublicationValidatorRunStatus: String, Codable, Equatable {
    case passed
    case failed
    case available
    case notInstalled
    case notApplicable
}

enum PublicationExportError: LocalizedError, Equatable {
    case missingProject
    case missingProfile
    case preflightFailed
    case warningConfirmationRequired
    case noIncludedManuscript
    case unsupportedImage(String)
    case archiveCreationFailed(String)
    case outputCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProject: "Open a Kistulentz project before publishing."
        case .missingProfile: "Choose an export profile first."
        case .preflightFailed: "Resolve every blocking preflight error before exporting."
        case .warningConfirmationRequired: "Review the preflight warnings and explicitly approve them before exporting."
        case .noIncludedManuscript: "The export plan does not contain any included manuscript sections."
        case .unsupportedImage(let name): "Kistulentz could not prepare the image \(name) for export."
        case .archiveCreationFailed(let message): "Kistulentz could not assemble the publication archive: \(message)"
        case .outputCreationFailed(let message): "Kistulentz could not create the exported book: \(message)"
        }
    }
}

enum PublicationMatterGenerator {
    static func defaultItems(metadata: PublicationMetadata) -> [PublicationMatterItem] {
        PublicationMatterKind.allCases.map { kind in
            let included: Bool
            switch kind {
            case .halfTitle, .titlePage, .copyright, .tableOfContents: included = true
            case .bibliography: included = false
            default: included = false
            }
            let generated = generatedMarkdown(for: kind, metadata: metadata)
            return PublicationMatterItem(
                id: stableID(kind),
                kind: kind,
                markdown: generated,
                lastGeneratedMarkdown: generated,
                isIncluded: included
            )
        }
    }

    static func regenerating(_ items: [PublicationMatterItem], metadata: PublicationMetadata) -> [PublicationMatterItem] {
        let existing = items.reduce(into: [PublicationMatterKind: PublicationMatterItem]()) { result, item in
            if result[item.kind] == nil { result[item.kind] = item }
        }
        return PublicationMatterKind.allCases.map { kind in
            guard var item = existing[kind] else {
                return defaultItems(metadata: metadata).first { $0.kind == kind }!
            }
            guard !item.isLocked, !item.hasAuthorEdits else { return item }
            let generated = generatedMarkdown(for: kind, metadata: metadata)
            item.markdown = generated
            item.lastGeneratedMarkdown = generated
            return item
        }
    }

    static func generatedMarkdown(for kind: PublicationMatterKind, metadata: PublicationMetadata) -> String {
        let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = metadata.authors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch kind {
        case .halfTitle:
            return title.isEmpty ? "" : "# \(title)\n"
        case .titlePage:
            var lines = title.isEmpty ? [] : ["# \(title)"]
            if !metadata.subtitle.isEmpty { lines += ["", "## \(metadata.subtitle)"] }
            if !authors.isEmpty { lines += ["", "by \(authors.joined(separator: ", "))"] }
            if !metadata.publisher.isEmpty { lines += ["", metadata.publisher] }
            return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        case .copyright:
            let year = Calendar.current.component(.year, from: Date())
            let holder = authors.joined(separator: ", ")
            var lines = ["# Copyright", "", holder.isEmpty ? "Copyright © \(year)." : "Copyright © \(year) \(holder).", "All rights reserved."]
            if !metadata.identifier.isEmpty { lines += ["", "Identifier: \(metadata.identifier)"] }
            if !metadata.edition.isEmpty { lines.append("Edition: \(metadata.edition)") }
            return lines.joined(separator: "\n") + "\n"
        case .tableOfContents:
            return "# Table of Contents\n\n<!-- Kistulentz generates entries from the approved export plan. -->\n"
        case .bibliography:
            return "# Bibliography\n\n<!-- Kistulentz generates entries from project sources. -->\n"
        case .endnotes:
            return "# Notes\n\n<!-- Kistulentz generates notes from citations and Markdown footnotes. -->\n"
        case .dedication: return "# Dedication\n\n"
        case .epigraph: return "# Epigraph\n\n"
        case .preface: return "# Preface\n\n"
        case .acknowledgments: return "# Acknowledgments\n\n"
        case .aboutAuthor:
            return authors.isEmpty ? "# About the Author\n\n" : "# About \(authors.joined(separator: " and "))\n\n"
        }
    }

    private static func stableID(_ kind: PublicationMatterKind) -> UUID {
        let suffix = PublicationMatterKind.allCases.firstIndex(of: kind)! + 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 900 + suffix))!
    }
}

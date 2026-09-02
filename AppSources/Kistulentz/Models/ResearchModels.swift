import Foundation

enum ResearchSourceType: String, Codable, CaseIterable, Identifiable {
    case book
    case bookChapter
    case journalArticle
    case magazineArticle
    case newspaperArticle
    case webpage
    case report
    case thesis
    case conferencePaper
    case dataset
    case interview
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .book: "Book"
        case .bookChapter: "Book Chapter"
        case .journalArticle: "Journal Article"
        case .magazineArticle: "Magazine Article"
        case .newspaperArticle: "Newspaper Article"
        case .webpage: "Web Page"
        case .report: "Report"
        case .thesis: "Thesis"
        case .conferencePaper: "Conference Paper"
        case .dataset: "Dataset"
        case .interview: "Interview"
        case .other: "Other"
        }
    }

    var cslType: String {
        switch self {
        case .book: "book"
        case .bookChapter: "chapter"
        case .journalArticle: "article-journal"
        case .magazineArticle: "article-magazine"
        case .newspaperArticle: "article-newspaper"
        case .webpage: "webpage"
        case .report: "report"
        case .thesis: "thesis"
        case .conferencePaper: "paper-conference"
        case .dataset: "dataset"
        case .interview: "interview"
        case .other: "document"
        }
    }

    init(cslType: String) {
        switch cslType.lowercased() {
        case "book": self = .book
        case "chapter", "entry", "entry-dictionary", "entry-encyclopedia": self = .bookChapter
        case "article-journal": self = .journalArticle
        case "article-magazine": self = .magazineArticle
        case "article-newspaper": self = .newspaperArticle
        case "webpage", "post", "post-weblog": self = .webpage
        case "report": self = .report
        case "thesis": self = .thesis
        case "paper-conference": self = .conferencePaper
        case "dataset": self = .dataset
        case "interview": self = .interview
        default: self = .other
        }
    }
}

enum ResearchCreatorRole: String, Codable, CaseIterable, Identifiable {
    case author
    case editor
    case translator
    case contributor

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ResearchCreator: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var role: ResearchCreatorRole
    var givenName: String
    var familyName: String
    var literalName: String

    init(
        id: UUID = UUID(),
        role: ResearchCreatorRole = .author,
        givenName: String = "",
        familyName: String = "",
        literalName: String = ""
    ) {
        self.id = id
        self.role = role
        self.givenName = givenName
        self.familyName = familyName
        self.literalName = literalName
    }

    var displayName: String {
        let literal = literalName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !literal.isEmpty { return literal }
        return [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var sortName: String {
        let family = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return family.isEmpty ? displayName : [family, given].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum ResearchAttachmentStorage: String, Codable, CaseIterable, Identifiable {
    case managedCopy
    case linkedOriginal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .managedCopy: "Copy into Research Library"
        case .linkedOriginal: "Link to Original"
        }
    }
}

enum ResearchAttachmentKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case epub
    case webArchive
    case image
    case text
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: "PDF"
        case .epub: "EPUB"
        case .webArchive: "Web Archive"
        case .image: "Image"
        case .text: "Text"
        case .other: "File"
        }
    }

    static func infer(from url: URL) -> ResearchAttachmentKind {
        switch url.pathExtension.lowercased() {
        case "pdf": .pdf
        case "epub": .epub
        case "webarchive", "html", "htm": .webArchive
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp": .image
        case "txt", "md", "rtf": .text
        default: .other
        }
    }
}

enum ResearchExtractionStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted
    case extracted
    case noReadableText
    case failed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notStarted: "Not indexed"
        case .extracted: "Locally indexed"
        case .noReadableText: "No readable text"
        case .failed: "Indexing failed"
        }
    }
}

struct ResearchAttachment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var displayName: String
    var kind: ResearchAttachmentKind
    var storage: ResearchAttachmentStorage
    var storedRelativePath: String?
    var originalPath: String
    var extractedTextRelativePath: String?
    var extractionStatus: ResearchExtractionStatus
    var extractionMessage: String
    var addedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        kind: ResearchAttachmentKind,
        storage: ResearchAttachmentStorage,
        storedRelativePath: String? = nil,
        originalPath: String,
        extractedTextRelativePath: String? = nil,
        extractionStatus: ResearchExtractionStatus = .notStarted,
        extractionMessage: String = "",
        addedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.storage = storage
        self.storedRelativePath = storedRelativePath
        self.originalPath = originalPath
        self.extractedTextRelativePath = extractedTextRelativePath
        self.extractionStatus = extractionStatus
        self.extractionMessage = extractionMessage
        self.addedAt = addedAt
    }
}

struct ResearchSource: Codable, Identifiable, Equatable {
    var id: UUID
    var citeKey: String
    var type: ResearchSourceType
    var title: String
    var subtitle: String
    var creators: [ResearchCreator]
    var issuedYear: Int?
    var issuedDate: String
    var containerTitle: String
    var publisher: String
    var publisherPlace: String
    var volume: String
    var issue: String
    var edition: String
    var pages: String
    var DOI: String
    var ISBN: String
    var URLString: String
    var accessedDate: String
    var abstract: String
    var keywords: [String]
    var libraryNotes: String
    var attachments: [ResearchAttachment]
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        citeKey: String = "",
        type: ResearchSourceType = .book,
        title: String = "",
        subtitle: String = "",
        creators: [ResearchCreator] = [],
        issuedYear: Int? = nil,
        issuedDate: String = "",
        containerTitle: String = "",
        publisher: String = "",
        publisherPlace: String = "",
        volume: String = "",
        issue: String = "",
        edition: String = "",
        pages: String = "",
        DOI: String = "",
        ISBN: String = "",
        URLString: String = "",
        accessedDate: String = "",
        abstract: String = "",
        keywords: [String] = [],
        libraryNotes: String = "",
        attachments: [ResearchAttachment] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.citeKey = citeKey
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.creators = creators
        self.issuedYear = issuedYear
        self.issuedDate = issuedDate
        self.containerTitle = containerTitle
        self.publisher = publisher
        self.publisherPlace = publisherPlace
        self.volume = volume
        self.issue = issue
        self.edition = edition
        self.pages = pages
        self.DOI = DOI
        self.ISBN = ISBN
        self.URLString = URLString
        self.accessedDate = accessedDate
        self.abstract = abstract
        self.keywords = keywords
        self.libraryNotes = libraryNotes
        self.attachments = attachments
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var authors: [ResearchCreator] { creators.filter { $0.role == .author } }
    var primaryCreatorName: String { authors.first?.displayName ?? creators.first?.displayName ?? "Unknown creator" }
}

struct ResearchLibraryArchive: Codable, Equatable {
    var schemaVersion = 1
    var sources: [ResearchSource] = []
}

enum BibliographyStyle: String, Codable, CaseIterable, Identifiable {
    case chicagoNotes = "chicago-notes"
    case chicagoAuthorDate = "chicago-author-date"
    case apa
    case mla
    case numbered

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chicagoNotes: "Chicago Notes & Bibliography"
        case .chicagoAuthorDate: "Chicago Author-Date"
        case .apa: "APA"
        case .mla: "MLA"
        case .numbered: "Numbered"
        }
    }
}

struct ProjectResearchQuotation: Codable, Identifiable, Equatable {
    var id: UUID
    var sourceID: UUID
    var text: String
    var locator: String
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        text: String,
        locator: String = "",
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceID = sourceID
        self.text = text
        self.locator = locator
        self.note = note
        self.createdAt = createdAt
    }
}

struct ProjectClaimSourceLink: Codable, Identifiable, Equatable {
    var id: UUID
    var sourceID: UUID
    var chapterPath: String
    var claimExcerpt: String
    var locator: String
    var note: String

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        chapterPath: String,
        claimExcerpt: String,
        locator: String = "",
        note: String = ""
    ) {
        self.id = id
        self.sourceID = sourceID
        self.chapterPath = chapterPath
        self.claimExcerpt = claimExcerpt
        self.locator = locator
        self.note = note
    }
}

struct ProjectBibliographyArchive: Codable, Equatable {
    var schemaVersion = KistulentzProjectFormat.currentVersion
    var sourceIDs: [UUID] = []
    var style: BibliographyStyle = .chicagoNotes
    var quotations: [ProjectResearchQuotation] = []
    var claimLinks: [ProjectClaimSourceLink] = []
}

enum ResearchLibraryError: LocalizedError, Equatable {
    case missingLocation
    case missingSource
    case invalidCitationKey
    case duplicateCitationKey(String)
    case unsupportedImport
    case unreadableAttachment(String)
    case metadataNotFound
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .missingLocation: "Choose a Research Library folder first."
        case .missingSource: "That research source no longer exists."
        case .invalidCitationKey: "Enter a citation key using letters, numbers, underscores, hyphens, or colons."
        case .duplicateCitationKey(let key): "The citation key “\(key)” is already in the Research Library."
        case .unsupportedImport: "Kistulentz could not identify a supported BibTeX, RIS, or CSL-JSON record in that file."
        case .unreadableAttachment(let name): "Kistulentz could not extract readable text from \(name)."
        case .metadataNotFound: "No matching metadata was found. You can still enter the source manually."
        case .invalidIdentifier: "Enter a valid DOI or ISBN."
        }
    }
}

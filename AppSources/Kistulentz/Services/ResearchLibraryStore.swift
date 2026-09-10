import AppKit
import Foundation

struct ResearchLibraryPersistence {
    var load: (URL) throws -> ResearchLibraryArchive
    var save: (ResearchLibraryArchive, URL) throws -> Void
    var addAttachment: (URL, UUID, ResearchAttachmentStorage, URL) throws -> ResearchAttachment
    var removeManagedAttachment: (ResearchAttachment, URL) throws -> Void
    var saveExtractedText: (String, UUID, URL) throws -> String
    var removeExtractedText: (String, URL) throws -> Void
    var loadExtractedText: (ResearchAttachment, URL) -> String?
    var attachmentURL: (ResearchAttachment, URL) -> URL
    var extractText: (URL, ResearchAttachmentKind) async throws -> String

    static var live: ResearchLibraryPersistence { ResearchLibraryPersistence(
        load: ResearchLibraryDisk.load,
        save: ResearchLibraryDisk.save,
        addAttachment: { try ResearchLibraryDisk.addAttachment(from: $0, to: $1, storage: $2, at: $3) },
        removeManagedAttachment: { try ResearchLibraryDisk.removeManagedAttachment($0, at: $1) },
        saveExtractedText: { try ResearchLibraryDisk.saveExtractedText($0, for: $1, at: $2) },
        removeExtractedText: { try ResearchLibraryDisk.removeExtractedText(relativePath: $0, at: $1) },
        loadExtractedText: { ResearchLibraryDisk.loadExtractedText(for: $0, at: $1) },
        attachmentURL: { ResearchLibraryDisk.attachmentURL($0, at: $1) },
        extractText: { url, kind in
#if UI_TEST_HOST
            if let rawDelay = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_RESEARCH_INDEX_DELAY_MS"],
               let delayMilliseconds = UInt64(rawDelay),
               delayMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
                try Task.checkCancellation()
            }
#endif
            let task = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                let text = try ResearchTextExtractor.extract(from: url, kind: kind)
                try Task.checkCancellation()
                return text
            }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }
    ) }
}

@MainActor
final class ResearchLibraryStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var sources: [ResearchSource] = []
    @Published private(set) var indexingAttachmentIDs: Set<UUID> = []
    @Published private(set) var isLookingUpMetadata = false
    @Published var searchText = ""
    @Published var errorMessage: String?

    private static let locationKey = "Kistulentz.researchLibraryLocation"
    private let metadataLookup: ResearchMetadataLookupService
    private let persistence: ResearchLibraryPersistence
    private let defaults: UserDefaults

    init(
        metadataLookup: ResearchMetadataLookupService = ResearchMetadataLookupService(),
        persistence: ResearchLibraryPersistence = .live,
        defaults: UserDefaults = .standard
    ) {
        self.metadataLookup = metadataLookup
        self.persistence = persistence
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.locationKey), !path.isEmpty {
            try? open(at: URL(fileURLWithPath: path, isDirectory: true), remember: false)
        }
    }

    var filteredSources: [ResearchSource] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = sources.sorted {
            let creator = $0.primaryCreatorName.localizedCaseInsensitiveCompare($1.primaryCreatorName)
            return creator == .orderedSame
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : creator == .orderedAscending
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { source in
            let metadata = [source.title, source.subtitle, source.primaryCreatorName, source.citeKey,
                            source.DOI, source.ISBN, source.abstract, source.keywords.joined(separator: " ")]
                .joined(separator: "\n")
            if metadata.localizedCaseInsensitiveContains(query) { return true }
            guard let rootURL else { return false }
            return source.attachments.contains {
                persistence.loadExtractedText($0, rootURL)?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }

    func open(at root: URL, remember: Bool = true) throws {
        let standardized = root.standardizedFileURL
        let archive = try persistence.load(standardized)
        rootURL = standardized
        sources = archive.sources
        if remember { defaults.set(standardized.path, forKey: Self.locationKey) }
    }

    @discardableResult
    func addSource(_ draft: ResearchSource = ResearchSource(title: "Untitled Source")) throws -> UUID {
        var source = draft
        source.title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.title.isEmpty { source.title = "Untitled Source" }
        if source.citeKey.isEmpty {
            source.citeKey = ResearchExchange.suggestedCitationKey(for: source, existing: Set(sources.map(\.citeKey)))
        }
        try validate(source)
        var updatedSources = sources
        updatedSources.append(source)
        try persist(updatedSources)
        return source.id
    }

    func updateSource(_ source: ResearchSource) throws {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { throw ResearchLibraryError.missingSource }
        var updated = source
        updated.citeKey = ResearchExchange.normalizedCitationKey(updated.citeKey)
        updated.modifiedAt = Date()
        try validate(updated)
        var updatedSources = sources
        updatedSources[index] = updated
        try persist(updatedSources)
    }

    func removeSource(_ id: UUID) throws {
        guard let rootURL, let index = sources.firstIndex(where: { $0.id == id }) else { throw ResearchLibraryError.missingSource }
        let removed = sources[index]
        var updatedSources = sources
        updatedSources.remove(at: index)
        try persist(updatedSources)
        for attachment in removed.attachments {
            try persistence.removeManagedAttachment(attachment, rootURL)
        }
    }

    @discardableResult
    func importSources(from url: URL) throws -> Int {
        let imported = try ResearchExchange.importSources(from: url)
        var updatedSources = sources
        var added = 0
        for var source in imported {
            if let duplicate = ResearchExchange.duplicate(of: source, in: updatedSources),
               let index = updatedSources.firstIndex(where: { $0.id == duplicate.id }) {
                source.id = duplicate.id
                source.citeKey = duplicate.citeKey
                updatedSources[index] = ResearchExchange.merged(existing: duplicate, incoming: source)
            } else {
                if source.citeKey.isEmpty || updatedSources.contains(where: { $0.citeKey.caseInsensitiveCompare(source.citeKey) == .orderedSame }) {
                    source.citeKey = ResearchExchange.suggestedCitationKey(for: source, existing: Set(updatedSources.map(\.citeKey)))
                }
                updatedSources.append(source)
                added += 1
            }
        }
        try persist(updatedSources)
        return added
    }

    func export(_ selectedSources: [ResearchSource], format: String, to url: URL) throws {
        switch format.lowercased() {
        case "bib", "bibtex": try ResearchExchange.exportBibTeX(selectedSources, to: url)
        case "ris": try ResearchExchange.exportRIS(selectedSources, to: url)
        default: try ResearchExchange.exportCSLJSON(selectedSources, to: url)
        }
    }

    func addAttachment(from url: URL, sourceID: UUID, storage: ResearchAttachmentStorage) async {
        guard let rootURL, let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            errorMessage = ResearchLibraryError.missingLocation.localizedDescription
            return
        }
        do {
            var attachment = try persistence.addAttachment(url, sourceID, storage, rootURL)
            var updatedSources = sources
            updatedSources[index].attachments.append(attachment)
            do {
                try persist(updatedSources)
            } catch {
                try? persistence.removeManagedAttachment(attachment, rootURL)
                throw error
            }
            indexingAttachmentIDs.insert(attachment.id)
            defer { indexingAttachmentIDs.remove(attachment.id) }
            let attachmentURL = persistence.attachmentURL(attachment, rootURL)
            var extractedTextPath: String?
            do {
                try Task.checkCancellation()
                let text = try await persistence.extractText(attachmentURL, attachment.kind)
                try Task.checkCancellation()
                let path = try persistence.saveExtractedText(text, attachment.id, rootURL)
                extractedTextPath = path
                attachment.extractedTextRelativePath = path
                attachment.extractionStatus = .extracted
                attachment.extractionMessage = "Indexed \(text.count.formatted()) characters locally."
            } catch is CancellationError {
                if let extractedTextPath { try? persistence.removeExtractedText(extractedTextPath, rootURL) }
                return
            } catch {
                attachment.extractionStatus = .noReadableText
                attachment.extractionMessage = error.localizedDescription
            }
            if let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }),
               let attachmentIndex = sources[sourceIndex].attachments.firstIndex(where: { $0.id == attachment.id }) {
                var indexedSources = sources
                indexedSources[sourceIndex].attachments[attachmentIndex] = attachment
                do {
                    try persist(indexedSources)
                } catch {
                    if let extractedTextPath { try? persistence.removeExtractedText(extractedTextPath, rootURL) }
                    throw error
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAttachment(_ attachmentID: UUID, sourceID: UUID) throws {
        guard let rootURL,
              let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }),
              let attachmentIndex = sources[sourceIndex].attachments.firstIndex(where: { $0.id == attachmentID }) else {
            throw ResearchLibraryError.missingSource
        }
        var updatedSources = sources
        let attachment = updatedSources[sourceIndex].attachments.remove(at: attachmentIndex)
        try persist(updatedSources)
        try persistence.removeManagedAttachment(attachment, rootURL)
    }

    func lookupDOI(_ value: String) async throws -> ResearchSource {
        isLookingUpMetadata = true
        defer { isLookingUpMetadata = false }
        var source = try await metadataLookup.lookupDOI(value)
        source.citeKey = ResearchExchange.suggestedCitationKey(for: source, existing: Set(sources.map(\.citeKey)))
        return source
    }

    func lookupISBN(_ value: String) async throws -> ResearchSource {
        isLookingUpMetadata = true
        defer { isLookingUpMetadata = false }
        var source = try await metadataLookup.lookupISBN(value)
        source.citeKey = ResearchExchange.suggestedCitationKey(for: source, existing: Set(sources.map(\.citeKey)))
        return source
    }

    func revealKnowledgeBase() {
        guard let rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([rootURL.appendingPathComponent(ResearchLibraryDisk.knowledgeBaseFileName)])
    }

    func attachmentURL(_ attachment: ResearchAttachment) -> URL? {
        rootURL.map { persistence.attachmentURL(attachment, $0) }
    }

    private func validate(_ source: ResearchSource) throws {
        guard !source.citeKey.isEmpty,
              ResearchExchange.normalizedCitationKey(source.citeKey) == source.citeKey else {
            throw ResearchLibraryError.invalidCitationKey
        }
        if sources.contains(where: { $0.id != source.id && $0.citeKey.caseInsensitiveCompare(source.citeKey) == .orderedSame }) {
            throw ResearchLibraryError.duplicateCitationKey(source.citeKey)
        }
    }

    private func persist(_ updatedSources: [ResearchSource]) throws {
        guard let rootURL else { throw ResearchLibraryError.missingLocation }
        try persistence.save(ResearchLibraryArchive(sources: updatedSources), rootURL)
        sources = updatedSources
    }
}

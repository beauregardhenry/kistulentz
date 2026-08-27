import AppKit
import Foundation

@MainActor
final class ResearchLibraryStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var sources: [ResearchSource] = []
    @Published private(set) var indexingAttachmentIDs: Set<UUID> = []
    @Published private(set) var isLookingUpMetadata = false
    @Published var searchText = ""
    @Published var errorMessage: String?

    private let locationKey = "Kistulentz.researchLibraryLocation"
    private let metadataLookup: ResearchMetadataLookupService

    init(metadataLookup: ResearchMetadataLookupService = ResearchMetadataLookupService()) {
        self.metadataLookup = metadataLookup
        if let path = UserDefaults.standard.string(forKey: locationKey), !path.isEmpty {
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
                ResearchLibraryDisk.loadExtractedText(for: $0, at: rootURL)?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }

    func open(at root: URL, remember: Bool = true) throws {
        let standardized = root.standardizedFileURL
        let archive = try ResearchLibraryDisk.load(from: standardized)
        rootURL = standardized
        sources = archive.sources
        if remember { UserDefaults.standard.set(standardized.path, forKey: locationKey) }
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
        sources.append(source)
        try save()
        return source.id
    }

    func updateSource(_ source: ResearchSource) throws {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { throw ResearchLibraryError.missingSource }
        var updated = source
        updated.citeKey = ResearchExchange.normalizedCitationKey(updated.citeKey)
        updated.modifiedAt = Date()
        try validate(updated)
        sources[index] = updated
        try save()
    }

    func removeSource(_ id: UUID) throws {
        guard let rootURL, let index = sources.firstIndex(where: { $0.id == id }) else { throw ResearchLibraryError.missingSource }
        for attachment in sources[index].attachments { try ResearchLibraryDisk.removeManagedAttachment(attachment, at: rootURL) }
        sources.remove(at: index)
        try save()
    }

    @discardableResult
    func importSources(from url: URL) throws -> Int {
        let imported = try ResearchExchange.importSources(from: url)
        var added = 0
        for var source in imported {
            if let duplicate = ResearchExchange.duplicate(of: source, in: sources),
               let index = sources.firstIndex(where: { $0.id == duplicate.id }) {
                source.id = duplicate.id
                source.citeKey = duplicate.citeKey
                sources[index] = ResearchExchange.merged(existing: duplicate, incoming: source)
            } else {
                if source.citeKey.isEmpty || sources.contains(where: { $0.citeKey.caseInsensitiveCompare(source.citeKey) == .orderedSame }) {
                    source.citeKey = ResearchExchange.suggestedCitationKey(for: source, existing: Set(sources.map(\.citeKey)))
                }
                sources.append(source)
                added += 1
            }
        }
        try save()
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
            var attachment = try ResearchLibraryDisk.addAttachment(from: url, to: sourceID, storage: storage, at: rootURL)
            sources[index].attachments.append(attachment)
            try save()
            indexingAttachmentIDs.insert(attachment.id)
            let attachmentURL = ResearchLibraryDisk.attachmentURL(attachment, at: rootURL)
            do {
                let text = try await Task.detached(priority: .utility) {
                    try ResearchTextExtractor.extract(from: attachmentURL, kind: attachment.kind)
                }.value
                attachment.extractedTextRelativePath = try ResearchLibraryDisk.saveExtractedText(text, for: attachment.id, at: rootURL)
                attachment.extractionStatus = .extracted
                attachment.extractionMessage = "Indexed \(text.count.formatted()) characters locally."
            } catch {
                attachment.extractionStatus = .noReadableText
                attachment.extractionMessage = error.localizedDescription
            }
            if let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }),
               let attachmentIndex = sources[sourceIndex].attachments.firstIndex(where: { $0.id == attachment.id }) {
                sources[sourceIndex].attachments[attachmentIndex] = attachment
                try save()
            }
            indexingAttachmentIDs.remove(attachment.id)
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
        let attachment = sources[sourceIndex].attachments.remove(at: attachmentIndex)
        try ResearchLibraryDisk.removeManagedAttachment(attachment, at: rootURL)
        try save()
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
        rootURL.map { ResearchLibraryDisk.attachmentURL(attachment, at: $0) }
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

    private func save() throws {
        guard let rootURL else { throw ResearchLibraryError.missingLocation }
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: sources), to: rootURL)
    }
}

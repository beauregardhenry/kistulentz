import Foundation

enum DraftRecoveryDisk {
    static func defaultDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Kistulentz", isDirectory: true)
            .appendingPathComponent("Draft Recovery", isDirectory: true)
    }

    static func save(_ entry: DraftRecoveryEntry, in directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: entryURL(entry.id, in: directory), options: .atomic)
    }

    static func loadAll(from directory: URL) -> [DraftRecoveryEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(DraftRecoveryEntry.self, from: data),
                      entry.formatVersion == DraftRecoveryEntry.currentFormatVersion else {
                    return nil
                }
                return entry
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func remove(_ id: UUID, from directory: URL) {
        try? FileManager.default.removeItem(at: entryURL(id, in: directory))
    }

    static func remove(sessionID: UUID, from directory: URL) {
        for entry in loadAll(from: directory) where entry.sessionID == sessionID {
            remove(entry.id, from: directory)
        }
    }

    static func savedText(for entry: DraftRecoveryEntry) -> String? {
        guard let url = entry.originalFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
    }

    static func writeRecoveredText(_ entry: DraftRecoveryEntry, to url: URL) throws {
        guard let data = entry.recoveredText.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func entryURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("draft-\(id.uuidString).json")
    }
}

@MainActor
final class DraftRecoveryManager: ObservableObject {
    static let shared = DraftRecoveryManager()

    @Published private(set) var pendingEntries: [DraftRecoveryEntry]

    let sessionID: UUID
    private let directoryURL: URL
    private let ioQueue = DispatchQueue(label: "Kistulentz.DraftRecovery")
    private var currentEntryIDs: Set<UUID> = []

    init(
        directoryURL: URL = DraftRecoveryDisk.defaultDirectoryURL(),
        sessionID: UUID = UUID()
    ) {
        self.directoryURL = directoryURL
        self.sessionID = sessionID

        var pending: [DraftRecoveryEntry] = []
        for entry in DraftRecoveryDisk.loadAll(from: directoryURL) {
            if let saved = DraftRecoveryDisk.savedText(for: entry), saved == entry.recoveredText {
                DraftRecoveryDisk.remove(entry.id, from: directoryURL)
            } else {
                pending.append(entry)
            }
        }
        pendingEntries = pending
    }

    func record(
        id: UUID,
        title: String,
        fileURL: URL?,
        projectRootURL: URL?,
        text: String
    ) {
        currentEntryIDs.insert(id)
        let entry = DraftRecoveryEntry(
            id: id,
            sessionID: sessionID,
            title: title,
            originalFilePath: fileURL?.standardizedFileURL.path,
            projectRootPath: projectRootURL?.standardizedFileURL.path,
            recoveredText: text
        )
        let directoryURL = self.directoryURL
        ioQueue.async {
            if let saved = DraftRecoveryDisk.savedText(for: entry), saved == entry.recoveredText {
                DraftRecoveryDisk.remove(entry.id, from: directoryURL)
            } else {
                try? DraftRecoveryDisk.save(entry, in: directoryURL)
            }
        }
    }

    func removeCurrentEntries(_ ids: Set<UUID>) {
        currentEntryIDs.subtract(ids)
        let directoryURL = self.directoryURL
        ioQueue.async {
            for id in ids { DraftRecoveryDisk.remove(id, from: directoryURL) }
        }
    }

    func resolve(_ entry: DraftRecoveryEntry) {
        pendingEntries.removeAll { $0.id == entry.id }
        let directoryURL = self.directoryURL
        ioQueue.async { DraftRecoveryDisk.remove(entry.id, from: directoryURL) }
    }

    func endSession() {
        let sessionID = self.sessionID
        ioQueue.sync {
            for entry in DraftRecoveryDisk.loadAll(from: directoryURL)
                where entry.sessionID == sessionID {
                if let saved = DraftRecoveryDisk.savedText(for: entry),
                   saved == entry.recoveredText {
                    DraftRecoveryDisk.remove(entry.id, from: directoryURL)
                }
            }
        }
        currentEntryIDs.removeAll()
    }

    func reloadPendingEntries() {
        pendingEntries = DraftRecoveryDisk.loadAll(from: directoryURL)
            .filter { $0.sessionID != sessionID }
    }
}

@MainActor
final class DraftRecoveryCoordinator: ObservableObject {
    private let manager: DraftRecoveryManager
    private let untitledKey = UUID().uuidString
    private var entryIDsByDocumentKey: [String: UUID] = [:]
    private var recoveryTask: Task<Void, Never>?
    private var title = "Untitled.md"
    private var fileURL: URL?
    private var projectRootURL: URL?
    private var latestText = ""
    private var currentDocumentKey: String?
    private var hasEditingActivity = false

    init(manager: DraftRecoveryManager) {
        self.manager = manager
    }

    convenience init() {
        self.init(manager: .shared)
    }

    func configure(
        title: String,
        fileURL: URL?,
        projectRootURL: URL?,
        text: String
    ) {
        let nextKey = fileURL?.standardizedFileURL.path ?? "untitled:\(untitledKey)"
        if self.fileURL == nil,
           fileURL != nil,
           currentDocumentKey != nextKey,
           let previousKey = currentDocumentKey,
           let previousID = entryIDsByDocumentKey.removeValue(forKey: previousKey),
           let saved = fileURL.flatMap({
               (try? String(contentsOf: $0, encoding: .utf8))
                   ?? (try? String(contentsOf: $0, encoding: .isoLatin1))
           }),
           saved == text {
            manager.removeCurrentEntries([previousID])
        }
        self.title = title
        self.fileURL = fileURL
        self.projectRootURL = projectRootURL
        latestText = text
        currentDocumentKey = nextKey
        hasEditingActivity = false
    }

    func schedule(text: String) {
        latestText = text
        hasEditingActivity = true
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.record(text: text)
        }
    }

    func flush() {
        guard hasEditingActivity else { return }
        recoveryTask?.cancel()
        record(text: latestText)
    }

    func close() {
        recoveryTask?.cancel()
        manager.removeCurrentEntries(Set(entryIDsByDocumentKey.values))
        entryIDsByDocumentKey.removeAll()
    }

    private func record(text: String) {
        let key = currentDocumentKey
            ?? fileURL?.standardizedFileURL.path
            ?? "untitled:\(untitledKey)"
        let id = entryIDsByDocumentKey[key] ?? UUID()
        entryIDsByDocumentKey[key] = id
        manager.record(
            id: id,
            title: title,
            fileURL: fileURL,
            projectRootURL: projectRootURL,
            text: text
        )
    }
}

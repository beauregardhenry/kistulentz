import Foundation

enum KistulentzProjectFormat {
    static let currentVersion = 2
}

enum ProjectBackupReason: String, Codable, Equatable {
    case preMigration
    case knownGood
    case beforeRecovery

    var title: String {
        switch self {
        case .preMigration: "Before migration"
        case .knownGood: "Last known good"
        case .beforeRecovery: "Before recovery"
        }
    }
}

struct ProjectMetadataBackup: Codable, Identifiable, Equatable {
    let directoryName: String
    let createdAt: Date
    let reason: ProjectBackupReason
    let formatVersion: Int

    var id: String { directoryName }
}

struct ProjectMigrationResult: Equatable {
    let fromVersion: Int
    let toVersion: Int
    let backup: ProjectMetadataBackup?

    var didMigrate: Bool { fromVersion != toVersion }
}

struct ProjectRecoveryRequest: Identifiable, Equatable {
    let rootURL: URL
    let failureDescription: String
    let backups: [ProjectMetadataBackup]

    var id: String { rootURL.standardizedFileURL.path }
}

enum ProjectCompatibilityError: LocalizedError, Equatable {
    case corruptMetadata(String)
    case unsupportedProjectVersion(found: Int, supported: Int)
    case missingBackup(String)
    case emptyBackup(String)
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .corruptMetadata(let file):
            "Kistulentz could not read \(file). The project’s Markdown files have not been changed."
        case .unsupportedProjectVersion(let found, let supported):
            "This project uses format \(found), but this Kistulentz release supports through format \(supported). Open it with the newer Kistulentz version that last saved it."
        case .missingBackup(let name):
            "The recovery snapshot \(name) is no longer available."
        case .emptyBackup(let name):
            "The recovery snapshot \(name) does not contain project metadata."
        case .recoveryFailed(let detail):
            "Kistulentz could not restore the project metadata: \(detail)"
        }
    }
}

enum ProjectCompatibilityManager {
    private struct VersionedDocument {
        let relativePath: String
        let versionKey: String
    }

    private static let backupInfoFileName = "backup.json"
    private static let backupPayloadDirectoryName = "metadata"
    private static let backupDirectoryName = ".kistulentz-backups"
    private static let knownGoodLimit = 3

    private static let versionedDocuments = [
        VersionedDocument(relativePath: "project.json", versionKey: "formatVersion"),
        VersionedDocument(relativePath: "outline.json", versionKey: "formatVersion"),
        VersionedDocument(relativePath: "bibliography.json", versionKey: "schemaVersion"),
        VersionedDocument(relativePath: "revisions.json", versionKey: "schemaVersion"),
        VersionedDocument(relativePath: "publication.json", versionKey: "schemaVersion")
    ]

    private static let recoverableJSONPaths = Set(
        versionedDocuments.map(\.relativePath) + [
            "style-decisions.json",
            "manuscript-cache.json",
            "beta-readers.json",
            "history/index.json"
        ]
    )

    static func prepareForOpen(at root: URL) throws -> ProjectMigrationResult {
        let root = root.standardizedFileURL
        let versions = try inspectedVersions(at: root)
        let manifestVersion = versions["project.json"] ?? 0

        for version in versions.values where version > KistulentzProjectFormat.currentVersion {
            throw ProjectCompatibilityError.unsupportedProjectVersion(
                found: version,
                supported: KistulentzProjectFormat.currentVersion
            )
        }

        let needsMigration = versions.values.contains { $0 < KistulentzProjectFormat.currentVersion }
        guard needsMigration else {
            return ProjectMigrationResult(
                fromVersion: manifestVersion,
                toVersion: manifestVersion,
                backup: nil
            )
        }

        let backup = try captureSnapshot(
            at: root,
            reason: .preMigration,
            formatVersion: manifestVersion
        )
        do {
            for document in versionedDocuments {
                let url = metadataURL(for: document.relativePath, at: root)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                try updateVersionField(
                    document.versionKey,
                    to: KistulentzProjectFormat.currentVersion,
                    in: url,
                    displayName: document.relativePath
                )
            }
            _ = try inspectedVersions(at: root)
        } catch {
            try? restoreJSONFiles(from: backup, at: root, removingMissingKnownFiles: false)
            throw error
        }

        return ProjectMigrationResult(
            fromVersion: manifestVersion,
            toVersion: KistulentzProjectFormat.currentVersion,
            backup: backup
        )
    }

    @discardableResult
    static func captureKnownGoodSnapshot(at root: URL) throws -> ProjectMetadataBackup {
        let version = (try? inspectedVersions(at: root)["project.json"])
            ?? KistulentzProjectFormat.currentVersion
        let backup = try captureSnapshot(at: root, reason: .knownGood, formatVersion: version)
        try pruneKnownGoodSnapshots(at: root)
        return backup
    }

    static func availableBackups(at root: URL) throws -> [ProjectMetadataBackup] {
        let directory = backupsURL(at: root)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            try? loadBackupInfo(from: url)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    static func restore(_ backup: ProjectMetadataBackup, at root: URL) throws {
        let root = root.standardizedFileURL
        let backupDirectory = backupsURL(at: root).appendingPathComponent(backup.directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: backupDirectory.path) else {
            throw ProjectCompatibilityError.missingBackup(backup.directoryName)
        }

        let currentVersion = (try? inspectedVersions(at: root)["project.json"]) ?? 0
        _ = try captureSnapshot(at: root, reason: .beforeRecovery, formatVersion: currentVersion)
        do {
            try restoreJSONFiles(from: backup, at: root, removingMissingKnownFiles: true)
        } catch let error as ProjectCompatibilityError {
            throw error
        } catch {
            throw ProjectCompatibilityError.recoveryFailed(error.localizedDescription)
        }
    }

    static func backupsURL(at root: URL) -> URL {
        root.standardizedFileURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }

    private static func inspectedVersions(at root: URL) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for document in versionedDocuments {
            let url = metadataURL(for: document.relativePath, at: root)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let object = try jsonObject(at: url, displayName: document.relativePath)
            result[document.relativePath] = object[document.versionKey] as? Int ?? 0
        }
        return result
    }

    private static func updateVersionField(
        _ key: String,
        to version: Int,
        in url: URL,
        displayName: String
    ) throws {
        var object = try jsonObject(at: url, displayName: displayName)
        object[key] = version
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProjectCompatibilityError.corruptMetadata(displayName)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func jsonObject(at url: URL, displayName: String) throws -> [String: Any] {
        do {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let object = value as? [String: Any] else {
                throw ProjectCompatibilityError.corruptMetadata(displayName)
            }
            return object
        } catch let error as ProjectCompatibilityError {
            throw error
        } catch {
            throw ProjectCompatibilityError.corruptMetadata(displayName)
        }
    }

    private static func captureSnapshot(
        at root: URL,
        reason: ProjectBackupReason,
        formatVersion: Int,
        now: Date = Date()
    ) throws -> ProjectMetadataBackup {
        let manager = FileManager.default
        let backupRoot = backupsURL(at: root)
        try manager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let timestamp = backupTimestamp(now)
        let directoryName = "\(reason.rawValue)-\(timestamp)-\(UUID().uuidString.prefix(8))"
        let directory = backupRoot.appendingPathComponent(directoryName, isDirectory: true)
        let payload = directory.appendingPathComponent(backupPayloadDirectoryName, isDirectory: true)
        try manager.createDirectory(at: payload, withIntermediateDirectories: true)

        do {
            let metadata = WritingProjectDisk.metadataURL(at: root)
            for source in try metadataJSONFiles(at: metadata) {
                let relativePath = relativePath(of: source, within: metadata)
                let destination = payload.appendingPathComponent(relativePath)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: destination)
            }

            let backup = ProjectMetadataBackup(
                directoryName: directoryName,
                createdAt: now,
                reason: reason,
                formatVersion: formatVersion
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(backup).write(
                to: directory.appendingPathComponent(backupInfoFileName),
                options: .atomic
            )
            return backup
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private static func restoreJSONFiles(
        from backup: ProjectMetadataBackup,
        at root: URL,
        removingMissingKnownFiles: Bool
    ) throws {
        let manager = FileManager.default
        let backupDirectory = backupsURL(at: root).appendingPathComponent(backup.directoryName, isDirectory: true)
        let payload = backupDirectory.appendingPathComponent(backupPayloadDirectoryName, isDirectory: true)
        let sources = try metadataJSONFiles(at: payload)
        guard !sources.isEmpty else { throw ProjectCompatibilityError.emptyBackup(backup.directoryName) }

        let destinationRoot = WritingProjectDisk.metadataURL(at: root)
        try manager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let pathsInBackup = Set(sources.map { relativePath(of: $0, within: payload) })

        if removingMissingKnownFiles {
            for relativePath in recoverableJSONPaths where !pathsInBackup.contains(relativePath) {
                let destination = destinationRoot.appendingPathComponent(relativePath)
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            }
        }

        for source in sources {
            let relativePath = relativePath(of: source, within: payload)
            let destination = destinationRoot.appendingPathComponent(relativePath)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
        }
    }

    private static func metadataJSONFiles(at root: URL) throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true, url.pathExtension.lowercased() == "json" {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private static func loadBackupInfo(from directory: URL) throws -> ProjectMetadataBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ProjectMetadataBackup.self,
            from: Data(contentsOf: directory.appendingPathComponent(backupInfoFileName))
        )
    }

    private static func pruneKnownGoodSnapshots(at root: URL) throws {
        let snapshots = try availableBackups(at: root).filter { $0.reason == .knownGood }
        for backup in snapshots.dropFirst(knownGoodLimit) {
            let url = backupsURL(at: root).appendingPathComponent(backup.directoryName, isDirectory: true)
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func metadataURL(for relativePath: String, at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(relativePath)
    }

    private static func relativePath(of url: URL, within root: URL) -> String {
        let rootPath = root.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private static func backupTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

import Foundation

enum AtomicFileWriteError: LocalizedError, Equatable {
    case unsafeDestination
    case commitFailedAndCleanupIncomplete(commitReason: String, cleanupReason: String)

    var errorDescription: String? {
        switch self {
        case .unsafeDestination:
            "Kistulentz refused to replace a folder, symbolic link, or unsafe file destination."
        case .commitFailedAndCleanupIncomplete(let commitReason, let cleanupReason):
            "The write could not be committed (\(commitReason)), and its temporary file could not be removed (\(cleanupReason))."
        }
    }
}

/// Stages a complete file beside its destination, then commits it with one filesystem operation.
/// A stage failure (including a full disk) cannot touch the current file. A commit failure keeps
/// the current file and removes the staged copy, reporting separately if cleanup also fails.
struct AtomicFileWriter {
    struct Operations: @unchecked Sendable {
        var fileExists: (URL) -> Bool
        var stage: (Data, URL) throws -> Void
        var commit: (URL, URL, Bool) throws -> Void
        var remove: (URL) throws -> Void

        static let live = Operations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            stage: { data, url in try data.write(to: url, options: .atomic) },
            commit: { staged, destination, destinationExists in
                if destinationExists {
                    _ = try FileManager.default.replaceItemAt(
                        destination,
                        withItemAt: staged,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try FileManager.default.moveItem(at: staged, to: destination)
                }
            },
            remove: { try FileManager.default.removeItem(at: $0) }
        )
    }

    private let operations: Operations

    init(operations: Operations = .live) {
        self.operations = operations
    }

    static func write(data: Data, to destination: URL) throws {
        try AtomicFileWriter().write(data: data, to: destination)
    }

    static func write(
        text: String,
        to destination: URL,
        encoding: String.Encoding = .utf8
    ) throws {
        guard let data = text.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try write(data: data, to: destination)
    }

    func write(data: Data, to destination: URL) throws {
        try validateDestination(destination)
        let staged = destination.deletingLastPathComponent().appendingPathComponent(
            ".Kistulentz-write-\(UUID().uuidString)",
            isDirectory: false
        )
        let destinationExists = operations.fileExists(destination)

        do {
            try operations.stage(data, staged)
            try operations.commit(staged, destination, destinationExists)
        } catch {
            guard operations.fileExists(staged) else { throw error }
            do {
                try operations.remove(staged)
            } catch let cleanupError {
                throw AtomicFileWriteError.commitFailedAndCleanupIncomplete(
                    commitReason: error.localizedDescription,
                    cleanupReason: cleanupError.localizedDescription
                )
            }
            throw error
        }
    }

    private func validateDestination(_ destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw AtomicFileWriteError.unsafeDestination
        }

        guard operations.fileExists(destination) else { return }
        let values = try destination.resourceValues(
            forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true else {
            throw AtomicFileWriteError.unsafeDestination
        }
    }
}

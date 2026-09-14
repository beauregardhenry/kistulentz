import Foundation

struct ArchiveSafetyPolicy: Equatable, Sendable {
    let maximumArchiveBytes: UInt64
    let maximumEntries: Int
    let maximumEntryBytes: Int64
    let maximumExtractedBytes: Int64
    let maximumCompressionRatio: Double
    let maximumPathBytes: Int

    static let documentImport = ArchiveSafetyPolicy(
        maximumArchiveBytes: 250_000_000,
        maximumEntries: 25_000,
        maximumEntryBytes: 50_000_000,
        maximumExtractedBytes: 600_000_000,
        maximumCompressionRatio: 1_000,
        maximumPathBytes: 1_024
    )

    static let epub = ArchiveSafetyPolicy(
        maximumArchiveBytes: 250_000_000,
        maximumEntries: 25_000,
        maximumEntryBytes: 40_000_000,
        maximumExtractedBytes: 600_000_000,
        maximumCompressionRatio: 1_000,
        maximumPathBytes: 1_024
    )
}

struct SafeArchiveEntry: Equatable, Sendable {
    let path: String
    let uncompressedBytes: Int64
    let compressedBytes: Int64
    let isDirectory: Bool
}

struct SafeArchiveInspection: Equatable, Sendable {
    let entries: [SafeArchiveEntry]

    var paths: Set<String> { Set(entries.map(\.path)) }

    func entry(named path: String) -> SafeArchiveEntry? {
        entries.first { $0.path == path }
    }
}

enum ArchiveSafetyError: LocalizedError, Equatable {
    case unavailable
    case archiveTooLarge
    case entryTooLarge
    case unsafeArchive
    case extractionFailed(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Kistulentz could not access the archive tools on this Mac."
        case .archiveTooLarge:
            "The archive expands beyond Kistulentz's safe import limit."
        case .entryTooLarge:
            "The archive contains an individual file that is too large to import safely."
        case .unsafeArchive:
            "The archive contains unsafe paths, links, collisions, or unusual compression."
        case .extractionFailed(let detail):
            detail ?? "The archive could not be read."
        }
    }
}

enum SafeArchiveReader {
    private static let maximumListingOutputBytes = 32_000_000
    private static let maximumDiagnosticOutputBytes = 1_000_000

    static func inspect(
        _ url: URL,
        policy: ArchiveSafetyPolicy
    ) throws -> SafeArchiveInspection {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let archiveBytes = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard archiveBytes > 0, archiveBytes <= policy.maximumArchiveBytes else {
            throw ArchiveSafetyError.archiveTooLarge
        }

        let pathData = try runUnzip(
            arguments: ["-Z1", url.path],
            maximumOutputBytes: maximumListingOutputBytes
        )
        guard let pathListing = String(data: pathData, encoding: .utf8) else {
            throw ArchiveSafetyError.unsafeArchive
        }
        let paths = pathListing.split(whereSeparator: \.isNewline).map(String.init)
        guard !paths.isEmpty, paths.count <= policy.maximumEntries else {
            throw ArchiveSafetyError.unsafeArchive
        }

        var collisionKeys: Set<String> = []
        for path in paths {
            try validate(path: path, policy: policy)
            let collisionKey = path.precomposedStringWithCanonicalMapping.lowercased()
            guard collisionKeys.insert(collisionKey).inserted else {
                throw ArchiveSafetyError.unsafeArchive
            }
        }

        let metadataData = try runUnzip(
            arguments: ["-Z", "-l", url.path],
            maximumOutputBytes: maximumListingOutputBytes
        )
        guard let metadataListing = String(data: metadataData, encoding: .utf8) else {
            throw ArchiveSafetyError.unsafeArchive
        }
        let metadata = try parseMetadata(metadataListing, policy: policy)
        guard metadata.count == paths.count else {
            throw ArchiveSafetyError.unsafeArchive
        }

        var totalBytes: Int64 = 0
        var entries: [SafeArchiveEntry] = []
        entries.reserveCapacity(paths.count)
        for (path, row) in zip(paths, metadata) {
            guard row.kind == "-" || row.kind == "d" else {
                throw ArchiveSafetyError.unsafeArchive
            }
            guard row.uncompressedBytes >= 0, row.compressedBytes >= 0 else {
                throw ArchiveSafetyError.unsafeArchive
            }
            if row.kind == "-" {
                guard row.uncompressedBytes <= policy.maximumEntryBytes else {
                    throw ArchiveSafetyError.entryTooLarge
                }
                let (newTotal, overflow) = totalBytes.addingReportingOverflow(row.uncompressedBytes)
                guard !overflow, newTotal <= policy.maximumExtractedBytes else {
                    throw ArchiveSafetyError.archiveTooLarge
                }
                totalBytes = newTotal

                if row.uncompressedBytes > 0 {
                    guard row.compressedBytes > 0 else {
                        throw ArchiveSafetyError.unsafeArchive
                    }
                    let ratio = Double(row.uncompressedBytes) / Double(row.compressedBytes)
                    guard ratio <= policy.maximumCompressionRatio else {
                        throw ArchiveSafetyError.unsafeArchive
                    }
                }
            }
            entries.append(SafeArchiveEntry(
                path: path,
                uncompressedBytes: row.uncompressedBytes,
                compressedBytes: row.compressedBytes,
                isDirectory: row.kind == "d"
            ))
        }
        return SafeArchiveInspection(entries: entries)
    }

    static func data(
        for entry: String,
        in url: URL,
        inspection: SafeArchiveInspection,
        required: Bool = true
    ) throws -> Data? {
        guard let metadata = inspection.entry(named: entry), !metadata.isDirectory else {
            if required { throw ArchiveSafetyError.unsafeArchive }
            return nil
        }
        guard metadata.uncompressedBytes <= Int64(Int.max) else {
            throw ArchiveSafetyError.entryTooLarge
        }
        return try runUnzip(
            arguments: ["-p", url.path, entry],
            maximumOutputBytes: Int(metadata.uncompressedBytes)
        )
    }

    static func extract(
        _ url: URL,
        to destination: URL,
        inspection: SafeArchiveInspection,
        policy: ArchiveSafetyPolicy
    ) throws {
        _ = try runUnzip(
            arguments: ["-qq", "-o", url.path, "-d", destination.path],
            maximumOutputBytes: maximumDiagnosticOutputBytes
        )
        try validateExtractedContents(
            at: destination,
            expectedEntries: inspection.entries.count,
            policy: policy
        )
    }

    private struct MetadataRow {
        let kind: Character
        let uncompressedBytes: Int64
        let compressedBytes: Int64
    }

    private static func parseMetadata(
        _ listing: String,
        policy: ArchiveSafetyPolicy
    ) throws -> [MetadataRow] {
        var rows: [MetadataRow] = []
        rows.reserveCapacity(min(policy.maximumEntries, 1_024))
        for line in listing.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let marker = fields.first?.first, marker == "-" || marker == "d" || marker == "l" else {
                continue
            }
            guard fields.count >= 6,
                  let uncompressedBytes = Int64(fields[3]),
                  let compressedBytes = Int64(fields[5]) else {
                throw ArchiveSafetyError.unsafeArchive
            }
            rows.append(MetadataRow(
                kind: marker,
                uncompressedBytes: uncompressedBytes,
                compressedBytes: compressedBytes
            ))
            guard rows.count <= policy.maximumEntries else {
                throw ArchiveSafetyError.unsafeArchive
            }
        }
        return rows
    }

    private static func validate(path: String, policy: ArchiveSafetyPolicy) throws {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        let hasUnexpectedEmptyComponent = components.dropLast().contains(where: \.isEmpty)
        let containsControlCharacter = path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !path.isEmpty,
              path == normalized,
              path.utf8.count <= policy.maximumPathBytes,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !hasUnexpectedEmptyComponent,
              !containsControlCharacter,
              !components.contains("."),
              !components.contains("..") else {
            throw ArchiveSafetyError.unsafeArchive
        }
    }

    private static func validateExtractedContents(
        at root: URL,
        expectedEntries: Int,
        policy: ArchiveSafetyPolicy
    ) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            throw ArchiveSafetyError.unsafeArchive
        }

        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        // Archive tools may create parent directories that were not explicit ZIP entries. Allow
        // one directory for every inspected entry while keeping a hard post-extraction ceiling.
        let (doubledEntryLimit, overflow) = expectedEntries.multipliedReportingOverflow(by: 2)
        let extractedItemLimit = min(
            policy.maximumEntries,
            overflow ? policy.maximumEntries : max(expectedEntries, doubledEntryLimit)
        )
        var count = 0
        var totalBytes: Int64 = 0
        for case let itemURL as URL in enumerator {
            count += 1
            guard count <= extractedItemLimit else {
                throw ArchiveSafetyError.unsafeArchive
            }
            let values = try itemURL.resourceValues(
                forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw ArchiveSafetyError.unsafeArchive
            }
            let canonicalPath = itemURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard canonicalPath.hasPrefix(canonicalRoot) else {
                throw ArchiveSafetyError.unsafeArchive
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size <= policy.maximumEntryBytes else {
                    throw ArchiveSafetyError.entryTooLarge
                }
                let (newTotal, overflow) = totalBytes.addingReportingOverflow(size)
                guard !overflow, newTotal <= policy.maximumExtractedBytes else {
                    throw ArchiveSafetyError.archiveTooLarge
                }
                totalBytes = newTotal
            } else if values.isDirectory != true {
                throw ArchiveSafetyError.unsafeArchive
            }
        }
    }

    private static func runUnzip(
        arguments: [String],
        maximumOutputBytes: Int
    ) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw ArchiveSafetyError.unavailable
        }

        var output = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 64 * 1_024)
            guard !chunk.isEmpty else { break }
            guard output.count <= maximumOutputBytes - min(chunk.count, maximumOutputBytes) else {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveSafetyError.entryTooLarge
            }
            output.append(chunk)
            guard output.count <= maximumOutputBytes else {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveSafetyError.entryTooLarge
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveSafetyError.extractionFailed(detail?.isEmpty == false ? detail : nil)
        }
        return output
    }
}

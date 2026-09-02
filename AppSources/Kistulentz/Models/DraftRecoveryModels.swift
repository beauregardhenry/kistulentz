import Foundation

struct DraftRecoveryEntry: Codable, Identifiable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let id: UUID
    let sessionID: UUID
    let title: String
    let originalFilePath: String?
    let projectRootPath: String?
    let recoveredText: String
    let updatedAt: Date

    init(
        id: UUID,
        sessionID: UUID,
        title: String,
        originalFilePath: String?,
        projectRootPath: String?,
        recoveredText: String,
        updatedAt: Date = Date()
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.originalFilePath = originalFilePath
        self.projectRootPath = projectRootPath
        self.recoveredText = recoveredText
        self.updatedAt = updatedAt
    }

    var originalFileURL: URL? {
        originalFilePath.map { URL(fileURLWithPath: $0) }
    }

    var suggestedCopyName: String {
        let source = originalFileURL?.deletingPathExtension().lastPathComponent
            ?? title.replacingOccurrences(of: ".md", with: "")
        return "\(source.isEmpty ? "Recovered Draft" : source) Recovered.md"
    }
}

enum KistulentzScaleTargets {
    static let manuscriptWords = 2_000_000
    static let projectDocuments = 2_000
    static let projectImportFiles = 1_000
    static let referenceBooks = 5_000
}

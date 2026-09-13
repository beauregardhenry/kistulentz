import Foundation

/// One font file the user has added through Settings. `familyName` is read from the font file
/// itself (via Core Text) at add time, not typed by the user, so it always matches what
/// `NSFontManager`/`CTFontManager` will actually resolve once the file is registered.
struct CustomFontRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let familyName: String
    let originalFilename: String
    let storedFilename: String
    let addedAt: Date

    init(
        id: UUID = UUID(),
        familyName: String,
        originalFilename: String,
        storedFilename: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.familyName = familyName
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.addedAt = addedAt
    }
}

struct CustomFontManifest: Codable, Equatable {
    var schemaVersion = 1
    var fonts: [CustomFontRecord] = []
}

enum CustomFontError: LocalizedError, Equatable {
    case unreadableFile(String)
    case invalidFontFile(String)
    case registrationFailed(String)
    case addFailedAndRollbackIncomplete(originalReason: String, rollbackReason: String)
    case missingFont

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            "Kistulentz could not read \(name)."
        case .invalidFontFile(let name):
            "\(name) does not appear to be a valid font file."
        case .registrationFailed(let reason):
            "Kistulentz could not register that font: \(reason)"
        case .addFailedAndRollbackIncomplete(let originalReason, let rollbackReason):
            "Adding that font failed (\(originalReason)), and Kistulentz could not clean up the partial attempt (\(rollbackReason)). Check Settings' custom font list before trying again."
        case .missingFont:
            "That font is no longer in the list."
        }
    }
}

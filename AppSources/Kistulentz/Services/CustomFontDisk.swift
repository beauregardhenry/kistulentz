import AppKit
import CoreText
import Foundation

/// Persists user-added font files under Application Support and registers them with Core Text --
/// `.persistent` scope by default, the same scope a real Font Book install uses, so a font added
/// here behaves like any other installed font everywhere else in the app (the editor's font
/// picker and the publication layout's body/heading font fields both resolve fonts by family name
/// through `NSFontManager`/`CTFontManager`, which don't distinguish how a font got registered).
///
/// `scope` is an injectable parameter, not hardcoded to `.persistent`, specifically so tests can
/// pass `.process` instead: `.persistent` registration is a real, system-wide change visible to
/// every other app and Font Book, and a test suite must never leave that behind on whichever Mac
/// happens to run it (a developer's machine or a CI runner). `.process` registers only for the
/// current run and disappears when it exits, so tests can exercise real Core Text registration
/// without leaving anything behind.
///
/// Font files are copied into Kistulentz's own managed folder before registering, rather than
/// registering directly from wherever the user picked the file -- `.persistent` registration
/// re-references its source file on future launches, so relying on a file the user could later
/// move, rename, or delete would make the registration fragile in a way that's invisible until it
/// silently stops working.
enum CustomFontDisk {
    private static let manifestFileName = "manifest.json"
    private static let filesDirectoryName = "Files"

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("Kistulentz", isDirectory: true)
            .appendingPathComponent("CustomFonts", isDirectory: true)
    }

    static func loadManifest(at root: URL) throws -> CustomFontManifest {
        let url = root.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return CustomFontManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomFontManifest.self, from: Data(contentsOf: url))
    }

    static func saveManifest(_ manifest: CustomFontManifest, at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: root.appendingPathComponent(manifestFileName), options: .atomic)
    }

    /// Copies `sourceURL` into managed storage and registers it. Rolls the copy and registration
    /// back if the manifest write that would make it durable fails, escalating through
    /// `RollbackTracker` if that rollback can't fully complete either. Adding a font whose family
    /// name matches one already on the list returns the existing record instead of creating a
    /// redundant second copy.
    static func addFont(
        from sourceURL: URL,
        at root: URL,
        scope: CTFontManagerScope = .persistent
    ) throws -> CustomFontRecord {
        let standardized = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            throw CustomFontError.unreadableFile(sourceURL.lastPathComponent)
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(standardized as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String,
              !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CustomFontError.invalidFontFile(sourceURL.lastPathComponent)
        }

        var manifest = try loadManifest(at: root)
        if let existing = manifest.fonts.first(where: { $0.familyName.caseInsensitiveCompare(familyName) == .orderedSame }) {
            return existing
        }

        let filesDirectory = root.appendingPathComponent(filesDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let storedFilename = "\(id.uuidString)-\(DocumentImportFilename.safe(standardized.lastPathComponent))"
        let destination = filesDirectory.appendingPathComponent(storedFilename)
        try FileManager.default.copyItem(at: standardized, to: destination)

        var registerError: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(destination as CFURL, scope, &registerError) else {
            try? FileManager.default.removeItem(at: destination)
            let description = registerError?.takeRetainedValue().localizedDescription ?? "an unknown error"
            throw CustomFontError.registrationFailed(description)
        }

        let record = CustomFontRecord(
            id: id,
            familyName: familyName,
            originalFilename: standardized.lastPathComponent,
            storedFilename: storedFilename
        )
        manifest.fonts.append(record)
        do {
            try saveManifest(manifest, at: root)
        } catch {
            try RollbackTracker.run(
                after: error,
                steps: [("removing the added font", {
                    var unregisterError: Unmanaged<CFError>?
                    _ = CTFontManagerUnregisterFontsForURL(destination as CFURL, scope, &unregisterError)
                    try FileManager.default.removeItem(at: destination)
                })]
            ) { originalReason, rollbackReason in
                CustomFontError.addFailedAndRollbackIncomplete(originalReason: originalReason, rollbackReason: rollbackReason)
            }
        }
        return record
    }

    /// Unregisters and deletes a previously-added font. Best-effort on unregistration -- the user
    /// asked to remove it, so a font that's already gone from Core Text (removed some other way)
    /// shouldn't block removing Kistulentz's own record of it.
    static func removeFont(
        _ record: CustomFontRecord,
        at root: URL,
        scope: CTFontManagerScope = .persistent
    ) throws {
        var manifest = try loadManifest(at: root)
        guard let index = manifest.fonts.firstIndex(where: { $0.id == record.id }) else {
            throw CustomFontError.missingFont
        }
        let fileURL = root.appendingPathComponent(filesDirectoryName).appendingPathComponent(record.storedFilename)
        var unregisterError: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(fileURL as CFURL, scope, &unregisterError)
        try? FileManager.default.removeItem(at: fileURL)
        manifest.fonts.remove(at: index)
        try saveManifest(manifest, at: root)
    }

    /// Re-registers every known font that isn't already available. `.persistent` registration is
    /// meant to survive across launches on its own, but re-asserting it defensively on every
    /// launch is cheap and catches the rare case where the OS-level registration and Kistulentz's
    /// own manifest have drifted apart (a restored backup, a font cache reset). Checking
    /// `NSFontManager`'s live family list first, rather than just calling register again and
    /// inspecting the result, sidesteps needing to distinguish Core Text's "already registered"
    /// error from a real failure.
    @discardableResult
    static func registerAll(
        at root: URL,
        scope: CTFontManagerScope = .persistent
    ) -> [(record: CustomFontRecord, failureReason: String?)] {
        guard let manifest = try? loadManifest(at: root) else { return [] }
        let filesDirectory = root.appendingPathComponent(filesDirectoryName, isDirectory: true)
        let alreadyAvailable = Set(NSFontManager.shared.availableFontFamilies)
        return manifest.fonts.map { record in
            guard !alreadyAvailable.contains(record.familyName) else { return (record, nil) }
            let fileURL = filesDirectory.appendingPathComponent(record.storedFilename)
            var registerError: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(fileURL as CFURL, scope, &registerError)
            let failureReason = success ? nil : (registerError?.takeRetainedValue().localizedDescription ?? "an unknown error")
            return (record, failureReason)
        }
    }
}

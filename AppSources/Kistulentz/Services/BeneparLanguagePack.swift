import CryptoKit
import Foundation

enum BeneparLanguagePackLocator {
    static let identifier = "english-benepar"
    static let schemaVersion = 1

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("Kistulentz", isDirectory: true)
            .appendingPathComponent("LanguagePacks", isDirectory: true)
            .appendingPathComponent("English", isDirectory: true)
    }

    static func locate(
        at rootURL: URL = defaultRootURL(),
        fileManager: FileManager = .default
    ) throws -> BeneparLanguagePackInstallation? {
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest: BeneparLanguagePackManifest
        do {
            manifest = try JSONDecoder().decode(
                BeneparLanguagePackManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw BeneparLanguagePackError.invalidManifest("manifest.json could not be read")
        }
        guard manifest.schemaVersion == schemaVersion else {
            throw BeneparLanguagePackError.invalidManifest("unsupported manifest version")
        }
        guard manifest.identifier == identifier else {
            throw BeneparLanguagePackError.invalidManifest("unexpected pack identifier")
        }
        guard manifest.architecture == architecture else {
            throw BeneparLanguagePackError.invalidManifest(
                "built for \(manifest.architecture), not \(architecture)"
            )
        }

        let pythonURL = try safeURL(relativePath: manifest.pythonRelativePath, root: rootURL)
        let modelURL = try safeURL(relativePath: manifest.modelRelativePath, root: rootURL)
        var isDirectory: ObjCBool = false
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            throw BeneparLanguagePackError.invalidManifest("the Python runtime is missing")
        }
        guard fileManager.fileExists(atPath: modelURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BeneparLanguagePackError.invalidManifest("the benepar_en3 model is missing")
        }
        return BeneparLanguagePackInstallation(
            rootURL: rootURL,
            pythonURL: pythonURL,
            modelURL: modelURL,
            manifest: manifest
        )
    }

    private static func safeURL(relativePath: String, root: URL) throws -> URL {
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !components.contains("..") else {
            throw BeneparLanguagePackError.invalidManifest("an unsafe internal path was rejected")
        }
        let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = standardizedRoot
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(standardizedRoot.path + "/") else {
            throw BeneparLanguagePackError.invalidManifest("an internal path leaves the pack folder")
        }
        return candidate
    }
}

@MainActor
final class BeneparLanguagePackManager: ObservableObject {
    nonisolated static let catalogURL = URL(
        string: "https://github.com/beauregardhenry/kistulentz/releases/download/language-pack-en-v1/catalog.json"
    )!

    @Published private(set) var state: BeneparLanguagePackState = .notInstalled
    @Published private(set) var isInstalling = false
    @Published private(set) var activityMessage = ""
    @Published var errorMessage: String?

    private let rootURL: URL
    private let catalogURL: URL
    private let fileManager: FileManager
    private let session: URLSession

    init(
        rootURL: URL = BeneparLanguagePackLocator.defaultRootURL(),
        catalogURL: URL = BeneparLanguagePackManager.catalogURL,
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.rootURL = rootURL
        self.catalogURL = catalogURL
        self.fileManager = fileManager
        self.session = session
        refresh()
    }

    var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    func refresh() {
        do {
            if let installation = try BeneparLanguagePackLocator.locate(at: rootURL, fileManager: fileManager) {
                state = .installed(
                    version: installation.manifest.version,
                    installedBytes: installation.manifest.installedBytes
                )
            } else {
                state = .notInstalled
            }
        } catch {
            state = .invalid(reason: error.localizedDescription)
        }
    }

    func install() async {
        guard !isInstalling else { return }
        isInstalling = true
        errorMessage = nil
        activityMessage = "Checking the English language pack…"
        do {
            let (catalogData, response) = try await session.data(from: catalogURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BeneparLanguagePackError.catalogUnavailable
            }
            guard let catalog = try? JSONDecoder().decode(BeneparLanguagePackCatalog.self, from: catalogData) else {
                throw BeneparLanguagePackError.unsupportedCatalog
            }
            guard catalog.schemaVersion == 1 else { throw BeneparLanguagePackError.unsupportedCatalog }
            guard let entry = catalog.packs.first(where: {
                $0.architecture == BeneparLanguagePackLocator.architecture
            }) else {
                throw BeneparLanguagePackError.architectureUnavailable(BeneparLanguagePackLocator.architecture)
            }
            let isSHA256 = entry.sha256.count == 64 && entry.sha256.allSatisfy { $0.isHexDigit }
            guard entry.downloadURL.scheme?.lowercased() == "https",
                  entry.downloadBytes > 0,
                  entry.installedBytes > 0,
                  isSHA256 else {
                throw BeneparLanguagePackError.invalidCatalog
            }

            activityMessage = "Downloading the English structural-analysis pack…"
            let (downloadedURL, downloadResponse) = try await session.download(from: entry.downloadURL)
            guard let http = downloadResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BeneparLanguagePackError.catalogUnavailable
            }
            let downloadedBytes = try downloadedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard downloadedBytes.map(Int64.init) == entry.downloadBytes else {
                throw BeneparLanguagePackError.unexpectedDownloadSize
            }
            activityMessage = "Verifying the SHA-256 checksum…"
            let checksum = try await Task.detached(priority: .userInitiated) {
                try Self.sha256(of: downloadedURL)
            }.value
            guard checksum == entry.sha256.lowercased() else {
                throw BeneparLanguagePackError.invalidChecksum
            }

            activityMessage = "Installing locally…"
            let installRootURL = rootURL
            try await Task.detached(priority: .userInitiated) {
                try Self.installArchive(
                    downloadedURL,
                    expected: entry,
                    at: installRootURL,
                    fileManager: FileManager()
                )
            }.value
            await BeneparService.shared.reset()
            refresh()
            activityMessage = "English structural analysis is ready."
        } catch is CancellationError {
            refresh()
            activityMessage = "English language-pack installation cancelled."
        } catch let error as URLError where error.code == .cancelled {
            refresh()
            activityMessage = "English language-pack installation cancelled."
        } catch {
            errorMessage = error.localizedDescription
            refresh()
            activityMessage = ""
        }
        isInstalling = false
    }

    func remove() async {
        do {
            await BeneparService.shared.reset()
            let removalRootURL = rootURL
            try await Task.detached(priority: .userInitiated) {
                let manager = FileManager()
                if manager.fileExists(atPath: removalRootURL.path) {
                    try manager.removeItem(at: removalRootURL)
                }
            }.value
            state = .notInstalled
            activityMessage = "English language pack removed. Native analysis remains active."
        } catch {
            errorMessage = "The English language pack could not be removed: \(error.localizedDescription)"
        }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func installArchive(
        _ archiveURL: URL,
        expected entry: BeneparLanguagePackCatalogEntry,
        at rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = rootURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".English-install-\(UUID().uuidString)", isDirectory: true)
        let backup = parent.appendingPathComponent(".English-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", "--noqtn", archiveURL.path, staging.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BeneparLanguagePackError.invalidArchive
        }

        let candidate: URL
        if fileManager.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) {
            candidate = staging
        } else {
            let children = try fileManager.contentsOfDirectory(
                at: staging,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            guard children.count == 1,
                  fileManager.fileExists(atPath: children[0].appendingPathComponent("manifest.json").path) else {
                throw BeneparLanguagePackError.invalidArchive
            }
            candidate = children[0]
        }

        let installation = try BeneparLanguagePackLocator.locate(at: candidate, fileManager: fileManager)
        guard let installation,
              installation.manifest.version == entry.version,
              installation.manifest.architecture == entry.architecture,
              installation.manifest.installedBytes == entry.installedBytes else {
            throw BeneparLanguagePackError.invalidManifest("the archive does not match the catalog")
        }

        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.moveItem(at: rootURL, to: backup)
        }
        do {
            try fileManager.moveItem(at: candidate, to: rootURL)
        } catch {
            if fileManager.fileExists(atPath: backup.path), !fileManager.fileExists(atPath: rootURL.path) {
                try? fileManager.moveItem(at: backup, to: rootURL)
            }
            throw error
        }
    }
}

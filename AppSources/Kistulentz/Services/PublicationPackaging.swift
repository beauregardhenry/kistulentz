import Foundation

enum PublicationArchiveUtility {
    static func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func zip(directory: URL, to outputURL: URL, epub: Bool = false) throws {
        if epub {
            try runZip(arguments: ["-X0", outputURL.path, "mimetype"], in: directory)
            var entries: [String] = []
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("META-INF").path) { entries.append("META-INF") }
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("EPUB").path) { entries.append("EPUB") }
            try runZip(arguments: ["-Xr9", outputURL.path] + entries, in: directory)
        } else {
            let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            try runZip(arguments: ["-Xr9", outputURL.path] + entries, in: directory)
        }
    }

    private static func runZip(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PublicationExportError.archiveCreationFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PublicationExportError.archiveCreationFailed(message?.isEmpty == false ? message! : "The system ZIP utility failed.")
        }
    }
}

enum PublicationMediaType {
    static func epub(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        default: nil
        }
    }

    static func docx(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "tif", "tiff": "image/tiff"
        case "bmp": "image/bmp"
        default: nil
        }
    }
}

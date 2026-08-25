import AppKit
import Foundation
import NaturalLanguage

struct EPUBProcessor {
    private static let maximumArchiveBytes: UInt64 = 250_000_000
    private static let maximumExtractedBytes: Int64 = 600_000_000
    private static let maximumEntries = 25_000
    private static let maximumAnalyzedCharacters = 2_500_000
    private static let maximumContainerBytes = 2_000_000
    private static let maximumPackageBytes = 10_000_000
    private static let maximumContentItemBytes = 40_000_000

    static func load(url: URL) throws -> EPUBReference {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let archiveSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard archiveSize > 0, archiveSize <= maximumArchiveBytes else {
            throw EPUBError.archiveTooLarge
        }

        let listingData = try runUnzip(arguments: ["-Z1", url.path])
        let entries = try validateArchiveListing(listingData)
        try validateArchiveMetadata(try runUnzip(arguments: ["-Z", "-l", url.path]))
        guard entries.contains(where: { $0.caseInsensitiveCompare("META-INF/container.xml") == .orderedSame }) else {
            throw EPUBError.invalidContainer
        }

        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EPUB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionRoot) }

        _ = try runUnzip(arguments: ["-qq", "-o", url.path, "-d", extractionRoot.path])
        try validateExtractedContents(at: extractionRoot)

        let containerURL = extractionRoot
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        let containerData = try readData(at: containerURL, maximumBytes: maximumContainerBytes)
        let container = ContainerParser()
        guard container.parse(data: containerData), let packagePath = container.packagePath else {
            throw EPUBError.invalidContainer
        }

        let packageURL = try safeURL(relativePath: packagePath, relativeTo: extractionRoot, root: extractionRoot)
        let packageData = try readData(at: packageURL, maximumBytes: maximumPackageBytes)
        let package = PackageParser()
        guard package.parse(data: packageData) else {
            throw EPUBError.invalidPackage
        }

        let orderedItems = package.spine.compactMap { package.manifest[$0] }
        let contentItems = orderedItems.isEmpty
            ? package.manifest.values.filter { $0.mediaType == "application/xhtml+xml" }
            : orderedItems
        guard !contentItems.isEmpty else { throw EPUBError.noReadableText }

        let packageDirectory = packageURL.deletingLastPathComponent()
        var chapters: [ReferenceChapter] = []
        var analyzedCharacters = 0

        for item in contentItems {
            guard analyzedCharacters < maximumAnalyzedCharacters else { break }
            let contentURL = try safeURL(relativePath: item.href, relativeTo: packageDirectory, root: extractionRoot)
            guard let data = try? readData(at: contentURL, maximumBytes: maximumContentItemBytes), !data.isEmpty else {
                continue
            }
            guard let parsed = extractText(from: data), !parsed.text.isEmpty else { continue }

            let remaining = maximumAnalyzedCharacters - analyzedCharacters
            let text = String(parsed.text.prefix(min(remaining, 160_000)))
            guard !text.isEmpty else { continue }
            chapters.append(ReferenceChapter(
                id: chapters.count,
                title: parsed.title?.nonEmpty ?? "Section \(chapters.count + 1)",
                text: text
            ))
            analyzedCharacters += text.count
        }

        guard !chapters.isEmpty else { throw EPUBError.noReadableText }
        let profile = ReferenceProfileBuilder.build(chapters: chapters)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        return EPUBReference(
            fileName: url.lastPathComponent,
            title: package.title?.nonEmpty ?? fallbackTitle,
            author: package.creator?.nonEmpty,
            chapters: chapters,
            profile: profile
        )
    }

    private static func runUnzip(arguments: [String]) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw EPUBError.unavailable
        }

        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw EPUBError.extractionFailed(message?.nonEmpty)
        }
        return output
    }

    private static func validateArchiveListing(_ data: Data) throws -> [String] {
        guard let listing = String(data: data, encoding: .utf8) else {
            throw EPUBError.invalidContainer
        }
        let entries = listing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !entries.isEmpty, entries.count <= maximumEntries else {
            throw EPUBError.unsafeArchive
        }

        for entry in entries {
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            guard normalized.utf8.count <= 1_024,
                  !normalized.hasPrefix("/"),
                  !normalized.hasPrefix("~"),
                  !components.contains("..") else {
                throw EPUBError.unsafeArchive
            }
        }
        return entries
    }

    private static func validateArchiveMetadata(_ data: Data) throws {
        guard let listing = String(data: data, encoding: .utf8) else {
            throw EPUBError.invalidContainer
        }
        var totalBytes: Int64 = 0
        for line in listing.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 4, let marker = fields.first?.first else { continue }
            if marker == "l" { throw EPUBError.unsafeArchive }
            guard marker == "-" || marker == "d" else { continue }
            guard let size = Int64(fields[3]), size >= 0 else { throw EPUBError.unsafeArchive }
            totalBytes += size
            guard totalBytes <= maximumExtractedBytes else { throw EPUBError.archiveTooLarge }
        }
    }

    private static func validateExtractedContents(at root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw EPUBError.invalidContainer
        }

        var totalBytes: Int64 = 0
        var entryCount = 0
        for case let fileURL as URL in enumerator {
            entryCount += 1
            guard entryCount <= maximumEntries else { throw EPUBError.unsafeArchive }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw EPUBError.unsafeArchive }
            if values.isRegularFile == true {
                totalBytes += Int64(values.fileSize ?? 0)
                guard totalBytes <= maximumExtractedBytes else { throw EPUBError.archiveTooLarge }
            }
        }
    }

    private static func safeURL(relativePath: String, relativeTo base: URL, root: URL) throws -> URL {
        let withoutFragment = relativePath.split(separator: "#", maxSplits: 1).first.map(String.init) ?? relativePath
        let decoded = withoutFragment.removingPercentEncoding ?? withoutFragment
        guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else {
            throw EPUBError.unsafeArchive
        }

        let resolved = base
            .appendingPathComponent(decoded)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard resolved.path.hasPrefix(rootPath) else { throw EPUBError.unsafeArchive }
        return resolved
    }

    private static func readData(at url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw EPUBError.unsafeArchive
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private static func extractText(from data: Data) -> (title: String?, text: String)? {
        let xhtml = XHTMLTextParser()
        if xhtml.parse(data: data), !xhtml.text.isEmpty {
            return (xhtml.title, normalize(xhtml.text))
        }

        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }
        return (nil, normalize(attributed.string))
    }

    private static func normalize(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r", with: "\n")
        value = value.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EPUBError: LocalizedError {
    case unavailable
    case archiveTooLarge
    case unsafeArchive
    case invalidContainer
    case invalidPackage
    case noReadableText
    case extractionFailed(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Kistulentz could not access the EPUB extractor on this Mac."
        case .archiveTooLarge:
            "This EPUB is too large to analyze safely."
        case .unsafeArchive:
            "This EPUB contains unsafe or unusually complex archive paths."
        case .invalidContainer:
            "This file does not contain a valid EPUB container."
        case .invalidPackage:
            "Kistulentz could not read this EPUB's package information."
        case .noReadableText:
            "No readable book text was found. The EPUB may be DRM-protected or image-only."
        case .extractionFailed(let detail):
            detail ?? "The EPUB could not be extracted."
        }
    }
}

private struct ManifestItem {
    let id: String
    let href: String
    let mediaType: String
}

private final class ContainerParser: NSObject, XMLParserDelegate {
    private(set) var packagePath: String?

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if localName(elementName) == "rootfile", packagePath == nil {
            packagePath = attributeDict["full-path"]
        }
    }
}

private final class PackageParser: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var creator: String?
    private(set) var manifest: [String: ManifestItem] = [:]
    private(set) var spine: [String] = []
    private var capture: String?
    private var buffer = ""

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        switch name {
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"],
               let mediaType = attributeDict["media-type"] {
                manifest[id] = ManifestItem(id: id, href: href, mediaType: mediaType)
            }
        case "itemref":
            if let idref = attributeDict["idref"] { spine.append(idref) }
        case "title" where title == nil, "creator" where creator == nil:
            capture = name
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capture != nil { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        guard capture == name else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title", title == nil { title = value }
        if name == "creator", creator == nil { creator = value }
        capture = nil
        buffer = ""
    }
}

private final class XHTMLTextParser: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var text = ""
    private var titleBuffer = ""
    private var isCapturingTitle = false
    private var skippedDepth = 0
    private let skippedElements: Set<String> = ["script", "style", "svg", "nav", "head"]
    private let blockElements: Set<String> = [
        "p", "div", "section", "article", "aside", "blockquote", "li", "br",
        "h1", "h2", "h3", "h4", "h5", "h6", "hr", "tr"
    ]

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if skippedDepth > 0 {
            skippedDepth += 1
            return
        }
        if skippedElements.contains(name) {
            skippedDepth = 1
            if name == "head" { isCapturingTitle = true }
            return
        }
        if name == "title" {
            isCapturingTitle = true
            titleBuffer = ""
        }
        if blockElements.contains(name), !text.hasSuffix("\n") { text += "\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturingTitle { titleBuffer += string }
        if skippedDepth == 0 { text += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if skippedDepth > 0 {
            skippedDepth -= 1
            if skippedDepth == 0, name == "head" { isCapturingTitle = false }
            return
        }
        if name == "title" {
            title = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            isCapturingTitle = false
        }
        if blockElements.contains(name), !text.hasSuffix("\n") { text += "\n" }
    }
}

private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map { String($0).lowercased() } ?? name.lowercased()
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

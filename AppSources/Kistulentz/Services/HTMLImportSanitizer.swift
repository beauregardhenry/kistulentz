import Foundation

struct SanitizedHTMLImport {
    var html: String
    var assets: [DocumentImportAsset]
    var notices: [DocumentImportNotice]
}

enum HTMLImportSanitizer {
    private static let maximumImageBytes = 40_000_000

    static func prepare(_ source: String, sourceURL: URL) -> SanitizedHTMLImport {
        var html = source
        var assets: [DocumentImportAsset] = []
        var notices: [DocumentImportNotice] = []
        var omittedRemoteImages = 0

        for pattern in [
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe\s*>"#,
            #"(?is)<object\b[^>]*>.*?</object\s*>"#,
            #"(?is)<video\b[^>]*>.*?</video\s*>"#,
            #"(?is)<audio\b[^>]*>.*?</audio\s*>"#,
            #"(?is)<svg\b[^>]*>.*?</svg\s*>"#,
            #"(?is)<canvas\b[^>]*>.*?</canvas\s*>"#,
            #"(?is)<embed\b[^>]*>"#,
            #"(?is)<source\b[^>]*>"#,
            #"(?is)<meta\b[^>]*>"#,
            #"(?is)<link\b[^>]*>"#,
            #"(?is)<base\b[^>]*>"#
        ] {
            html = replacing(pattern: pattern, in: html, with: "")
        }
        for attributePattern in [
            #"(?is)\sstyle\s*=\s*([\"']).*?\1"#,
            #"(?is)\sbackground\s*=\s*([\"']).*?\1"#,
            #"(?is)\ssrcset\s*=\s*([\"']).*?\1"#
        ] {
            html = replacing(pattern: attributePattern, in: html, with: "")
        }

        guard let imageRegex = try? NSRegularExpression(pattern: #"(?is)<img\b[^>]*>"#) else {
            return SanitizedHTMLImport(html: html, assets: assets, notices: notices)
        }
        let range = NSRange(location: 0, length: (html as NSString).length)
        for match in imageRegex.matches(in: html, range: range).reversed() {
            let tag = (html as NSString).substring(with: match.range)
            let sourceValue = attribute("src", in: tag) ?? ""
            let alt = attribute("alt", in: tag)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement: String

            if let asset = dataURIAsset(sourceValue, alt: alt, number: assets.count + 1) {
                assets.append(asset)
                replacement = "<p>\(DocumentImportDraft.assetToken(asset.id))</p>"
            } else if let asset = localAsset(sourceValue, alt: alt, sourceURL: sourceURL, number: assets.count + 1) {
                assets.append(asset)
                replacement = "<p>\(DocumentImportDraft.assetToken(asset.id))</p>"
            } else {
                if sourceValue.lowercased().hasPrefix("http://") || sourceValue.lowercased().hasPrefix("https://") {
                    omittedRemoteImages += 1
                }
                replacement = "<p>[Image omitted during import: \(escapedHTML(alt?.isEmpty == false ? alt! : "unavailable image"))]</p>"
            }
            html = (html as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        if omittedRemoteImages > 0 {
            notices.append(DocumentImportNotice(
                severity: .warning,
                title: "Remote images were not downloaded",
                detail: "Kistulentz omitted \(omittedRemoteImages) remote image\(omittedRemoteImages == 1 ? "" : "s") so importing the HTML remained local."
            ))
        }
        return SanitizedHTMLImport(html: html, assets: assets, notices: notices)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)\\b\(escaped)\\s*=\\s*([\"'])(.*?)\\1"
        ) else { return nil }
        let fullRange = NSRange(location: 0, length: (tag as NSString).length)
        guard let match = regex.firstMatch(in: tag, range: fullRange), match.numberOfRanges > 2 else { return nil }
        return (tag as NSString).substring(with: match.range(at: 2))
    }

    private static func dataURIAsset(_ source: String, alt: String?, number: Int) -> DocumentImportAsset? {
        guard source.lowercased().hasPrefix("data:image/"),
              let comma = source.firstIndex(of: ",") else { return nil }
        let metadata = String(source[..<comma]).lowercased()
        guard metadata.contains(";base64") else { return nil }
        let encoded = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              !data.isEmpty,
              data.count <= maximumImageBytes else { return nil }
        let subtype = metadata
            .dropFirst("data:image/".count)
            .split(separator: ";").first.map(String.init) ?? "png"
        let ext = subtype == "jpeg" ? "jpg" : DocumentImportFilename.safe(subtype)
        return DocumentImportAsset(
            suggestedFilename: "image-\(number).\(ext)",
            altText: alt?.isEmpty == false ? alt! : "Imported image \(number)",
            data: data
        )
    }

    private static func localAsset(
        _ source: String,
        alt: String?,
        sourceURL: URL,
        number: Int
    ) -> DocumentImportAsset? {
        guard !source.isEmpty,
              !source.contains(":"),
              let decoded = source.removingPercentEncoding else { return nil }
        let root = sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(decoded).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              let data = try? Data(contentsOf: candidate, options: .mappedIfSafe),
              !data.isEmpty,
              data.count <= maximumImageBytes else { return nil }
        let proposed = candidate.lastPathComponent.isEmpty ? "image-\(number).png" : candidate.lastPathComponent
        return DocumentImportAsset(
            suggestedFilename: proposed,
            altText: alt?.isEmpty == false ? alt! : candidate.deletingPathExtension().lastPathComponent,
            data: data
        )
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(location: 0, length: (value as NSString).length)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func escapedHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

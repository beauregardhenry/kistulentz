import Foundation

struct ResearchMetadataLookupService {
    var dataLoader: (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }

    func lookupDOI(_ rawValue: String) async throws -> ResearchSource {
        let doi = Self.normalizedDOI(rawValue)
        guard doi.contains("/"), doi.hasPrefix("10.") else { throw ResearchLibraryError.invalidIdentifier }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.crossref.org/works/\(encoded)") else {
            throw ResearchLibraryError.invalidIdentifier
        }
        let data = try await load(url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let item = root?["message"] as? [String: Any],
              let title = (item["title"] as? [String])?.first,
              !title.isEmpty else { throw ResearchLibraryError.metadataNotFound }

        let creators = (item["author"] as? [[String: Any]] ?? []).map {
            ResearchCreator(
                givenName: $0["given"] as? String ?? "",
                familyName: $0["family"] as? String ?? "",
                literalName: $0["name"] as? String ?? ""
            )
        }
        let parts = Self.dateParts(item["published-print"])
            ?? Self.dateParts(item["published-online"])
            ?? Self.dateParts(item["issued"])
        return ResearchSource(
            type: Self.crossrefType(item["type"] as? String ?? ""),
            title: title,
            subtitle: (item["subtitle"] as? [String])?.first ?? "",
            creators: creators,
            issuedYear: parts?.first,
            issuedDate: parts?.map(String.init).joined(separator: "-") ?? "",
            containerTitle: (item["container-title"] as? [String])?.first ?? "",
            publisher: item["publisher"] as? String ?? "",
            volume: Self.stringValue(item["volume"]),
            issue: Self.stringValue(item["issue"]),
            pages: Self.stringValue(item["page"]),
            DOI: item["DOI"] as? String ?? doi,
            ISBN: (item["ISBN"] as? [String])?.first ?? "",
            URLString: item["URL"] as? String ?? "",
            abstract: Self.plainText(item["abstract"] as? String ?? ""),
            keywords: item["subject"] as? [String] ?? []
        )
    }

    func lookupISBN(_ rawValue: String) async throws -> ResearchSource {
        let isbn = rawValue.uppercased().filter { $0.isNumber || $0 == "X" }
        guard isbn.count == 10 || isbn.count == 13 else { throw ResearchLibraryError.invalidIdentifier }
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "isbn:\(isbn)"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,publisher,isbn"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { throw ResearchLibraryError.invalidIdentifier }
        let data = try await load(url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let item = (root?["docs"] as? [[String: Any]])?.first,
              let title = item["title"] as? String,
              !title.isEmpty else { throw ResearchLibraryError.metadataNotFound }
        let creators = (item["author_name"] as? [String] ?? []).map {
            ResearchCreator(literalName: $0)
        }
        let workKey = item["key"] as? String ?? ""
        return ResearchSource(
            type: .book,
            title: title,
            creators: creators,
            issuedYear: item["first_publish_year"] as? Int,
            publisher: (item["publisher"] as? [String])?.first ?? "",
            ISBN: (item["isbn"] as? [String])?.first(where: { $0.uppercased().filter { $0.isNumber || $0 == "X" } == isbn }) ?? isbn,
            URLString: workKey.isEmpty ? "" : "https://openlibrary.org\(workKey)"
        )
    }

    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Kistulentz/0.13.0 (https://github.com/beauregardhenry/kistulentz)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await dataLoader(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResearchLibraryError.metadataNotFound
        }
        return data
    }

    private static func normalizedDOI(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func dateParts(_ value: Any?) -> [Int]? {
        ((value as? [String: Any])?["date-parts"] as? [[Int]])?.first
    }

    private static func stringValue(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func crossrefType(_ value: String) -> ResearchSourceType {
        switch value.lowercased() {
        case "book": .book
        case "book-chapter", "reference-entry": .bookChapter
        case "journal-article": .journalArticle
        case "proceedings-article": .conferencePaper
        case "report": .report
        case "dissertation": .thesis
        case "dataset": .dataset
        case "posted-content": .webpage
        default: .other
        }
    }
}

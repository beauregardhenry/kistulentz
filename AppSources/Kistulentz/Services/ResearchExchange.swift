import Foundation

enum ResearchExchange {
    static func importSources(from url: URL) throws -> [ResearchSource] {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let sources: [ResearchSource]
        switch ext {
        case "bib", "bibtex":
            sources = parseBibTeX(String(data: data, encoding: .utf8) ?? "")
        case "ris":
            sources = parseRIS(String(data: data, encoding: .utf8) ?? "")
        case "json", "csljson":
            sources = try parseCSLJSON(data)
        default:
            if let parsed = try? parseCSLJSON(data), !parsed.isEmpty { sources = parsed }
            else if let text = String(data: data, encoding: .utf8), text.contains("TY  -") { sources = parseRIS(text) }
            else if let text = String(data: data, encoding: .utf8), text.contains("@") { sources = parseBibTeX(text) }
            else { throw ResearchLibraryError.unsupportedImport }
        }
        guard !sources.isEmpty else { throw ResearchLibraryError.unsupportedImport }
        return sources
    }

    static func exportCSLJSON(_ sources: [ResearchSource], to url: URL) throws {
        let values = sources.map(cslObject)
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    static func exportBibTeX(_ sources: [ResearchSource], to url: URL) throws {
        let value = sources.map(bibTeX).joined(separator: "\n\n") + "\n"
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportRIS(_ sources: [ResearchSource], to url: URL) throws {
        let value = sources.map(ris).joined(separator: "\n")
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    static func normalizedCitationKey(_ value: String) -> String {
        String(value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || "_-:".unicodeScalars.contains($0)
        })
    }

    static func suggestedCitationKey(for source: ResearchSource, existing: Set<String>) -> String {
        let creator = source.authors.first?.familyName.nonEmptyResearch
            ?? source.authors.first?.literalName.nonEmptyResearch
            ?? source.creators.first?.familyName.nonEmptyResearch
            ?? "source"
        let creatorPart = asciiWord(creator)
        let year = source.issuedYear.map(String.init) ?? "nd"
        let titleWord = source.title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .first(where: { !["a", "an", "the", "of", "in", "and"].contains($0.lowercased()) })
            .map(asciiWord) ?? "work"
        let base = [creatorPart, year, titleWord].joined().lowercased()
        var candidate = base.isEmpty ? "source\(year)" : base
        var suffix = 2
        let folded = Set(existing.map { $0.lowercased() })
        while folded.contains(candidate.lowercased()) {
            candidate = "\(base)\(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func duplicate(of source: ResearchSource, in existing: [ResearchSource]) -> ResearchSource? {
        let doi = normalizedDOI(source.DOI)
        if !doi.isEmpty, let match = existing.first(where: { normalizedDOI($0.DOI) == doi }) { return match }
        let isbn = digitsAndX(source.ISBN)
        if !isbn.isEmpty, let match = existing.first(where: { digitsAndX($0.ISBN) == isbn }) { return match }
        let title = normalizedComparison(source.title)
        let creator = normalizedComparison(source.primaryCreatorName)
        return existing.first {
            normalizedComparison($0.title) == title && normalizedComparison($0.primaryCreatorName) == creator
        }
    }

    static func merged(existing: ResearchSource, incoming: ResearchSource) -> ResearchSource {
        var result = existing
        func prefer(_ current: inout String, _ proposed: String) {
            if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { current = proposed }
        }
        prefer(&result.title, incoming.title)
        prefer(&result.subtitle, incoming.subtitle)
        if result.creators.isEmpty { result.creators = incoming.creators }
        if result.issuedYear == nil { result.issuedYear = incoming.issuedYear }
        prefer(&result.issuedDate, incoming.issuedDate)
        prefer(&result.containerTitle, incoming.containerTitle)
        prefer(&result.publisher, incoming.publisher)
        prefer(&result.publisherPlace, incoming.publisherPlace)
        prefer(&result.volume, incoming.volume)
        prefer(&result.issue, incoming.issue)
        prefer(&result.edition, incoming.edition)
        prefer(&result.pages, incoming.pages)
        prefer(&result.DOI, incoming.DOI)
        prefer(&result.ISBN, incoming.ISBN)
        prefer(&result.URLString, incoming.URLString)
        prefer(&result.accessedDate, incoming.accessedDate)
        prefer(&result.abstract, incoming.abstract)
        result.keywords = Array(Set(result.keywords + incoming.keywords)).sorted()
        result.modifiedAt = Date()
        return result
    }

    private static func parseCSLJSON(_ data: Data) throws -> [ResearchSource] {
        let root = try JSONSerialization.jsonObject(with: data)
        let items: [[String: Any]]
        if let array = root as? [[String: Any]] { items = array }
        else if let dictionary = root as? [String: Any], let array = dictionary["items"] as? [[String: Any]] { items = array }
        else if let dictionary = root as? [String: Any] { items = [dictionary] }
        else { return [] }

        return items.compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            var creators: [ResearchCreator] = []
            for (key, role) in [("author", ResearchCreatorRole.author), ("editor", .editor), ("translator", .translator)] {
                for person in item[key] as? [[String: Any]] ?? [] {
                    creators.append(ResearchCreator(
                        role: role,
                        givenName: person["given"] as? String ?? "",
                        familyName: person["family"] as? String ?? "",
                        literalName: person["literal"] as? String ?? ""
                    ))
                }
            }
            let dateParts = ((item["issued"] as? [String: Any])?["date-parts"] as? [[Int]])?.first
            let year = dateParts?.first
            let issuedDate = dateParts?.map(String.init).joined(separator: "-") ?? ""
            return ResearchSource(
                citeKey: item["id"] as? String ?? "",
                type: ResearchSourceType(cslType: item["type"] as? String ?? "document"),
                title: title,
                subtitle: item["title-short"] as? String ?? "",
                creators: creators,
                issuedYear: year,
                issuedDate: issuedDate,
                containerTitle: item["container-title"] as? String ?? "",
                publisher: item["publisher"] as? String ?? "",
                publisherPlace: item["publisher-place"] as? String ?? "",
                volume: stringValue(item["volume"]),
                issue: stringValue(item["issue"]),
                edition: stringValue(item["edition"]),
                pages: stringValue(item["page"]),
                DOI: item["DOI"] as? String ?? "",
                ISBN: (item["ISBN"] as? [String])?.first ?? item["ISBN"] as? String ?? "",
                URLString: item["URL"] as? String ?? "",
                accessedDate: "",
                abstract: item["abstract"] as? String ?? "",
                keywords: (item["keyword"] as? String)?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            )
        }
    }

    private static func parseBibTeX(_ text: String) -> [ResearchSource] {
        var scanner = BibScanner(text)
        return scanner.records().compactMap { record in
            guard let title = record.fields["title"]?.strippingBibTeX, !title.isEmpty else { return nil }
            let authors = parseBibNames(record.fields["author"] ?? "", role: .author)
            let editors = parseBibNames(record.fields["editor"] ?? "", role: .editor)
            let year = Int(record.fields["year"]?.filter(\.isNumber) ?? "")
            return ResearchSource(
                citeKey: normalizedCitationKey(record.key),
                type: bibType(record.type),
                title: title,
                subtitle: "",
                creators: authors + editors,
                issuedYear: year,
                issuedDate: record.fields["date"]?.strippingBibTeX ?? "",
                containerTitle: (record.fields["journal"] ?? record.fields["booktitle"] ?? "").strippingBibTeX,
                publisher: (record.fields["publisher"] ?? "").strippingBibTeX,
                publisherPlace: (record.fields["address"] ?? "").strippingBibTeX,
                volume: (record.fields["volume"] ?? "").strippingBibTeX,
                issue: (record.fields["number"] ?? "").strippingBibTeX,
                edition: (record.fields["edition"] ?? "").strippingBibTeX,
                pages: (record.fields["pages"] ?? "").strippingBibTeX,
                DOI: (record.fields["doi"] ?? "").strippingBibTeX,
                ISBN: (record.fields["isbn"] ?? "").strippingBibTeX,
                URLString: (record.fields["url"] ?? "").strippingBibTeX,
                accessedDate: (record.fields["urldate"] ?? "").strippingBibTeX,
                abstract: (record.fields["abstract"] ?? "").strippingBibTeX,
                keywords: (record.fields["keywords"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
        }
    }

    private static func parseRIS(_ text: String) -> [ResearchSource] {
        var records: [[String: [String]]] = []
        var current: [String: [String]] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard line.count >= 6 else { continue }
            let key = String(line.prefix(2))
            guard line.dropFirst(2).hasPrefix("  -") else { continue }
            let value = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "TY" { current = [key: [value]] }
            else if key == "ER" {
                if !current.isEmpty { records.append(current) }
                current = [:]
            } else { current[key, default: []].append(value) }
        }
        if !current.isEmpty { records.append(current) }
        return records.compactMap { record in
            let title = record["TI"]?.first ?? record["T1"]?.first ?? ""
            guard !title.isEmpty else { return nil }
            let creators = (record["AU"] ?? record["A1"] ?? []).map { risName($0, role: .author) }
                + (record["ED"] ?? record["A2"] ?? []).map { risName($0, role: .editor) }
            let yearText = record["PY"]?.first ?? record["Y1"]?.first ?? ""
            return ResearchSource(
                citeKey: normalizedCitationKey(record["ID"]?.first ?? ""),
                type: risType(record["TY"]?.first ?? "GEN"),
                title: title,
                creators: creators,
                issuedYear: Int(yearText.prefix(4)),
                issuedDate: yearText,
                containerTitle: record["JO"]?.first ?? record["JF"]?.first ?? record["T2"]?.first ?? "",
                publisher: record["PB"]?.first ?? "",
                publisherPlace: record["CY"]?.first ?? "",
                volume: record["VL"]?.first ?? "",
                issue: record["IS"]?.first ?? "",
                edition: record["ET"]?.first ?? "",
                pages: risPages(record),
                DOI: record["DO"]?.first ?? "",
                ISBN: record["SN"]?.first ?? "",
                URLString: record["UR"]?.first ?? "",
                accessedDate: record["Y2"]?.first ?? "",
                abstract: record["AB"]?.first ?? "",
                keywords: record["KW"] ?? []
            )
        }
    }

    private static func cslObject(_ source: ResearchSource) -> [String: Any] {
        var object: [String: Any] = [
            "id": source.citeKey,
            "type": source.type.cslType,
            "title": source.title
        ]
        func put(_ key: String, _ value: String) { if !value.isEmpty { object[key] = value } }
        put("title-short", source.subtitle)
        put("container-title", source.containerTitle)
        put("publisher", source.publisher)
        put("publisher-place", source.publisherPlace)
        put("volume", source.volume)
        put("issue", source.issue)
        put("edition", source.edition)
        put("page", source.pages)
        put("DOI", source.DOI)
        put("URL", source.URLString)
        put("abstract", source.abstract)
        if !source.ISBN.isEmpty { object["ISBN"] = [source.ISBN] }
        if !source.keywords.isEmpty { object["keyword"] = source.keywords.joined(separator: ", ") }
        if let year = source.issuedYear { object["issued"] = ["date-parts": [[year]]] }
        for role in [ResearchCreatorRole.author, .editor, .translator] {
            let values = source.creators.filter { $0.role == role }.map { creator -> [String: String] in
                if !creator.literalName.isEmpty { return ["literal": creator.literalName] }
                return ["given": creator.givenName, "family": creator.familyName]
            }
            if !values.isEmpty { object[role.rawValue] = values }
        }
        return object
    }

    private static func bibTeX(_ source: ResearchSource) -> String {
        let type: String
        switch source.type {
        case .book: type = "book"
        case .bookChapter: type = "incollection"
        case .journalArticle: type = "article"
        case .conferencePaper: type = "inproceedings"
        case .thesis: type = "phdthesis"
        case .report: type = "techreport"
        default: type = "misc"
        }
        var fields: [(String, String)] = [("title", source.title)]
        let authors = source.authors.map(bibName).joined(separator: " and ")
        if !authors.isEmpty { fields.append(("author", authors)) }
        if let year = source.issuedYear { fields.append(("year", String(year))) }
        for (key, value) in [
            ("journal", source.containerTitle), ("publisher", source.publisher),
            ("address", source.publisherPlace), ("volume", source.volume), ("number", source.issue),
            ("edition", source.edition), ("pages", source.pages), ("doi", source.DOI),
            ("isbn", source.ISBN), ("url", source.URLString), ("abstract", source.abstract),
            ("keywords", source.keywords.joined(separator: ", "))
        ] where !value.isEmpty { fields.append((key, value)) }
        let body = fields.map { "  \($0.0) = {\(escapeBib($0.1))}" }.joined(separator: ",\n")
        return "@\(type){\(source.citeKey),\n\(body)\n}"
    }

    private static func ris(_ source: ResearchSource) -> String {
        var lines = ["TY  - \(risCode(source.type))", "ID  - \(source.citeKey)", "TI  - \(source.title)"]
        for creator in source.authors { lines.append("AU  - \(creator.sortName)") }
        if let year = source.issuedYear { lines.append("PY  - \(year)") }
        for (tag, value) in [
            ("JO", source.containerTitle), ("PB", source.publisher), ("CY", source.publisherPlace),
            ("VL", source.volume), ("IS", source.issue), ("SP", source.pages), ("DO", source.DOI),
            ("SN", source.ISBN), ("UR", source.URLString), ("AB", source.abstract)
        ] where !value.isEmpty { lines.append("\(tag)  - \(value)") }
        for keyword in source.keywords { lines.append("KW  - \(keyword)") }
        lines.append("ER  -")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseBibNames(_ value: String, role: ResearchCreatorRole) -> [ResearchCreator] {
        value.strippingBibTeX.components(separatedBy: " and ").map { raw in
            let pieces = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pieces.count == 2 { return ResearchCreator(role: role, givenName: pieces[1], familyName: pieces[0]) }
            let words = raw.split(separator: " ").map(String.init)
            guard words.count > 1 else { return ResearchCreator(role: role, literalName: raw) }
            return ResearchCreator(role: role, givenName: words.dropLast().joined(separator: " "), familyName: words.last ?? "")
        }.filter { !$0.displayName.isEmpty }
    }

    private static func risName(_ raw: String, role: ResearchCreatorRole) -> ResearchCreator {
        let pieces = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.count == 2
            ? ResearchCreator(role: role, givenName: pieces[1], familyName: pieces[0])
            : ResearchCreator(role: role, literalName: raw)
    }

    private static func bibName(_ creator: ResearchCreator) -> String {
        if !creator.literalName.isEmpty { return creator.literalName }
        return [creator.familyName, creator.givenName].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func bibType(_ value: String) -> ResearchSourceType {
        switch value.lowercased() {
        case "book", "booklet": .book
        case "inbook", "incollection": .bookChapter
        case "article": .journalArticle
        case "inproceedings", "conference": .conferencePaper
        case "phdthesis", "mastersthesis": .thesis
        case "techreport": .report
        default: .other
        }
    }

    private static func risType(_ value: String) -> ResearchSourceType {
        switch value.uppercased() {
        case "BOOK": .book
        case "CHAP": .bookChapter
        case "JOUR": .journalArticle
        case "MGZN": .magazineArticle
        case "NEWS": .newspaperArticle
        case "ELEC", "WEB": .webpage
        case "RPRT": .report
        case "THES": .thesis
        case "CONF", "CPAPER": .conferencePaper
        case "DATA": .dataset
        default: .other
        }
    }

    private static func risCode(_ type: ResearchSourceType) -> String {
        switch type {
        case .book: "BOOK"
        case .bookChapter: "CHAP"
        case .journalArticle: "JOUR"
        case .magazineArticle: "MGZN"
        case .newspaperArticle: "NEWS"
        case .webpage: "ELEC"
        case .report: "RPRT"
        case .thesis: "THES"
        case .conferencePaper: "CPAPER"
        case .dataset: "DATA"
        default: "GEN"
        }
    }

    private static func risPages(_ record: [String: [String]]) -> String {
        let start = record["SP"]?.first ?? ""
        let end = record["EP"]?.first ?? ""
        return end.isEmpty ? start : "\(start)-\(end)"
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func normalizedDOI(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func digitsAndX(_ value: String) -> String {
        value.uppercased().filter { $0.isNumber || $0 == "X" }
    }

    private static func normalizedComparison(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func asciiWord(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func escapeBib(_ value: String) -> String {
        value.replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")
    }
}

private struct BibRecord {
    let type: String
    let key: String
    let fields: [String: String]
}

private struct BibScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) { characters = Array(text) }

    mutating func records() -> [BibRecord] {
        var result: [BibRecord] = []
        while let at = characters[index...].firstIndex(of: "@") {
            index = at + 1
            let type = read(until: { $0 == "{" || $0 == "(" }).trimmingCharacters(in: .whitespacesAndNewlines)
            guard index < characters.count else { break }
            let closing: Character = characters[index] == "{" ? "}" : ")"
            index += 1
            let key = read(until: { $0 == "," }).trimmingCharacters(in: .whitespacesAndNewlines)
            if index < characters.count { index += 1 }
            var fields: [String: String] = [:]
            while index < characters.count {
                skipWhitespaceAndCommas()
                if index >= characters.count || characters[index] == closing { index += min(1, characters.count - index); break }
                let name = read(until: { $0 == "=" }).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard index < characters.count else { break }
                index += 1
                skipWhitespaceAndCommas(includeCommas: false)
                let value = readValue(closing: closing)
                if !name.isEmpty { fields[name] = value }
            }
            if !type.isEmpty { result.append(BibRecord(type: type, key: key, fields: fields)) }
        }
        return result
    }

    private mutating func read(until predicate: (Character) -> Bool) -> String {
        let start = index
        while index < characters.count && !predicate(characters[index]) { index += 1 }
        return String(characters[start..<index])
    }

    private mutating func readValue(closing: Character) -> String {
        guard index < characters.count else { return "" }
        if characters[index] == "{" {
            index += 1
            let start = index
            var depth = 1
            while index < characters.count, depth > 0 {
                if characters[index] == "{" { depth += 1 }
                if characters[index] == "}" { depth -= 1 }
                index += 1
            }
            return String(characters[start..<max(start, index - 1)])
        }
        if characters[index] == "\"" {
            index += 1
            let start = index
            while index < characters.count {
                if characters[index] == "\"", index == 0 || characters[index - 1] != "\\" { break }
                index += 1
            }
            let value = String(characters[start..<index])
            if index < characters.count { index += 1 }
            return value
        }
        return read(until: { $0 == "," || $0 == closing }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func skipWhitespaceAndCommas(includeCommas: Bool = true) {
        while index < characters.count,
              characters[index].isWhitespace || (includeCommas && characters[index] == ",") { index += 1 }
    }
}

private extension String {
    var strippingBibTeX: String {
        replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyResearch: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

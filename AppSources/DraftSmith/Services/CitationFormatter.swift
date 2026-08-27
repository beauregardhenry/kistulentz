import Foundation

enum CitationFormatter {
    static func markdownCitation(for source: ResearchSource, locator: String = "") -> String {
        let cleanLocator = locator.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanLocator.isEmpty ? "[@\(source.citeKey)]" : "[@\(source.citeKey), \(cleanLocator)]"
    }

    static func bibliography(_ sources: [ResearchSource], style: BibliographyStyle) -> String {
        let sorted = sources.sorted { lhs, rhs in
            let left = lhs.primaryCreatorName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let right = rhs.primaryCreatorName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return sorted.enumerated().map { index, source in
            entry(source, style: style, number: index + 1)
        }.joined(separator: "\n\n")
    }

    static func entry(_ source: ResearchSource, style: BibliographyStyle, number: Int = 1) -> String {
        switch style {
        case .chicagoNotes:
            chicago(source, authorDate: false)
        case .chicagoAuthorDate:
            chicago(source, authorDate: true)
        case .apa:
            apa(source)
        case .mla:
            mla(source)
        case .numbered:
            "[\(number)] \(numbered(source))"
        }
    }

    private static func chicago(_ source: ResearchSource, authorDate: Bool) -> String {
        let creators = creatorList(source.authors, style: .chicago)
        let year = source.issuedYear.map(String.init) ?? "n.d."
        var parts: [String] = []
        if !creators.isEmpty { parts.append(ensurePeriod(creators)) }
        if authorDate { parts.append(ensurePeriod(year)) }
        parts.append("*\(source.title)*.")
        if !source.edition.isEmpty { parts.append("\(source.edition) ed.") }
        let publication = [source.publisherPlace, source.publisher].filter { !$0.isEmpty }.joined(separator: ": ")
        if !publication.isEmpty {
            parts.append(authorDate ? ensurePeriod(publication) : "\(publication), \(year).")
        } else if !authorDate { parts.append(ensurePeriod(year)) }
        appendIdentifiers(source, to: &parts)
        return parts.joined(separator: " ")
    }

    private static func apa(_ source: ResearchSource) -> String {
        let creators = creatorList(source.authors, style: .apa)
        let year = source.issuedYear.map(String.init) ?? "n.d."
        var parts = [creators.isEmpty ? "Unknown author." : ensurePeriod(creators), "(\(year)).", "*\(sentenceCase(source.title))*."]
        if !source.containerTitle.isEmpty {
            var container = "*\(source.containerTitle)*"
            if !source.volume.isEmpty { container += ", *\(source.volume)*" }
            if !source.issue.isEmpty { container += "(\(source.issue))" }
            if !source.pages.isEmpty { container += ", \(source.pages)" }
            parts.append(ensurePeriod(container))
        } else if !source.publisher.isEmpty {
            parts.append(ensurePeriod(source.publisher))
        }
        appendIdentifiers(source, to: &parts)
        return parts.joined(separator: " ")
    }

    private static func mla(_ source: ResearchSource) -> String {
        let creators = creatorList(source.authors, style: .mla)
        var parts: [String] = []
        if !creators.isEmpty { parts.append(ensurePeriod(creators)) }
        parts.append("*\(source.title)*.")
        if !source.containerTitle.isEmpty { parts.append("*\(source.containerTitle)*,") }
        if !source.publisher.isEmpty { parts.append("\(source.publisher),") }
        if let year = source.issuedYear { parts.append("\(year),") }
        if !source.pages.isEmpty { parts.append("pp. \(source.pages).") }
        appendIdentifiers(source, to: &parts)
        return parts.joined(separator: " ")
    }

    private static func numbered(_ source: ResearchSource) -> String {
        let creators = creatorList(source.authors, style: .numbered)
        var parts: [String] = []
        if !creators.isEmpty { parts.append(ensurePeriod(creators)) }
        parts.append("\(source.title).")
        if !source.containerTitle.isEmpty { parts.append("\(source.containerTitle).") }
        if let year = source.issuedYear { parts.append("\(year).") }
        if !source.volume.isEmpty { parts.append("vol. \(source.volume).") }
        if !source.pages.isEmpty { parts.append("pp. \(source.pages).") }
        appendIdentifiers(source, to: &parts)
        return parts.joined(separator: " ")
    }

    private enum CreatorStyle { case chicago, apa, mla, numbered }

    private static func creatorList(_ creators: [ResearchCreator], style: CreatorStyle) -> String {
        guard !creators.isEmpty else { return "" }
        let names = creators.map { creator -> String in
            if !creator.literalName.isEmpty { return creator.literalName }
            switch style {
            case .apa:
                let initials = creator.givenName.split(separator: " ").compactMap(\.first).map { "\($0)." }.joined(separator: " ")
                return [creator.familyName, initials].filter { !$0.isEmpty }.joined(separator: ", ")
            case .chicago, .mla:
                return creator.sortName
            case .numbered:
                let initials = creator.givenName.split(separator: " ").compactMap(\.first).map(String.init).joined()
                return [initials, creator.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        if names.count == 1 { return names[0] }
        if names.count > 7, style == .apa { return names.prefix(6).joined(separator: ", ") + ", …, " + names.last! }
        if names.count > 3 { return names[0] + " et al." }
        return names.dropLast().joined(separator: ", ") + (names.count == 2 ? " and " : ", and ") + names.last!
    }

    private static func appendIdentifiers(_ source: ResearchSource, to parts: inout [String]) {
        if !source.DOI.isEmpty {
            let doi = source.DOI
                .replacingOccurrences(of: "https://doi.org/", with: "")
                .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            parts.append("https://doi.org/\(doi).")
        } else if !source.URLString.isEmpty {
            parts.append(ensurePeriod(source.URLString))
        }
    }

    private static func ensurePeriod(_ value: String) -> String {
        value.hasSuffix(".") ? value : value + "."
    }

    private static func sentenceCase(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}

enum ProjectResearchDisk {
    static let notesFileName = "Kistulentz Research Notes.md"
    private static let bibliographyFileName = "bibliography.json"

    static func prepare(at root: URL, projectName: String) throws {
        let bibliographyURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent(bibliographyFileName)
        if !FileManager.default.fileExists(atPath: bibliographyURL.path) {
            try save(ProjectBibliographyArchive(), at: root)
        }
        let notesURL = notesURL(at: root)
        if !FileManager.default.fileExists(atPath: notesURL.path) {
            let text = """
            # \(projectName) Research Notes

            Use this file for project-specific source notes, quotations, questions, and research decisions. Citation records and attachment indexes remain in the hidden `.kistulentz` project folder so Kistulentz can validate them safely.

            ## Notes

            """
            try text.write(to: notesURL, atomically: true, encoding: .utf8)
        }
    }

    static func load(at root: URL) throws -> ProjectBibliographyArchive {
        let url = WritingProjectDisk.metadataURL(at: root).appendingPathComponent(bibliographyFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return ProjectBibliographyArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectBibliographyArchive.self, from: Data(contentsOf: url))
    }

    static func save(_ archive: ProjectBibliographyArchive, at root: URL) throws {
        try FileManager.default.createDirectory(at: WritingProjectDisk.metadataURL(at: root), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(
            to: WritingProjectDisk.metadataURL(at: root).appendingPathComponent(bibliographyFileName),
            options: .atomic
        )
    }

    static func notesURL(at root: URL) -> URL { root.appendingPathComponent(notesFileName) }
}

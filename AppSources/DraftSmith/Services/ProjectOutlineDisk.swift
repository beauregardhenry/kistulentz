import Foundation

enum ProjectOutlineDisk {
    private static let fileName = "outline.json"

    static func prepare(at root: URL, manifest: WritingProjectManifest) throws {
        let url = outlineURL(at: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let archive = ProjectOutlineArchive(nodes: importedNodes(
            paths: manifest.chapterOrder,
            projectKind: manifest.kind,
            root: root
        ))
        try save(archive, at: root)
    }

    static func load(at root: URL) throws -> ProjectOutlineArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectOutlineArchive.self, from: Data(contentsOf: outlineURL(at: root)))
    }

    static func save(_ archive: ProjectOutlineArchive, at root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: outlineURL(at: root), options: .atomic)
    }

    static func reconcile(
        _ archive: ProjectOutlineArchive,
        chapterPaths: [String],
        projectKind: WritingProjectKind,
        root: URL
    ) -> ProjectOutlineArchive {
        let represented = Set(OutlineTree.filePaths(in: archive.nodes))
        let missing = chapterPaths.filter { !represented.contains($0) }
        guard !missing.isEmpty else { return archive }
        var result = archive
        result.nodes.append(contentsOf: importedNodes(paths: missing, projectKind: projectKind, root: root))
        return result
    }

    static func outlineURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(fileName)
    }

    static func importedNodes(
        paths: [String],
        projectKind: WritingProjectKind,
        root: URL
    ) -> [OutlineNode] {
        var nodes: [OutlineNode] = []
        var folderOrder: [String] = []
        var folderPaths: [String: [String]] = [:]

        for relativePath in paths {
            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else {
                nodes.append(fileNode(path: relativePath, kind: .chapter, root: root))
                continue
            }
            let folder = components[0]
            if folderPaths[folder] == nil { folderOrder.append(folder) }
            folderPaths[folder, default: []].append(relativePath)
        }

        for folder in folderOrder {
            let groupedPaths = folderPaths[folder] ?? []
            var partChildren: [OutlineNode] = []
            var nestedOrder: [String] = []
            var nestedPaths: [String: [String]] = [:]

            for relativePath in groupedPaths {
                let components = relativePath.split(separator: "/").map(String.init)
                if components.count == 2 {
                    partChildren.append(fileNode(path: relativePath, kind: .chapter, root: root))
                } else {
                    let nested = components[1]
                    if nestedPaths[nested] == nil { nestedOrder.append(nested) }
                    nestedPaths[nested, default: []].append(relativePath)
                }
            }

            for nested in nestedOrder {
                let leafKind: OutlineNodeKind = projectKind == .fiction ? .scene : .section
                let leaves = (nestedPaths[nested] ?? []).map { fileNode(path: $0, kind: leafKind, root: root) }
                partChildren.append(OutlineNode(title: nested, kind: .chapter, children: leaves))
            }
            nodes.append(OutlineNode(title: folder, kind: .part, children: partChildren))
        }
        return nodes
    }

    private static func fileNode(path: String, kind: OutlineNodeKind, root: URL) -> OutlineNode {
        let fallback = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let text = (try? WritingProjectDisk.readChapter(path, at: root)) ?? ""
        let title = text.components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.hasPrefix("# ") })
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        var metadata = OutlineNodeMetadata()
        metadata.status = WritingProjectDisk.wordCount(in: text) > 0 ? .drafting : .planned
        return OutlineNode(title: title, kind: kind, relativePath: path, metadata: metadata)
    }
}

enum OutlineTree {
    static func flattened(_ nodes: [OutlineNode], depth: Int = 0, parentID: UUID? = nil) -> [OutlineFlatRow] {
        nodes.flatMap { node in
            [OutlineFlatRow(node: node, depth: depth, parentID: parentID)]
                + flattened(node.children, depth: depth + 1, parentID: node.id)
        }
    }

    static func node(id: UUID, in nodes: [OutlineNode]) -> OutlineNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = self.node(id: id, in: node.children) { return match }
        }
        return nil
    }

    static func parentID(of id: UUID, in nodes: [OutlineNode], parentID: UUID? = nil) -> UUID? {
        for node in nodes {
            if node.id == id { return parentID }
            if let result = self.parentID(of: id, in: node.children, parentID: node.id) { return result }
        }
        return nil
    }

    static func children(of parentID: UUID?, in nodes: [OutlineNode]) -> [OutlineNode] {
        guard let parentID else { return nodes }
        return node(id: parentID, in: nodes)?.children ?? []
    }

    static func filePaths(in nodes: [OutlineNode]) -> [String] {
        nodes.flatMap { node in
            (node.relativePath.map { [$0] } ?? []) + filePaths(in: node.children)
        }
    }

    static func ancestry(to id: UUID, in nodes: [OutlineNode]) -> [OutlineNode] {
        for node in nodes {
            if node.id == id { return [node] }
            let childPath = ancestry(to: id, in: node.children)
            if !childPath.isEmpty { return [node] + childPath }
        }
        return []
    }

    static func update(_ updated: OutlineNode, in nodes: inout [OutlineNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == updated.id {
                nodes[index] = updated
                return true
            }
            if update(updated, in: &nodes[index].children) { return true }
        }
        return false
    }

    static func updatePath(nodeID: UUID, path: String, in nodes: inout [OutlineNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == nodeID {
                nodes[index].relativePath = path
                nodes[index].metadata.modifiedAt = Date()
                return true
            }
            if updatePath(nodeID: nodeID, path: path, in: &nodes[index].children) { return true }
        }
        return false
    }

    static func append(_ node: OutlineNode, to parentID: UUID?, in nodes: inout [OutlineNode]) -> Bool {
        guard canPlace(node.kind, under: parentID.flatMap { self.node(id: $0, in: nodes)?.kind }) else {
            return false
        }
        guard let parentID else {
            nodes.append(node)
            return true
        }
        return mutateNode(id: parentID, in: &nodes) { parent in
            parent.children.append(node)
        }
    }

    static func move(nodeID: UUID, onto targetID: UUID, in nodes: inout [OutlineNode]) -> Bool {
        guard nodeID != targetID,
              let original = location(of: nodeID, in: nodes),
              let moving = remove(id: nodeID, from: &nodes) else { return false }

        guard let target = node(id: targetID, in: nodes) else {
            insert(moving, at: original, in: &nodes)
            return false
        }

        if target.kind.isContainer, canPlace(moving.kind, under: target.kind) {
            let inserted = mutateNode(id: target.id, in: &nodes) { $0.children.append(moving) }
            if inserted { return true }
        } else if let targetLocation = location(of: targetID, in: nodes),
                  canPlace(moving.kind, under: targetLocation.parentID.flatMap({ node(id: $0, in: nodes)?.kind })) {
            var destination = targetLocation
            destination.index = targetLocation.index
            insert(moving, at: destination, in: &nodes)
            return true
        }

        insert(moving, at: original, in: &nodes)
        return false
    }

    static func move(nodeID: UUID, toParent parentID: UUID?, in nodes: inout [OutlineNode]) -> Bool {
        guard let original = location(of: nodeID, in: nodes),
              let moving = remove(id: nodeID, from: &nodes) else { return false }
        let parentKind = parentID.flatMap { node(id: $0, in: nodes)?.kind }
        guard canPlace(moving.kind, under: parentKind), append(moving, to: parentID, in: &nodes) else {
            insert(moving, at: original, in: &nodes)
            return false
        }
        return true
    }

    static func canPlace(_ child: OutlineNodeKind, under parent: OutlineNodeKind?) -> Bool {
        switch parent {
        case nil: child == .part || child == .chapter
        case .part: child == .chapter
        case .chapter: child == .scene || child == .section
        case .scene, .section: false
        }
    }

    private struct Location {
        let parentID: UUID?
        var index: Int
    }

    private static func location(of id: UUID, in nodes: [OutlineNode], parentID: UUID? = nil) -> Location? {
        for (index, node) in nodes.enumerated() {
            if node.id == id { return Location(parentID: parentID, index: index) }
            if let result = location(of: id, in: node.children, parentID: node.id) { return result }
        }
        return nil
    }

    private static func remove(id: UUID, from nodes: inout [OutlineNode]) -> OutlineNode? {
        for index in nodes.indices {
            if nodes[index].id == id { return nodes.remove(at: index) }
            if let result = remove(id: id, from: &nodes[index].children) { return result }
        }
        return nil
    }

    private static func insert(_ node: OutlineNode, at location: Location, in nodes: inout [OutlineNode]) {
        if let parentID = location.parentID {
            _ = mutateNode(id: parentID, in: &nodes) { parent in
                parent.children.insert(node, at: min(location.index, parent.children.count))
            }
        } else {
            nodes.insert(node, at: min(location.index, nodes.count))
        }
    }

    private static func mutateNode(
        id: UUID,
        in nodes: inout [OutlineNode],
        mutation: (inout OutlineNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                mutation(&nodes[index])
                return true
            }
            if mutateNode(id: id, in: &nodes[index].children, mutation: mutation) { return true }
        }
        return false
    }
}

enum OutlineSynopsisGenerator {
    static func suggest(from markdown: String, maximumCharacters: Int = 420) -> String {
        let prose = markdown.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: " ")
        let sentences = ReferenceTextTools.sentences(in: prose)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ReferenceTextTools.words(in: $0).count >= 4 }
        guard !sentences.isEmpty else { return "" }

        let keywords = Set(ReferenceTextTools.significantWords(in: prose).prefix(18))
        let scored = sentences.enumerated().map { index, sentence in
            let matches = ReferenceTextTools.words(in: sentence)
                .map { $0.lowercased() }
                .filter(keywords.contains)
                .count
            let positionBonus = index == 0 ? 3 : index == sentences.count - 1 ? 1 : 0
            return (index, sentence, matches + positionBonus)
        }
        let selected = scored
            .sorted { lhs, rhs in lhs.2 == rhs.2 ? lhs.0 < rhs.0 : lhs.2 > rhs.2 }
            .prefix(min(3, sentences.count))
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        let result = selected.joined(separator: " ")
        return result.count <= maximumCharacters
            ? result
            : String(result.prefix(maximumCharacters)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

enum HeadingSplitPlanner {
    private struct HeadingMatch {
        let location: Int
        let title: String
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}##[\t ]+(.+?)(?:[\t ]+#+)?[\t ]*$"#
    )

    static func plan(node: OutlineNode, markdown: String) throws -> HeadingSplitPlan {
        guard let chapterPath = node.relativePath else { throw ProjectOutlineError.nodeHasNoFile }
        let source = markdown as NSString
        let matches = headingMatches(in: markdown)
        guard !matches.isEmpty else { throw ProjectOutlineError.noHeadings }

        let remaining = source.substring(with: NSRange(location: 0, length: matches[0].location))
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        var sections: [HeadingSplitSection] = []
        var usedNames: Set<String> = []

        for (index, match) in matches.enumerated() {
            let title = match.title
            let end = index + 1 < matches.count ? matches[index + 1].location : source.length
            let sectionRange = NSRange(location: match.location, length: end - match.location)
            let body = source.substring(with: sectionRange)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            let base = safeFileComponent(title)
            var candidate = "\(base).md"
            var suffix = 2
            while usedNames.contains(candidate.lowercased()) {
                candidate = "\(base) \(suffix).md"
                suffix += 1
            }
            usedNames.insert(candidate.lowercased())
            sections.append(HeadingSplitSection(title: title, markdown: body, fileName: candidate))
        }
        return HeadingSplitPlan(
            nodeID: node.id,
            chapterPath: chapterPath,
            remainingMarkdown: remaining,
            sections: sections
        )
    }

    private static func headingMatches(in markdown: String) -> [HeadingMatch] {
        var result: [HeadingMatch] = []
        var fence: (character: Character, length: Int)?

        markdown.enumerateSubstrings(
            in: markdown.startIndex..<markdown.endIndex,
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = String(markdown[lineRange])
            if let marker = fenceMarker(in: line) {
                if let openFence = fence {
                    if marker.character == openFence.character,
                       marker.length >= openFence.length,
                       marker.hasOnlyTrailingWhitespace {
                        fence = nil
                    }
                } else {
                    fence = (marker.character, marker.length)
                }
                return
            }
            guard fence == nil else { return }

            let localRange = NSRange(location: 0, length: (line as NSString).length)
            guard let match = headingRegex.firstMatch(in: line, range: localRange) else { return }
            let globalRange = NSRange(lineRange, in: markdown)
            let title = (line as NSString).substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(HeadingMatch(location: globalRange.location, title: title))
        }
        return result
    }

    private static func fenceMarker(
        in line: String
    ) -> (character: Character, length: Int, hasOnlyTrailingWhitespace: Bool)? {
        let withoutIndent = line.drop(while: { $0 == " " }).count >= line.count - 3
            ? line.drop(while: { $0 == " " })
            : line[...]
        guard let character = withoutIndent.first, character == "`" || character == "~" else { return nil }
        let length = withoutIndent.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let remainder = withoutIndent.dropFirst(length)
        return (character, length, remainder.allSatisfy(\.isWhitespace))
    }

    static func safeFileComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let pieces = value.components(separatedBy: invalid)
        let cleaned = pieces.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Untitled" : String(cleaned.prefix(120))
    }
}

enum ProjectFileOrganizer {
    static func plan(nodes: [OutlineNode], at root: URL) -> OutlineFileOrganizationPlan {
        var moves: [OutlineFileMove] = []
        collectMoves(nodes, parentFolders: [], into: &moves)
        return validate(OutlineFileOrganizationPlan(moves: moves), at: root)
    }

    static func validate(_ plan: OutlineFileOrganizationPlan, at root: URL) -> OutlineFileOrganizationPlan {
        var result = plan
        var destinations: [String: Int] = [:]
        for index in result.moves.indices {
            result.moves[index].conflict = nil
            guard result.moves[index].isIncluded else { continue }
            let destination = result.moves[index].destinationPath
            if !isSafeMarkdownPath(destination) {
                result.moves[index].conflict = ProjectOutlineError.invalidDestination(destination).localizedDescription
                continue
            }
            let key = destination.lowercased()
            if let otherIndex = destinations[key] {
                result.moves[index].conflict = "Two outline items use this destination."
                result.moves[otherIndex].conflict = "Two outline items use this destination."
            } else {
                destinations[key] = index
            }
            let destinationURL = root.appendingPathComponent(destination)
            if destination != result.moves[index].sourcePath,
               FileManager.default.fileExists(atPath: destinationURL.path) {
                result.moves[index].conflict = ProjectOutlineError.fileConflict(destination).localizedDescription
            }
        }
        return result
    }

    static func execute(_ plan: OutlineFileOrganizationPlan, at root: URL) throws -> [OutlineFileMove] {
        let checked = validate(plan, at: root)
        guard !checked.hasConflicts else {
            throw ProjectOutlineError.fileConflict("one or more proposed destinations")
        }
        let moves = checked.includedMoves.filter { $0.sourcePath != $0.destinationPath }
        var completed: [OutlineFileMove] = []
        do {
            for move in moves {
                let source = root.appendingPathComponent(move.sourcePath)
                let destination = root.appendingPathComponent(move.destinationPath)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: source, to: destination)
                completed.append(move)
            }
            return completed
        } catch {
            for move in completed.reversed() {
                let source = root.appendingPathComponent(move.destinationPath)
                let destination = root.appendingPathComponent(move.sourcePath)
                try? FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.moveItem(at: source, to: destination)
            }
            throw error
        }
    }

    static func undo(_ moves: [OutlineFileMove], at root: URL) throws {
        for move in moves.reversed() {
            let source = root.appendingPathComponent(move.destinationPath)
            let destination = root.appendingPathComponent(move.sourcePath)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ProjectOutlineError.fileConflict(move.sourcePath)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    private static func collectMoves(
        _ nodes: [OutlineNode],
        parentFolders: [String],
        into moves: inout [OutlineFileMove]
    ) {
        for node in nodes {
            var nodeFolders = parentFolders
            if node.kind == .part || node.kind == .chapter {
                nodeFolders.append(HeadingSplitPlanner.safeFileComponent(node.title))
            }
            if let path = node.relativePath {
                let destination = (nodeFolders + [URL(fileURLWithPath: path).lastPathComponent])
                    .joined(separator: "/")
                moves.append(OutlineFileMove(
                    nodeID: node.id,
                    sourcePath: path,
                    destinationPath: destination,
                    isIncluded: path != destination
                ))
            }
            collectMoves(node.children, parentFolders: nodeFolders, into: &moves)
        }
    }

    private static func isSafeMarkdownPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              URL(fileURLWithPath: path).pathExtension.lowercased() == "md" else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              components.first != WritingProjectDisk.metadataDirectoryName else { return false }
        let reserved = [
            WritingProjectDisk.styleFileName,
            ManuscriptProjectDisk.reportFileName,
            ManuscriptProjectDisk.bibleFileName
        ]
        return !reserved.contains(components.last ?? "")
    }
}

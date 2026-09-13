import Foundation

/// A fully validated project assembled away from the live observable store.
/// Nothing in the editor changes until every required project component has
/// loaded successfully and the reconciled outline/manifest have been saved.
struct LoadedWritingProject {
    let rootURL: URL
    let migrationResult: ProjectMigrationResult
    let manifest: WritingProjectManifest
    let chapters: [ProjectChapter]
    let selectedChapterPath: String
    let text: String
    let outlineNodes: [OutlineNode]
    let styleText: String
    let styleDecisions: [ProjectStyleDecision]
    let snapshots: [ProjectSnapshot]
    let manuscriptReportText: String
    let bibleText: String
    let manuscriptCache: ManuscriptProjectCache
    let customBetaReaders: [BetaReaderProfile]
    let projectBibliography: ProjectBibliographyArchive
    let researchNotesText: String
    let revisionArchive: SystemicRevisionArchive
    let publicationArchive: PublicationArchive
}

enum WritingProjectLoader {
    static func load(at requestedRoot: URL) throws -> LoadedWritingProject {
        let root = requestedRoot.standardizedFileURL
        let migrationResult = try ProjectCompatibilityManager.prepareForOpen(at: root)
        let originalManifest = try WritingProjectDisk.loadManifest(at: root)

        try ManuscriptProjectDisk.prepare(
            at: root,
            projectName: originalManifest.name,
            kind: originalManifest.kind
        )
        try ProjectOutlineDisk.prepare(at: root, manifest: originalManifest)
        try ProjectResearchDisk.prepare(at: root, projectName: originalManifest.name)
        try SystemicRevisionDisk.prepare(at: root)
        try PublicationDisk.prepare(
            at: root,
            projectName: originalManifest.name,
            projectKind: originalManifest.kind
        )
        // .process scope only -- opening a project must never leave a permanent, system-wide font
        // registration behind on whichever Mac happens to open it.
        ProjectFontDisk.registerBundledFonts(at: root)

        let discoveredChapters = try WritingProjectDisk.loadChapters(
            at: root,
            manifest: originalManifest
        )
        let reconciledOutline = ProjectOutlineDisk.reconcile(
            try ProjectOutlineDisk.load(at: root),
            chapterPaths: discoveredChapters.map(\.relativePath),
            projectKind: originalManifest.kind,
            root: root
        )

        let discoveredPaths = discoveredChapters.map(\.relativePath)
        let knownPaths = Set(discoveredPaths)
        var orderedPaths = OutlineTree.filePaths(in: reconciledOutline.nodes)
            .filter(knownPaths.contains)
        orderedPaths.append(contentsOf: discoveredPaths.filter { !orderedPaths.contains($0) })

        guard let selectedPath = originalManifest.lastOpenedChapter
            .flatMap({ knownPaths.contains($0) ? $0 : nil })
            ?? orderedPaths.first else {
            throw WritingProjectError.noMarkdownFiles
        }

        var manifest = originalManifest
        manifest.chapterOrder = orderedPaths
        manifest.lastOpenedChapter = selectedPath
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        // Complete every read before committing either the reconciled metadata
        // or this value to WritingProjectStore. A corrupt late-loading file must
        // not leave the visible editor attached to a partially loaded project.
        let text = try WritingProjectDisk.readChapter(selectedPath, at: root)
        let styleText = try ProjectStyleManager.loadStyle(at: root)
        let styleDecisions = try ProjectStyleManager.loadDecisions(at: root)
        let snapshots = try WritingProjectDisk.loadSnapshots(at: root)
        let manuscriptReportText = try ManuscriptProjectDisk.loadReport(at: root)
        let bibleText = try ManuscriptProjectDisk.loadBible(at: root)
        let manuscriptCache = try ManuscriptProjectDisk.loadCache(at: root)
        let customBetaReaders = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)
        let projectBibliography = try ProjectResearchDisk.load(at: root)
        let researchNotesText = try String(
            contentsOf: ProjectResearchDisk.notesURL(at: root),
            encoding: .utf8
        )
        let revisionArchive = try SystemicRevisionDisk.load(at: root)
        let publicationArchive = try PublicationDisk.load(at: root)

        try ProjectOutlineDisk.save(reconciledOutline, at: root)
        try WritingProjectDisk.saveManifest(manifest, at: root)

        return LoadedWritingProject(
            rootURL: root,
            migrationResult: migrationResult,
            manifest: manifest,
            chapters: chapters,
            selectedChapterPath: selectedPath,
            text: text,
            outlineNodes: reconciledOutline.nodes,
            styleText: styleText,
            styleDecisions: styleDecisions,
            snapshots: snapshots,
            manuscriptReportText: manuscriptReportText,
            bibleText: bibleText,
            manuscriptCache: manuscriptCache,
            customBetaReaders: customBetaReaders,
            projectBibliography: projectBibliography,
            researchNotesText: researchNotesText,
            revisionArchive: revisionArchive,
            publicationArchive: publicationArchive
        )
    }
}

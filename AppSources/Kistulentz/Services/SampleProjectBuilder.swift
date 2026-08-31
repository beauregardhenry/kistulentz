import Foundation

enum SampleProjectBuilder {
    static func create(in parent: URL, kind: WritingProjectKind) throws -> URL {
        let baseName = kind == .fiction
            ? "Kistulentz Fiction Sample"
            : "Kistulentz Nonfiction Sample"
        let name = uniqueProjectName(baseName, in: parent)
        let root = try WritingProjectDisk.createProject(in: parent, name: name, kind: kind)

        let chapters = sampleChapters(for: kind)
        for chapter in chapters {
            try WritingProjectDisk.writeChapter(chapter.text, relativePath: chapter.path, at: root)
        }

        var manifest = try WritingProjectDisk.loadManifest(at: root)
        manifest.chapterOrder = chapters.map(\.path)
        manifest.lastOpenedChapter = chapters.first?.path
        try WritingProjectDisk.saveManifest(manifest, at: root)
        return root
    }

    private static func uniqueProjectName(_ base: String, in parent: URL) -> String {
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(
            atPath: parent.appendingPathComponent(candidate, isDirectory: true).path
        ) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func sampleChapters(for kind: WritingProjectKind) -> [(path: String, text: String)] {
        switch kind {
        case .fiction:
            return [
                (
                    "Chapter 1.md",
                    """
                    # The Signal House

                    Mara reached the abandoned signal house before the storm closed the road. A brass lantern waited on its shelf, cold and unexpectedly clean.

                    Someone had trimmed its wick since her last visit.
                    """
                ),
                (
                    "Chapter 2.md",
                    """
                    # The Second Light

                    At midnight, a second lantern answered from across the flooded valley. Mara wrote down the interval between flashes and found a sentence hidden in the pattern.

                    It used her name.
                    """
                )
            ]
        case .nonfiction:
            return [
                (
                    "Draft.md",
                    """
                    # Why Clear Systems Earn Trust

                    A dependable system tells people what it is doing, what it cannot do, and how to recover when something goes wrong. Clarity is part of the product, not decoration added later.

                    This sample demonstrates a short opening claim and a readable paragraph structure.
                    """
                ),
                (
                    "Evidence and Examples.md",
                    """
                    # Evidence and Examples

                    Strong nonfiction separates observation from inference. It names the evidence, explains the reasoning, and marks uncertainty when the available material does not support a firm conclusion.

                    Add sources and concrete examples here before publishing the argument.
                    """
                )
            ]
        }
    }
}

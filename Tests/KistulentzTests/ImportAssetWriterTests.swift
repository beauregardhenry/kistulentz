import XCTest
@testable import Kistulentz

final class ImportAssetWriterTests: XCTestCase {
    func testPlanSanitizesAndDeduplicatesProposedNamesCaseInsensitively() {
        let first = DocumentImportAsset(suggestedFilename: "diagram.png", altText: "One", data: Data([1]))
        let second = DocumentImportAsset(suggestedFilename: "diagram.png", altText: "Two", data: Data([2]))
        let third = DocumentImportAsset(suggestedFilename: "DIAGRAM.PNG", altText: "Three", data: Data([3]))
        let folder = URL(fileURLWithPath: "/tmp/Some Project-assets", isDirectory: true)

        let plan = ImportAssetWriter.plan(
            [
                (id: first.id, proposedName: "../Chapter One-diagram.png", asset: first),
                (id: second.id, proposedName: "Chapter One-diagram.png", asset: second),
                (id: third.id, proposedName: "Chapter One-DIAGRAM.PNG", asset: third)
            ],
            in: folder
        )

        let references = [plan.references[first.id], plan.references[second.id], plan.references[third.id]]
            .compactMap { $0 }
        XCTAssertEqual(references.count, 3, "Every asset should get its own reference.")
        XCTAssertEqual(Set(references.map { $0.lowercased() }).count, 3, "References must be unique, not just distinct by case.")
        XCTAssertTrue(references.allSatisfy { $0.hasPrefix("Some Project-assets/") })
        XCTAssertTrue(references.allSatisfy { !$0.contains("..") && !$0.contains("/../") })
    }

    func testWriteIsANoOpForAnEmptyPlanAndCreatesNothing() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("assets", isDirectory: true)
        let plan = ImportAssetWriter.plan([], in: folder)

        let created = try ImportAssetWriter.write(plan, to: folder)

        XCTAssertTrue(created.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testWriteCreatesTheFolderAndEveryFileReturningThemInWriteOrder() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("assets", isDirectory: true)
        let first = DocumentImportAsset(suggestedFilename: "one.png", altText: "One", data: Data([1]))
        let second = DocumentImportAsset(suggestedFilename: "two.png", altText: "Two", data: Data([2]))
        let plan = ImportAssetWriter.plan(
            [
                (id: first.id, proposedName: "one.png", asset: first),
                (id: second.id, proposedName: "two.png", asset: second)
            ],
            in: folder
        )

        let created = try ImportAssetWriter.write(plan, to: folder)

        XCTAssertEqual(created.first, folder)
        XCTAssertEqual(created.count, 3)
        for file in plan.files {
            XCTAssertTrue(created.contains(file.destination))
            XCTAssertEqual(try Data(contentsOf: file.destination), file.asset.data)
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ImportAssetWriter-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

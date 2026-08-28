import CryptoKit
import Foundation

enum PublicationExporter {
    static func preview(plan: PublicationExportPlan, root: URL) -> PublicationRenderedBook {
        PublicationRenderer(plan: plan, root: root).render()
    }

    static func export(
        plan: PublicationExportPlan,
        root: URL,
        outputDirectory: URL,
        allowingWarnings: Bool
    ) throws -> PublicationExportResult {
        let preflight = PublicationPreflight.run(plan: plan, root: root)
        guard preflight.errors.isEmpty else { throw PublicationExportError.preflightFailed }
        guard allowingWarnings || preflight.warnings.isEmpty else { throw PublicationExportError.warningConfirmationRequired }
        guard !plan.manuscriptItems.isEmpty else { throw PublicationExportError.noIncludedManuscript }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = uniqueOutputURL(plan: plan, directory: outputDirectory)
        let rendered = preview(plan: plan, root: root)
        do {
            switch plan.format {
            case .epub:
                try EPUBPublicationWriter.write(rendered, to: outputURL, root: root)
            case .printPDF, .readerPDF:
                try PDFPublicationWriter.write(rendered, to: outputURL, root: root)
            case .docx:
                try DOCXPublicationWriter.write(rendered, to: outputURL, root: root)
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        let values = try outputValues(at: outputURL)
        return PublicationExportResult(
            outputURL: outputURL,
            sha256: values.sha256,
            byteCount: values.byteCount,
            preflight: preflight
        )
    }

    static func outputValues(at url: URL) throws -> (sha256: String, byteCount: Int64) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (digest, Int64(data.count))
    }

    private static func uniqueOutputURL(plan: PublicationExportPlan, directory: URL) -> URL {
        let base = HeadingSplitPlanner.safeFileComponent(plan.metadata.title.isEmpty ? plan.projectName : plan.metadata.title)
        let qualifier: String
        switch plan.format {
        case .printPDF: qualifier = "-print-interior"
        case .readerPDF: qualifier = "-reader"
        default: qualifier = ""
        }
        let proposed = "\(base)\(qualifier).\(plan.format.fileExtension)"
        var result = directory.appendingPathComponent(proposed)
        var copy = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = directory.appendingPathComponent("\(base)\(qualifier)-\(copy).\(plan.format.fileExtension)")
            copy += 1
        }
        return result
    }
}

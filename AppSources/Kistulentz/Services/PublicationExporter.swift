import CryptoKit
import Foundation
import PDFKit

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
        let packageURL = uniquePackageURL(plan: plan, directory: outputDirectory)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: false)
        let outputURL = uniqueOutputURL(plan: plan, directory: packageURL)
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
            try? FileManager.default.removeItem(at: packageURL)
            throw error
        }
        let values = try outputValues(at: outputURL)
        let validatorRuns = PublicationExternalValidation.evaluate(plan: plan, outputURL: outputURL)
        let completedPreflight = postflight(
            preflight,
            plan: plan,
            outputURL: outputURL,
            byteCount: values.byteCount,
            validatorRuns: validatorRuns
        )
        let package: PublicationPackageURLs
        do {
            package = try PublicationPackageWriter.finish(
                packageURL: packageURL,
                primaryURL: outputURL,
                plan: plan,
                root: root,
                sha256: values.sha256,
                byteCount: values.byteCount,
                report: completedPreflight,
                validatorRuns: validatorRuns
            )
        } catch {
            try? FileManager.default.removeItem(at: packageURL)
            throw error
        }
        return PublicationExportResult(
            outputURL: outputURL,
            sha256: values.sha256,
            byteCount: values.byteCount,
            preflight: completedPreflight,
            packageURL: package.package,
            reportMarkdownURL: package.reportMarkdown,
            reportPDFURL: package.reportPDF,
            validatorRuns: validatorRuns
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

    private static func uniquePackageURL(plan: PublicationExportPlan, directory: URL) -> URL {
        let base = HeadingSplitPlanner.safeFileComponent(plan.metadata.title.isEmpty ? plan.projectName : plan.metadata.title)
        var result = directory.appendingPathComponent("\(base)-submission", isDirectory: true)
        var copy = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = directory.appendingPathComponent("\(base)-submission-\(copy)", isDirectory: true)
            copy += 1
        }
        return result
    }

    private static func postflight(
        _ preflight: PublicationPreflightReport,
        plan: PublicationExportPlan,
        outputURL: URL,
        byteCount: Int64,
        validatorRuns: [PublicationValidatorRun]
    ) -> PublicationPreflightReport {
        var findings = preflight.findings
        findings.append(PublicationPreflightFinding(
            id: "output-created",
            severity: .information,
            title: "Publication file was created and checksummed",
            detail: "Kistulentz verified that the exported file can be read and recorded its SHA-256 checksum.",
            sourcePath: outputURL.lastPathComponent,
            readinessStatus: .passedLocally
        ))
        if plan.format == .epub,
           plan.destinations.contains(.ingramSparkEbook),
           byteCount > 100_000_000 {
            findings.append(PublicationPreflightFinding(
                id: "ingram-epub-size",
                severity: .warning,
                title: "EPUB exceeds IngramSpark's documented 100 MB limit",
                detail: "Reduce image or embedded-asset size before submission.",
                sourcePath: outputURL.lastPathComponent,
                readinessStatus: .actionRequired,
                requirementURL: PublicationDestination.ingramSparkEbook.requirementURL
            ))
        }
        if plan.format == .printPDF, let document = PDFDocument(url: outputURL) {
            let pages = document.pageCount
            findings.append(PublicationPreflightFinding(
                id: "print-page-count",
                severity: .information,
                title: "Final interior contains \(pages) pages",
                detail: "Use this count when selecting a cover template and confirming the retailer's gutter bracket.",
                sourcePath: outputURL.lastPathComponent,
                readinessStatus: .passedLocally
            ))
            if plan.destinations.contains(.kdpPrint) {
                let required = kdpInsideMargin(pageCount: pages)
                if plan.profile.layout.insideMargin < required {
                    findings.append(PublicationPreflightFinding(
                        id: "kdp-final-gutter",
                        severity: .warning,
                        title: "Inside gutter is too small for the final KDP page count",
                        detail: "\(pages) pages require at least \(required / 72) inches; this profile uses \(plan.profile.layout.insideMargin / 72) inches.",
                        readinessStatus: .actionRequired,
                        requirementURL: "https://kdp.amazon.com/en_US/help/topic/GVBQ3CMEQW3W2VL6"
                    ))
                } else {
                    findings.append(PublicationPreflightFinding(
                        id: "kdp-final-gutter-pass",
                        severity: .information,
                        title: "Inside gutter meets the documented KDP page-count bracket",
                        detail: "The \(plan.profile.layout.insideMargin / 72)-inch gutter meets the minimum Kistulentz calculated for \(pages) pages.",
                        readinessStatus: .passedLocally,
                        requirementURL: "https://kdp.amazon.com/en_US/help/topic/GVBQ3CMEQW3W2VL6"
                    ))
                }
            }
        }
        for run in validatorRuns {
            switch run.status {
            case .passed:
                findings.append(PublicationPreflightFinding(
                    id: "validator-\(run.validator.rawValue)-pass",
                    severity: .information,
                    title: "\(run.validator.title) passed",
                    detail: run.summary,
                    readinessStatus: .passedLocally
                ))
            case .failed:
                findings.append(PublicationPreflightFinding(
                    id: "validator-\(run.validator.rawValue)-failure",
                    severity: .error,
                    title: "\(run.validator.title) reported problems",
                    detail: run.summary,
                    readinessStatus: .actionRequired
                ))
            case .available, .notInstalled:
                findings.append(PublicationPreflightFinding(
                    id: "validator-\(run.validator.rawValue)-status",
                    severity: .information,
                    title: run.validator.title,
                    detail: run.summary,
                    readinessStatus: run.status == .available ? .manualReviewRequired : .externalValidationRequired
                ))
            case .notApplicable:
                break
            }
        }
        return PublicationPreflightReport(findings: findings)
    }

    private static func kdpInsideMargin(pageCount: Int) -> Double {
        switch pageCount {
        case ...150: 27
        case ...300: 36
        case ...500: 45
        case ...700: 54
        default: 63
        }
    }
}

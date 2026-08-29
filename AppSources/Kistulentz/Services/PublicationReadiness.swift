import AppKit
import CoreText
import Foundation
import PDFKit

struct PublicationPackageURLs: Equatable {
    var package: URL
    var primary: URL
    var reportMarkdown: URL
    var reportPDF: URL
}

enum PublicationExternalValidation {
    static func evaluate(plan: PublicationExportPlan, outputURL: URL) -> [PublicationValidatorRun] {
        guard plan.format == .epub else { return [] }
        var runs: [PublicationValidatorRun] = [runEPUBCheck(on: outputURL)]
        if plan.destinations.contains(.kindleEbook) {
            runs.append(applicationStatus(
                validator: .kindlePreviewer,
                candidatePaths: [
                    "/Applications/Kindle Previewer 3.app",
                    "/Applications/Kindle Previewer.app",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Kindle Previewer 3.app").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Kindle Previewer.app").path
                ],
                availableSummary: "Kindle Previewer is installed. Open the exported EPUB there for visual review.",
                missingSummary: "Kindle Previewer was not found. Visual Kindle review remains outstanding."
            ))
        }
        if plan.destinations.contains(.appleBooks) {
            runs.append(applicationStatus(
                validator: .appleTransporter,
                candidatePaths: [
                    "/Applications/Transporter.app",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Transporter.app").path
                ],
                availableSummary: "Apple Transporter is installed. Apple Books delivery validation remains required.",
                missingSummary: "Apple Transporter was not found. Apple Books delivery validation remains outstanding."
            ))
        }
        return runs
    }

    private static func runEPUBCheck(on outputURL: URL) -> PublicationValidatorRun {
        guard let executable = epubCheckExecutable() else {
            return PublicationValidatorRun(
                validator: .epubCheck,
                status: .notInstalled,
                summary: "EPUBCheck was not found. External EPUB conformance validation remains outstanding.",
                output: ""
            )
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = [outputURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let trimmed = String(output.prefix(40_000)).trimmingCharacters(in: .whitespacesAndNewlines)
            let passed = process.terminationStatus == 0
            return PublicationValidatorRun(
                validator: .epubCheck,
                status: passed ? .passed : .failed,
                summary: passed ? "EPUBCheck passed." : "EPUBCheck reported conformance problems.",
                output: trimmed
            )
        } catch {
            return PublicationValidatorRun(
                validator: .epubCheck,
                status: .failed,
                summary: "EPUBCheck could not be launched.",
                output: error.localizedDescription
            )
        }
    }

    private static func epubCheckExecutable() -> URL? {
        var candidates = ["/opt/homebrew/bin/epubcheck", "/usr/local/bin/epubcheck"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/epubcheck" })
        }
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func applicationStatus(
        validator: PublicationExternalValidator,
        candidatePaths: [String],
        availableSummary: String,
        missingSummary: String
    ) -> PublicationValidatorRun {
        let installed = candidatePaths.contains { FileManager.default.fileExists(atPath: $0) }
        return PublicationValidatorRun(
            validator: validator,
            status: installed ? .available : .notInstalled,
            summary: installed ? availableSummary : missingSummary,
            output: ""
        )
    }
}

enum PublicationReadinessReportWriter {
    static func markdown(
        plan: PublicationExportPlan,
        resultURL: URL,
        sha256: String,
        byteCount: Int64,
        report: PublicationPreflightReport,
        validatorRuns: [PublicationValidatorRun],
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let destinationText = plan.destinations.isEmpty
            ? "No destination selected"
            : plan.destinations.map(\.title).joined(separator: ", ")
        let outcome: String
        if !report.errors.isEmpty {
            outcome = "Action required before submission"
        } else if validatorRuns.contains(where: { $0.status == .failed }) {
            outcome = "External validation reported problems"
        } else if validatorRuns.contains(where: { $0.status == .notInstalled }) ||
                    report.findings.contains(where: { $0.readinessStatus == .externalValidationRequired }) {
            outcome = "Local checks passed; external validation remains"
        } else {
            outcome = "Local checks passed; complete the listed manual review"
        }

        var text = """
        # Kistulentz Submission Readiness Report

        - Publication: \(plan.metadata.title.isEmpty ? plan.projectName : plan.metadata.title)
        - Format: \(plan.format.title)
        - Destinations: \(destinationText)
        - Generated: \(formatter.string(from: generatedAt))
        - Outcome: \(outcome)

        This report records checks Kistulentz performed locally. It is not retailer certification and does not guarantee acceptance.

        ## Exported Publication

        - File: \(resultURL.lastPathComponent)
        - Size: \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        - SHA-256: `\(sha256)`

        ## Status Guide

        - Passed Locally: Kistulentz directly verified the stated condition.
        - Action Required: A local check found a problem or an author decision is needed.
        - External Validation Required: Another current tool or retailer upload must verify the result.
        - Manual Review Required: A person must inspect something automation cannot judge reliably.

        """

        let orderedStatuses: [PublicationReadinessStatus] = [
            .actionRequired, .passedLocally, .externalValidationRequired, .manualReviewRequired
        ]
        for status in orderedStatuses {
            let matches = report.findings.filter { $0.readinessStatus == status }
            guard !matches.isEmpty else { continue }
            text += "## \(status.title)\n\n"
            for finding in matches {
                text += "### \(finding.title)\n\n"
                text += "\(finding.detail)\n"
                if let path = finding.sourcePath { text += "\nFile: `\(URL(fileURLWithPath: path).lastPathComponent)`\n" }
                if let url = finding.requirementURL { text += "\nRequirement: \(url)\n" }
                text += "\n"
            }
        }

        if !validatorRuns.isEmpty {
            text += "## External Validator Results\n\n"
            for run in validatorRuns {
                text += "### \(run.validator.title) — \(validatorStatus(run.status))\n\n\(run.summary)\n\n"
                if !run.output.isEmpty {
                    text += "Detailed validator output is intentionally omitted from this shareable report because external tools may echo publication content.\n\n"
                }
            }
        }

        text += """
        ## Privacy and Scope

        This report contains filenames, publication settings, checks, validator output, and checksums. It intentionally contains no manuscript prose or excerpts. All checks and report generation ran locally on this Mac.

        ## Requirements Consulted

        """
        for destination in plan.destinations {
            text += "- \(destination.title): \(destination.requirementURL)\n"
        }
        if plan.format == .epub {
            text += "- EPUB Accessibility 1.1: https://www.w3.org/TR/epub-a11y-11/\n"
            text += "- EPUBCheck: https://github.com/w3c/epubcheck\n"
        }
        return text + "\n"
    }

    static func writePDF(markdown: String, to outputURL: URL) throws {
        let plain = markdown
            .replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "```text\n", with: "")
            .replacingOccurrences(of: "```\n", with: "")
            .replacingOccurrences(of: "`", with: "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5),
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: plain, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let pageSize = CGSize(width: 612, height: 792)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PublicationExportError.outputCreationFailed("The readiness-report PDF could not be created.")
        }
        let pageRect = CGRect(x: 54, y: 54, width: pageSize.width - 108, height: pageSize.height - 108)
        var location = 0
        while location < attributed.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: pageRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                context.endPDFPage()
                context.closePDF()
                throw PublicationExportError.outputCreationFailed("The readiness report could not be paginated.")
            }
            location += visible.length
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func validatorStatus(_ status: PublicationValidatorRunStatus) -> String {
        switch status {
        case .passed: "Passed"
        case .failed: "Failed"
        case .available: "Installed; manual use required"
        case .notInstalled: "Not installed"
        case .notApplicable: "Not applicable"
        }
    }
}

enum PublicationPackageWriter {
    private struct Manifest: Codable {
        var schemaVersion = 1
        var generatedAt: Date
        var applicationVersion: String
        var publicationTitle: String
        var format: PublicationExportFormat
        var destinations: [PublicationDestination]
        var primaryFile: String
        var primarySHA256: String
        var primaryByteCount: Int64
        var manuscriptTextIncluded: Bool
        var validators: [ValidatorSummary]
    }

    private struct ValidatorSummary: Codable {
        var name: String
        var status: PublicationValidatorRunStatus
        var summary: String
    }

    static func finish(
        packageURL: URL,
        primaryURL: URL,
        plan: PublicationExportPlan,
        root: URL,
        sha256: String,
        byteCount: Int64,
        report: PublicationPreflightReport,
        validatorRuns: [PublicationValidatorRun]
    ) throws -> PublicationPackageURLs {
        let reportMarkdownURL = packageURL.appendingPathComponent("Submission Readiness Report.md")
        let reportPDFURL = packageURL.appendingPathComponent("Submission Readiness Report.pdf")
        try copySeparateCover(plan: plan, root: root, packageURL: packageURL)
        let markdown = PublicationReadinessReportWriter.markdown(
            plan: plan,
            resultURL: primaryURL,
            sha256: sha256,
            byteCount: byteCount,
            report: report,
            validatorRuns: validatorRuns
        )
        try markdown.write(to: reportMarkdownURL, atomically: true, encoding: .utf8)
        try PublicationReadinessReportWriter.writePDF(markdown: markdown, to: reportPDFURL)

        let manifest = Manifest(
            generatedAt: Date(),
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            publicationTitle: plan.metadata.title.isEmpty ? plan.projectName : plan.metadata.title,
            format: plan.format,
            destinations: plan.destinations,
            primaryFile: primaryURL.lastPathComponent,
            primarySHA256: sha256,
            primaryByteCount: byteCount,
            manuscriptTextIncluded: false,
            validators: validatorRuns.map { ValidatorSummary(name: $0.validator.title, status: $0.status, summary: $0.summary) }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: packageURL.appendingPathComponent("package-manifest.json"), options: .atomic)
        try writeChecksums(in: packageURL)
        return PublicationPackageURLs(
            package: packageURL,
            primary: primaryURL,
            reportMarkdown: reportMarkdownURL,
            reportPDF: reportPDFURL
        )
    }

    private static func copySeparateCover(plan: PublicationExportPlan, root: URL, packageURL: URL) throws {
        let relativePath = plan.format == .printPDF
            ? plan.metadata.printCoverPDFRelativePath
            : plan.metadata.coverImageRelativePath
        guard let source = PublicationDisk.resolveAsset(relativePath, at: root),
              FileManager.default.fileExists(atPath: source.path) else { return }
        let title = HeadingSplitPlanner.safeFileComponent(plan.metadata.title.isEmpty ? plan.projectName : plan.metadata.title)
        let qualifier = plan.format == .printPDF ? "print-cover" : "ebook-cover"
        let destination = packageURL.appendingPathComponent("\(title)-\(qualifier).\(source.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func writeChecksums(in packageURL: URL) throws {
        let checksumURL = packageURL.appendingPathComponent("SHA256SUMS.txt")
        let files = try FileManager.default.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0 != checksumURL && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let lines = try files.map { file -> String in
            let values = try PublicationExporter.outputValues(at: file)
            return "\(values.sha256)  \(file.lastPathComponent)"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: checksumURL, atomically: true, encoding: .utf8)
    }
}

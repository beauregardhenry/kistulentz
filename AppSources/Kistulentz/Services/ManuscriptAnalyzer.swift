import Foundation

enum ManuscriptAnalyzer {
    static func analyze(
        projectName: String,
        kind: WritingProjectKind,
        documents: [ManuscriptDocument]
    ) -> ManuscriptAnalysis {
        let metrics = ManuscriptMetricsAnalyzer.analyze(documents: documents)
        let continuity = ManuscriptContinuityAnalyzer.analyze(
            documents: documents,
            chapters: metrics.chapters
        )

        var result = ManuscriptAnalysis(
            projectName: projectName,
            kind: kind,
            chapters: metrics.chapters,
            entities: continuity.entities,
            keyTerms: continuity.keyTerms,
            repeatedPhrases: continuity.repeatedPhrases,
            timelineMarkers: continuity.timelineMarkers,
            claimChecks: continuity.claimChecks,
            continuityChecks: continuity.continuityChecks,
            totalWords: metrics.totalWords,
            totalSentences: metrics.totalSentences,
            overallGrade: metrics.overallGrade,
            averageSentenceWords: metrics.averageSentenceWords,
            averageParagraphWords: metrics.averageParagraphWords,
            dialogueRatio: metrics.dialogueRatio,
            citationCount: metrics.citationCount,
            adverbCount: metrics.adverbCount,
            passiveVoiceCount: metrics.passiveVoiceCount,
            structuralProfile: nil,
            reportMarkdown: "",
            generatedBibleBlock: ""
        )
        result.reportMarkdown = ManuscriptReportRenderer.renderReport(result)
        result.generatedBibleBlock = ManuscriptReportRenderer.renderBibleBlock(result)
        return result
    }

    static func addingStructuralProfile(
        _ structuralProfile: StructuralProfile,
        to analysis: ManuscriptAnalysis
    ) -> ManuscriptAnalysis {
        var enriched = ManuscriptAnalysis(
            projectName: analysis.projectName,
            kind: analysis.kind,
            chapters: analysis.chapters,
            entities: analysis.entities,
            keyTerms: analysis.keyTerms,
            repeatedPhrases: analysis.repeatedPhrases,
            timelineMarkers: analysis.timelineMarkers,
            claimChecks: analysis.claimChecks,
            continuityChecks: analysis.continuityChecks,
            totalWords: analysis.totalWords,
            totalSentences: analysis.totalSentences,
            overallGrade: analysis.overallGrade,
            averageSentenceWords: analysis.averageSentenceWords,
            averageParagraphWords: analysis.averageParagraphWords,
            dialogueRatio: analysis.dialogueRatio,
            citationCount: analysis.citationCount,
            adverbCount: analysis.adverbCount,
            passiveVoiceCount: analysis.passiveVoiceCount,
            structuralProfile: structuralProfile,
            reportMarkdown: analysis.reportMarkdown,
            generatedBibleBlock: analysis.generatedBibleBlock
        )
        enriched.reportMarkdown = ManuscriptReportRenderer.renderReport(enriched)
        return enriched
    }

    static func context(
        documents: [ManuscriptDocument],
        report: String,
        bible: String,
        maximumCharacters: Int = 80_000
    ) -> String {
        var remaining = max(8_000, maximumCharacters)
        var sections: [String] = []

        func append(label: String, text: String, maximum: Int) {
            guard remaining > 500 else { return }
            let allowance = min(maximum, remaining)
            let excerpt = sampledText(text, limit: allowance)
            let section = "<\(label)>\n\(excerpt)\n</\(label)>"
            sections.append(section)
            remaining -= section.count
        }

        append(label: "local_manuscript_report", text: report, maximum: 18_000)
        append(label: "project_bible", text: bible, maximum: 18_000)

        let selected = evenlySampled(documents, limit: min(documents.count, 60))
        let perDocument = max(700, min(4_500, remaining / max(selected.count, 1)))
        for document in selected where remaining > 500 {
            let excerpt = sampledText(document.text, limit: min(perDocument, remaining))
            let section = """
            <manuscript_section path="\(document.relativePath)" title="\(document.title)">
            \(excerpt)
            </manuscript_section>
            """
            sections.append(section)
            remaining -= section.count
        }
        return sections.joined(separator: "\n\n")
    }

    private static func sampledText(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 200 else { return text }
        let part = max(60, limit / 3)
        let start = String(text.prefix(part))
        let middleStart = text.index(text.startIndex, offsetBy: max(0, text.count / 2 - part / 2))
        let middle = String(text[middleStart...].prefix(part))
        let end = String(text.suffix(part))
        return "\(start)\n\n[…middle excerpt…]\n\n\(middle)\n\n[…ending excerpt…]\n\n\(end)"
    }

    private static func evenlySampled<T>(_ values: [T], limit: Int) -> [T] {
        guard values.count > limit, limit > 0 else { return values }
        return (0..<limit).map { values[$0 * values.count / limit] }
    }
}

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
            let opening = "<\(label)>\n"
            let closing = "\n</\(label)>"
            let wrapperCount = opening.count + closing.count + (sections.isEmpty ? 0 : 2)
            guard remaining > wrapperCount else { return }
            let allowance = min(maximum, remaining - wrapperCount)
            let excerpt = sampledText(text, limit: allowance)
            let section = "\(opening)\(excerpt)\(closing)"
            sections.append(section)
            remaining -= section.count + (sections.count == 1 ? 0 : 2)
        }

        append(label: "local_manuscript_report", text: report, maximum: 18_000)
        append(label: "project_bible", text: bible, maximum: 18_000)

        let selected = evenlySampled(documents, limit: min(documents.count, 60))
        let wrappers = selected.map { document in
            (
                opening: "<manuscript_section path=\"\(document.relativePath)\" title=\"\(document.title)\">\n",
                closing: "\n</manuscript_section>"
            )
        }
        let wrapperCharacters = wrappers.reduce(0) { $0 + $1.opening.count + $1.closing.count }
            + selected.count * 2
        guard !selected.isEmpty, wrapperCharacters <= remaining else {
            return sections.joined(separator: "\n\n")
        }
        // Reserve the tag overhead up front so every evenly sampled section—including the ending—
        // remains represented and the context cannot silently run over its requested budget.
        let perDocument = min(4_500, (remaining - wrapperCharacters) / selected.count)
        for (document, wrapper) in zip(selected, wrappers) {
            let excerpt = sampledText(document.text, limit: perDocument)
            let section = "\(wrapper.opening)\(excerpt)\(wrapper.closing)"
            sections.append(section)
            remaining -= section.count + 2
        }
        return sections.joined(separator: "\n\n")
    }

    private static func sampledText(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return limit > 0 ? text : "" }
        let middleMarker = "\n\n[…middle excerpt…]\n\n"
        let endingMarker = "\n\n[…ending excerpt…]\n\n"
        let markerCount = middleMarker.count + endingMarker.count
        guard limit > markerCount + 3 else { return String(text.prefix(limit)) }

        let available = limit - markerCount
        let startCount = available / 3
        let middleCount = available / 3
        let endCount = available - startCount - middleCount
        let start = String(text.prefix(startCount))
        let middleStart = text.index(text.startIndex, offsetBy: max(0, text.count / 2 - middleCount / 2))
        let middle = String(text[middleStart...].prefix(middleCount))
        let end = String(text.suffix(endCount))
        return "\(start)\(middleMarker)\(middle)\(endingMarker)\(end)"
    }

    private static func evenlySampled<T>(_ values: [T], limit: Int) -> [T] {
        guard values.count > limit, limit > 0 else { return values }
        guard limit > 1 else { return [values[0]] }
        // Include both endpoints. The earlier `index * count / limit` distribution never selected
        // the final section, which could leave an AI review blind to the manuscript's ending.
        return (0..<limit).map { values[$0 * (values.count - 1) / (limit - 1)] }
    }
}

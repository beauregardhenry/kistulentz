import Foundation

enum ManuscriptReportRenderer {
    static func renderReport(_ analysis: ManuscriptAnalysis) -> String {
        let averageChapter = analysis.chapters.isEmpty
            ? 0
            : Double(analysis.totalWords) / Double(analysis.chapters.count)
        let shortest = analysis.chapters.min(by: { $0.wordCount < $1.wordCount })
        let longest = analysis.chapters.max(by: { $0.wordCount < $1.wordCount })
        let gradeValues = analysis.chapters.map(\.gradeLevel)
        let gradeRange = (gradeValues.min() ?? 0, gradeValues.max() ?? 0)
        let dialoguePercent = Int((analysis.dialogueRatio * 100).rounded())

        var lines: [String] = [
            "## Overview",
            "",
            "- **Project type:** \(analysis.kind.title)",
            "- **Chapters or sections:** \(analysis.chapters.count)",
            "- **Words:** \(analysis.totalWords.formatted())",
            "- **Estimated reading time:** \(analysis.totalWords == 0 ? 0 : max(1, Int(ceil(Double(analysis.totalWords) / 225.0)))) minutes",
            "- **Reading grade:** \(format(analysis.overallGrade))",
            "- **Named entities tracked:** \(analysis.entities.count)",
            "",
            "## Structure",
            "",
            "The manuscript uses \(analysis.chapters.count) ordered Markdown \(analysis.chapters.count == 1 ? "section" : "sections") with an average of \(Int(averageChapter.rounded()).formatted()) words each."
        ]

        if let shortest, let longest {
            lines.append("- Shortest: **\(shortest.title)** — \(shortest.wordCount.formatted()) words")
            lines.append("- Longest: **\(longest.title)** — \(longest.wordCount.formatted()) words")
        }
        let empty = analysis.chapters.filter { $0.wordCount < 25 }
        if !empty.isEmpty {
            lines.append("- Check very short sections: \(empty.prefix(8).map { "**\($0.title)**" }.joined(separator: ", "))")
        }
        let headingless = analysis.chapters.filter { $0.headingCount == 0 }
        if !headingless.isEmpty {
            lines.append("- \(headingless.count) section\(headingless.count == 1 ? " has" : "s have") no Markdown heading.")
        }

        lines += [
            "",
            "## Pacing",
            "",
            "- Average sentence length: **\(format(analysis.averageSentenceWords)) words**",
            "- Average paragraph length: **\(format(analysis.averageParagraphWords)) words**",
            "- Dialogue or quoted speech: **\(dialoguePercent)%** of words",
            pacingObservation(analysis),
            "",
            "## Continuity & Consistency",
            ""
        ]
        appendFindings(
            analysis.continuityChecks,
            empty: "No obvious cross-chapter naming or readability discontinuities were found by the local scan.",
            to: &lines
        )

        lines += ["", "## Characters & People", ""]
        appendEntities(
            analysis.entities.filter { $0.kind == .person },
            empty: "No recurring personal names were confidently identified yet.",
            to: &lines
        )
        let places = analysis.entities.filter { $0.kind == .place }
        let organizations = analysis.entities.filter { $0.kind == .organization }
        if !places.isEmpty {
            lines += ["", "### Places & Settings", ""]
            appendEntities(places, empty: "", to: &lines)
        }
        if !organizations.isEmpty {
            lines += ["", "### Organizations & Groups", ""]
            appendEntities(organizations, empty: "", to: &lines)
        }

        lines += [
            "",
            "## Argument, Evidence & Sources",
            "",
            "- Citation-like references detected: **\(analysis.citationCount)**",
            "- Sentences worth checking for support: **\(analysis.claimChecks.count)**"
        ]
        appendFindings(
            analysis.claimChecks,
            empty: "No obvious numeric or research-style claims without nearby citation markers were detected.",
            to: &lines
        )

        lines += [
            "",
            "## Readability & Accessibility",
            "",
            "- Overall estimated grade: **\(format(analysis.overallGrade))**",
            "- Chapter range: **\(format(gradeRange.0))–\(format(gradeRange.1))**",
            "- Adverbs flagged locally: **\(analysis.adverbCount)**",
            "- Passive constructions flagged locally: **\(analysis.passiveVoiceCount)**"
        ]
        if let structure = analysis.structuralProfile {
            lines += [
                "",
                "### Benepar Sentence Structure",
                "",
                "- Sentences analyzed: **\(structure.sentencesAnalyzed)**\(structure.isSampled ? " of \(structure.sentencesAvailable) available" : "")",
                "- Average parse depth: **\(format(structure.averageTreeDepth))**; maximum: **\(structure.maximumTreeDepth)**",
                "- Average clauses per sentence: **\(format(structure.averageClausesPerSentence))**",
                "- Sentences using subordinate clauses: **\(Int((structure.subordinateSentenceRatio * 100).rounded()))%**",
                "- Average longest noun phrase: **\(format(structure.averageLongestNounPhraseWords)) words**",
                "- Sentences using coordination: **\(Int((structure.coordinationRatio * 100).rounded()))%**",
                "",
                "These are syntactic signals from the optional local English language pack. Fragments, dense clauses, and long phrases may be intentional, especially in fiction."
            ]
        }
        lines += ["", "## Repetition & Language", ""]
        if analysis.repeatedPhrases.isEmpty {
            lines.append("No repeated three-word phrase crossed the local reporting threshold.")
        } else {
            for phrase in analysis.repeatedPhrases {
                lines.append("- `\(phrase.value)` — \(phrase.count) uses")
            }
        }
        if !analysis.keyTerms.isEmpty {
            lines += ["", "### Frequent Key Terms", ""]
            lines.append(analysis.keyTerms.prefix(20).map { "`\($0.value)` (\($0.count))" }.joined(separator: " · "))
        }

        lines += [
            "",
            "## Voice & Style",
            "",
            "The local profile is \(voiceDescription(analysis)). These measurements describe surface patterns; they do not judge artistic intent or factual quality.",
            "",
            "## Recommended Attention",
            ""
        ]
        lines.append(contentsOf: recommendations(analysis))
        lines += [
            "",
            "---",
            "",
            "This report is generated locally from the project’s Markdown files. It identifies signals to review, not proven errors. **Deepen w/ AI** is separate and never runs automatically."
        ]
        return lines.joined(separator: "\n")
    }

    static func renderBibleBlock(_ analysis: ManuscriptAnalysis) -> String {
        var lines = ["## Automatically Tracked Manuscript Facts"]
        for kind in ManuscriptEntityKind.allCases {
            let matches = analysis.entities.filter { $0.kind == kind }
            guard !matches.isEmpty else { continue }
            lines += ["", "### \(kind.title)", ""]
            for entity in matches.prefix(40) {
                let chapters = entity.chapters.prefix(5).joined(separator: ", ")
                let more = entity.chapters.count > 5 ? " and \(entity.chapters.count - 5) more" : ""
                lines.append("- **\(entity.name)** — \(entity.count) mentions; \(chapters)\(more) <!-- kistulentz:id:entity:\(kind.rawValue):\(slug(entity.name)) -->")
            }
        }

        lines += ["", "### Key Terms & Concepts", ""]
        if analysis.keyTerms.isEmpty {
            lines.append("- No stable key terms identified yet. <!-- kistulentz:id:key-term:none -->")
        } else {
            for term in analysis.keyTerms.prefix(30) {
                lines.append("- **\(term.value)** — \(term.count) uses <!-- kistulentz:id:key-term:\(slug(term.value)) -->")
            }
        }

        lines += ["", "### Timeline & Date Markers", ""]
        if analysis.timelineMarkers.isEmpty {
            lines.append("- No explicit date or weekday markers identified yet. <!-- kistulentz:id:timeline:none -->")
        } else {
            for marker in analysis.timelineMarkers {
                lines.append("- **\(marker.value)** — \(marker.count) mentions <!-- kistulentz:id:timeline:\(slug(marker.value)) -->")
            }
        }

        lines += ["", "### Chapter & Section Map", ""]
        for (index, chapter) in analysis.chapters.enumerated() {
            lines.append("- **\(index + 1). \(chapter.title)** — \(chapter.wordCount.formatted()) words; grade \(format(chapter.gradeLevel)) <!-- kistulentz:id:chapter:\(slug(chapter.relativePath)) -->")
        }

        lines += ["", "### Continuity Watchlist", ""]
        if analysis.continuityChecks.isEmpty {
            lines.append("- No obvious local continuity warnings. <!-- kistulentz:id:continuity:none -->")
        } else {
            for (index, finding) in analysis.continuityChecks.enumerated() {
                lines.append("- **\(finding.title):** \(finding.detail) <!-- kistulentz:id:continuity:\(index)-\(slug(finding.title)) -->")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func pacingObservation(_ analysis: ManuscriptAnalysis) -> String {
        guard analysis.chapters.count > 1 else {
            return "- Pacing comparison will become more useful after the project contains multiple sections."
        }
        let values = analysis.chapters.map { Double($0.wordCount) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let variation = mean == 0 ? 0 : sqrt(variance) / mean
        if variation > 0.65 {
            return "- Section lengths vary sharply. Confirm that the largest shifts are intentional rather than structural gaps."
        }
        if analysis.averageSentenceWords < 13 {
            return "- Short sentences create a generally brisk surface pace. Check whether reflective or explanatory passages have enough room."
        }
        if analysis.averageSentenceWords > 22 {
            return "- Long sentences create a generally deliberate pace. Check action, transitions, and key explanations for drag."
        }
        return "- Sentence and section lengths suggest a generally steady surface pace."
    }

    private static func voiceDescription(_ analysis: ManuscriptAnalysis) -> String {
        let tempo = analysis.averageSentenceWords < 13 ? "brisk" : analysis.averageSentenceWords > 21 ? "deliberate" : "steady"
        let paragraph = analysis.averageParagraphWords < 45 ? "open, short-paragraph" : analysis.averageParagraphWords > 110 ? "dense, long-paragraph" : "moderately dense"
        let dialogue = analysis.dialogueRatio > 0.28 ? "dialogue-forward" : "narrative or explanatory-forward"
        return "\(tempo), \(paragraph), and \(dialogue)"
    }

    private static func recommendations(_ analysis: ManuscriptAnalysis) -> [String] {
        var values: [String] = []
        if !analysis.continuityChecks.isEmpty {
            values.append("1. Review the \(analysis.continuityChecks.count) continuity signal\(analysis.continuityChecks.count == 1 ? "" : "s") against the manuscript’s intended canon or terminology.")
        }
        if !analysis.claimChecks.isEmpty {
            values.append("\(values.count + 1). Verify support and citation placement for the \(analysis.claimChecks.count) claim-style sentence\(analysis.claimChecks.count == 1 ? "" : "s") surfaced locally.")
        }
        if analysis.overallGrade > 12 {
            values.append("\(values.count + 1). Review dense sentences and jargon if the intended audience is general rather than specialist.")
        }
        if !analysis.repeatedPhrases.isEmpty {
            values.append("\(values.count + 1). Inspect the most repeated phrases in context; retain deliberate motifs and revise accidental echoes.")
        }
        if values.isEmpty {
            values.append("1. No high-priority local signal dominates. Review structure and intent section by section before requesting deeper AI analysis.")
        }
        return values
    }

    private static func appendEntities(
        _ entities: [ManuscriptEntity],
        empty: String,
        to lines: inout [String]
    ) {
        guard !entities.isEmpty else {
            if !empty.isEmpty { lines.append(empty) }
            return
        }
        for entity in entities.prefix(30) {
            lines.append("- **\(entity.name)** — \(entity.count) mentions across \(entity.chapters.count) section\(entity.chapters.count == 1 ? "" : "s")")
        }
    }

    private static func appendFindings(
        _ findings: [ManuscriptFinding],
        empty: String,
        to lines: inout [String]
    ) {
        guard !findings.isEmpty else {
            lines.append(empty)
            return
        }
        for finding in findings.prefix(12) {
            let path = finding.chapterPath.map { " (`\($0)`)" } ?? ""
            lines.append("- **\(finding.title):** \(finding.detail)\(path)")
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func slug(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let pieces = folded.lowercased().split { !$0.isLetter && !$0.isNumber }
        return pieces.joined(separator: "-").prefix(80).description
    }
}

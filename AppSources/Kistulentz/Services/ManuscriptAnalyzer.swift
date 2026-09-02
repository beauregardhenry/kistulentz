import Foundation
import NaturalLanguage

enum ManuscriptAnalyzer {
    private static let headingRegex = try! NSRegularExpression(pattern: #"(?m)^\s{0,3}#{1,6}\s+"#)
    private static let citationRegex = try! NSRegularExpression(
        pattern: #"(?:\[[^\]]+\]\([^\)]+\)|\[\^[^\]]+\]|https?://\S+|\([A-Z][A-Za-z-]+(?:\s+(?:and|&|et al\.)\s+[A-Z][A-Za-z-]+)?,\s*(?:18|19|20)\d{2}\))"#,
        options: [.caseInsensitive]
    )
    private static let claimCueRegex = try! NSRegularExpression(
        pattern: #"\b(?:research|studies|data|evidence|experts|scientists|survey|report|statistics|according to|proves?|causes?|results? in)\b|\b\d+(?:\.\d+)?\s*%|\b(?:18|19|20)\d{2}\b"#,
        options: [.caseInsensitive]
    )
    private static let timelineRegex = try! NSRegularExpression(
        pattern: #"\b(?:(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:\s+\d{1,2})?(?:,?\s+(?:18|19|20)\d{2})?|(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)|(?:18|19|20)\d{2})\b"#,
        options: [.caseInsensitive]
    )
    private static let phraseStopwords: Set<String> = [
        "and", "the", "that", "this", "with", "from", "into", "were", "was", "are", "for",
        "but", "not", "you", "your", "his", "her", "their", "they", "she", "him", "have",
        "had", "has", "would", "could", "should", "there", "then", "than", "when", "where"
    ]

    static func analyze(
        projectName: String,
        kind: WritingProjectKind,
        documents: [ManuscriptDocument]
    ) -> ManuscriptAnalysis {
        var chapterMetrics: [ManuscriptChapterMetrics] = []
        var entityAccumulator: [String: EntityAccumulator] = [:]
        var wordCounts: [String: Int] = [:]
        var phraseCounts: [String: Int] = [:]
        var timelineCounts: [String: Int] = [:]
        var claimChecks: [ManuscriptFinding] = []
        var totalDialogueWords = 0
        var totalParagraphWords = 0
        var totalParagraphs = 0
        var allWords: [String] = []

        for document in documents {
            let words = ReferenceTextTools.words(in: document.text)
            let sentences = ReferenceTextTools.sentences(in: document.text)
            let paragraphs = nonemptyParagraphs(in: document.text)
            let readable = ReadabilityEngine.analyze(document.text, targetGrade: 8)
            let dialogueWords = ReferenceTextTools.dialogueWordCount(in: document.text)
            let citationCount = matches(citationRegex, in: document.text).count
            let paragraphWordCount = paragraphs.reduce(0) { $0 + ReferenceTextTools.words(in: $1).count }
            let sentenceCount = max(sentences.count, words.isEmpty ? 0 : 1)
            let averageSentence = words.isEmpty ? 0 : Double(words.count) / Double(max(sentenceCount, 1))
            let averageParagraph = paragraphs.isEmpty ? 0 : Double(paragraphWordCount) / Double(paragraphs.count)
            let dialogueRatio = words.isEmpty ? 0 : Double(dialogueWords) / Double(words.count)
            let headingCount = matches(headingRegex, in: document.text).count
            let adverbs = readable.issues.filter { $0.category == .adverb }.count
            let passive = readable.issues.filter { $0.category == .passiveVoice }.count

            chapterMetrics.append(ManuscriptChapterMetrics(
                relativePath: document.relativePath,
                title: document.title,
                wordCount: words.count,
                sentenceCount: sentenceCount,
                gradeLevel: readable.stats.gradeLevel,
                averageSentenceWords: averageSentence,
                averageParagraphWords: averageParagraph,
                dialogueRatio: dialogueRatio,
                headingCount: headingCount,
                adverbCount: adverbs,
                passiveVoiceCount: passive,
                citationCount: citationCount
            ))

            totalDialogueWords += dialogueWords
            totalParagraphWords += paragraphWordCount
            totalParagraphs += paragraphs.count
            allWords.append(contentsOf: words)
            accumulateWords(words, into: &wordCounts)
            accumulatePhrases(words, into: &phraseCounts)
            accumulateEntities(in: document, into: &entityAccumulator)
            accumulateTimeline(in: document.text, into: &timelineCounts)
            claimChecks.append(contentsOf: unsupportedClaimChecks(in: document))
        }

        addFallbackEntities(documents: documents, into: &entityAccumulator)

        let totalWords = chapterMetrics.reduce(0) { $0 + $1.wordCount }
        let totalSentences = chapterMetrics.reduce(0) { $0 + $1.sentenceCount }
        let combinedText = documents.map(\.text).joined(separator: "\n\n")
        let overallStats = ReadabilityEngine.calculateStats(for: combinedText, targetGrade: 8)
        let averageSentence = totalWords == 0 ? 0 : Double(totalWords) / Double(max(totalSentences, 1))
        let averageParagraph = totalParagraphs == 0 ? 0 : Double(totalParagraphWords) / Double(totalParagraphs)
        let dialogueRatio = totalWords == 0 ? 0 : Double(totalDialogueWords) / Double(totalWords)
        let entities = makeEntities(entityAccumulator)
        let keyTerms = makeKeyTerms(wordCounts, excluding: entities)
        let repeatedPhrases = phraseCounts
            .filter { $0.value >= 3 }
            .sorted(by: frequencySort)
            .prefix(15)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }
        let timelineMarkers = timelineCounts
            .sorted(by: frequencySort)
            .prefix(30)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }
        let continuity = continuityChecks(chapters: chapterMetrics, entities: entities)

        var result = ManuscriptAnalysis(
            projectName: projectName,
            kind: kind,
            chapters: chapterMetrics,
            entities: entities,
            keyTerms: keyTerms,
            repeatedPhrases: repeatedPhrases,
            timelineMarkers: timelineMarkers,
            claimChecks: Array(claimChecks.prefix(20)),
            continuityChecks: continuity,
            totalWords: totalWords,
            totalSentences: totalSentences,
            overallGrade: overallStats.gradeLevel,
            averageSentenceWords: averageSentence,
            averageParagraphWords: averageParagraph,
            dialogueRatio: dialogueRatio,
            citationCount: chapterMetrics.reduce(0) { $0 + $1.citationCount },
            adverbCount: chapterMetrics.reduce(0) { $0 + $1.adverbCount },
            passiveVoiceCount: chapterMetrics.reduce(0) { $0 + $1.passiveVoiceCount },
            structuralProfile: nil,
            reportMarkdown: "",
            generatedBibleBlock: ""
        )
        result.reportMarkdown = renderReport(result)
        result.generatedBibleBlock = renderBibleBlock(result)
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
        enriched.reportMarkdown = renderReport(enriched)
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

    private static func renderReport(_ analysis: ManuscriptAnalysis) -> String {
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
        appendFindings(analysis.continuityChecks, empty: "No obvious cross-chapter naming or readability discontinuities were found by the local scan.", to: &lines)

        lines += ["", "## Characters & People", ""]
        appendEntities(analysis.entities.filter { $0.kind == .person }, empty: "No recurring personal names were confidently identified yet.", to: &lines)
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
        appendFindings(analysis.claimChecks, empty: "No obvious numeric or research-style claims without nearby citation markers were detected.", to: &lines)

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

    private static func renderBibleBlock(_ analysis: ManuscriptAnalysis) -> String {
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

    private static func appendEntities(_ entities: [ManuscriptEntity], empty: String, to lines: inout [String]) {
        guard !entities.isEmpty else {
            if !empty.isEmpty { lines.append(empty) }
            return
        }
        for entity in entities.prefix(30) {
            lines.append("- **\(entity.name)** — \(entity.count) mentions across \(entity.chapters.count) section\(entity.chapters.count == 1 ? "" : "s")")
        }
    }

    private static func appendFindings(_ findings: [ManuscriptFinding], empty: String, to lines: inout [String]) {
        guard !findings.isEmpty else {
            lines.append(empty)
            return
        }
        for finding in findings.prefix(12) {
            let path = finding.chapterPath.map { " (`\($0)`)" } ?? ""
            lines.append("- **\(finding.title):** \(finding.detail)\(path)")
        }
    }

    private static func unsupportedClaimChecks(in document: ManuscriptDocument) -> [ManuscriptFinding] {
        let sentences = ReferenceTextTools.sentences(in: document.text)
        return sentences.compactMap { sentence in
            let range = NSRange(location: 0, length: (sentence as NSString).length)
            guard claimCueRegex.firstMatch(in: sentence, range: range) != nil,
                  citationRegex.firstMatch(in: sentence, range: range) == nil else { return nil }
            let excerpt = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else { return nil }
            return ManuscriptFinding(
                title: "Check support",
                detail: String(excerpt.prefix(220)),
                chapterPath: document.relativePath
            )
        }
    }

    private static func continuityChecks(
        chapters: [ManuscriptChapterMetrics],
        entities: [ManuscriptEntity]
    ) -> [ManuscriptFinding] {
        var findings: [ManuscriptFinding] = []
        let recurring = entities.filter { $0.count >= 2 && ($0.kind == .person || $0.kind == .other) }
        for firstIndex in recurring.indices {
            for secondIndex in recurring.indices where secondIndex > firstIndex {
                let first = recurring[firstIndex]
                let second = recurring[secondIndex]
                guard first.name.first?.lowercased() == second.name.first?.lowercased(),
                      abs(first.name.count - second.name.count) <= 1,
                      levenshtein(first.name.lowercased(), second.name.lowercased()) == 1 else { continue }
                findings.append(ManuscriptFinding(
                    title: "Similar names",
                    detail: "`\(first.name)` and `\(second.name)` differ by one character. Confirm that both forms are intentional."
                ))
                if findings.count >= 8 { break }
            }
            if findings.count >= 8 { break }
        }

        let titles = Dictionary(grouping: chapters, by: { $0.title.lowercased() })
        for duplicate in titles.values where duplicate.count > 1 {
            findings.append(ManuscriptFinding(
                title: "Repeated section title",
                detail: "`\(duplicate[0].title)` appears \(duplicate.count) times."
            ))
        }

        if let minimum = chapters.min(by: { $0.gradeLevel < $1.gradeLevel }),
           let maximum = chapters.max(by: { $0.gradeLevel < $1.gradeLevel }),
           maximum.gradeLevel - minimum.gradeLevel >= 4 {
            findings.append(ManuscriptFinding(
                title: "Reading-level shift",
                detail: "`\(minimum.title)` is near grade \(format(minimum.gradeLevel)), while `\(maximum.title)` is near grade \(format(maximum.gradeLevel)). Check whether the audience or voice changes intentionally."
            ))
        }
        return findings
    }

    private static func accumulateEntities(
        in document: ManuscriptDocument,
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let text = String(document.text.prefix(500_000))
        guard !text.isEmpty else { return }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let kind: ManuscriptEntityKind
            switch tag {
            case .personalName: kind = .person
            case .placeName: kind = .place
            case .organizationName: kind = .organization
            default: return true
            }
            let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return true }
            addEntity(name: name, kind: kind, chapter: document.title, into: &accumulator)
            return true
        }
    }

    private static func addFallbackEntities(
        documents: [ManuscriptDocument],
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let combined = documents.map(\.text).joined(separator: "\n")
        for name in ReferenceTextTools.characterNames(in: String(combined.prefix(600_000))) {
            let lower = name.lowercased()
            if accumulator.values.contains(where: { $0.name.lowercased() == lower }) { continue }
            var chapters: [String] = []
            var total = 0
            for document in documents {
                let count = occurrences(of: name, in: document.text)
                if count > 0 {
                    total += count
                    chapters.append(document.title)
                }
            }
            guard total >= 2 else { continue }
            let key = "\(ManuscriptEntityKind.other.rawValue):\(lower)"
            accumulator[key] = EntityAccumulator(name: name, kind: .other, count: total, chapters: Set(chapters))
        }
    }

    private static func addEntity(
        name: String,
        kind: ManuscriptEntityKind,
        chapter: String,
        into accumulator: inout [String: EntityAccumulator]
    ) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(kind.rawValue):\(clean.lowercased())"
        var value = accumulator[key] ?? EntityAccumulator(name: clean, kind: kind, count: 0, chapters: [])
        value.count += 1
        value.chapters.insert(chapter)
        accumulator[key] = value
    }

    private static func makeEntities(_ accumulator: [String: EntityAccumulator]) -> [ManuscriptEntity] {
        accumulator.values
            .filter { $0.count >= 2 }
            .map { ManuscriptEntity(
                name: $0.name,
                kind: $0.kind,
                count: $0.count,
                chapters: $0.chapters.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            ) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.count > rhs.count
            }
    }

    private static func makeKeyTerms(
        _ counts: [String: Int],
        excluding entities: [ManuscriptEntity]
    ) -> [ManuscriptFrequency] {
        let nameWords = Set(entities.flatMap { entity in
            entity.name.lowercased().split(separator: " ").map(String.init)
        })
        return counts
            .filter { word, count in
                word.count >= 5 && count >= 3 && !phraseStopwords.contains(word) && !nameWords.contains(word)
            }
            .sorted(by: frequencySort)
            .prefix(30)
            .map { ManuscriptFrequency(value: $0.key, count: $0.value) }
    }

    private static func accumulateWords(_ words: [String], into counts: inout [String: Int]) {
        for raw in words.prefix(500_000) {
            let word = raw.lowercased()
            counts[word, default: 0] += 1
        }
    }

    private static func accumulatePhrases(_ words: [String], into counts: inout [String: Int]) {
        let lowered = words.prefix(500_000).map { $0.lowercased() }
        guard lowered.count >= 3 else { return }
        for index in 0...(lowered.count - 3) {
            let slice = Array(lowered[index..<(index + 3)])
            guard slice.allSatisfy({ $0.count > 2 }),
                  !phraseStopwords.contains(slice[0]),
                  !phraseStopwords.contains(slice[2]) else { continue }
            counts[slice.joined(separator: " "), default: 0] += 1
        }
    }

    private static func accumulateTimeline(in text: String, into counts: inout [String: Int]) {
        let source = text as NSString
        for match in matches(timelineRegex, in: text) {
            let value = source.substring(with: match.range)
            let key = value.prefix(1).uppercased() + value.dropFirst().lowercased()
            counts[key, default: 0] += 1
        }
    }

    private static func nonemptyParagraphs(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, options: [.caseInsensitive], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private static func frequencySort(_ lhs: Dictionary<String, Int>.Element, _ rhs: Dictionary<String, Int>.Element) -> Bool {
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
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

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private static func slug(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let pieces = folded.lowercased().split { !$0.isLetter && !$0.isNumber }
        return pieces.joined(separator: "-").prefix(80).description
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (index, first) in a.enumerated() {
            var current = [index + 1]
            for (otherIndex, second) in b.enumerated() {
                current.append(min(
                    current[otherIndex] + 1,
                    previous[otherIndex + 1] + 1,
                    previous[otherIndex] + (first == second ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[b.count]
    }
}

private struct EntityAccumulator {
    let name: String
    let kind: ManuscriptEntityKind
    var count: Int
    var chapters: Set<String>
}

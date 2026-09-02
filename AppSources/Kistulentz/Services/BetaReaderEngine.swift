import Foundation

enum BetaReaderEngine {
    static func read(
        profile: BetaReaderProfile,
        scope: BetaReaderScope,
        projectName: String,
        kind: WritingProjectKind,
        documents: [ManuscriptDocument],
        targetGrade: Int
    ) -> BetaReaderFeedback {
        let analysis = ManuscriptAnalyzer.analyze(
            projectName: projectName,
            kind: kind,
            documents: documents
        )
        let focus = "\(profile.name) \(profile.focus)".lowercased()
        var strengths: [String] = []
        var concerns: [String] = []
        var questions: [String] = []

        if analysis.totalWords == 0 {
            concerns.append("This scope contains no prose to assess yet.")
        } else {
            strengths.append("The selected scope contains \(analysis.totalWords.formatted()) words across \(documents.count) \(documents.count == 1 ? "section" : "sections"), enough for a local surface-pattern review.")
        }

        if analysis.overallGrade <= Double(targetGrade) + 1 {
            strengths.append("The estimated reading grade \(format(analysis.overallGrade)) is near the grade \(targetGrade) target.")
        } else {
            concerns.append("The estimated reading grade is \(format(analysis.overallGrade)), above the grade \(targetGrade) target. Dense sentences and unexplained terms are good places to inspect first.")
        }

        if focus.contains("structure") || focus.contains("momentum") || focus.contains("overall") {
            addStructureSignals(analysis, strengths: &strengths, concerns: &concerns, questions: &questions)
        }
        if focus.contains("character") || focus.contains("emotion") || focus.contains("relationship") {
            addCharacterSignals(analysis, strengths: &strengths, concerns: &concerns, questions: &questions)
        }
        if focus.contains("continuity") || focus.contains("chronology") || focus.contains("terminology") {
            if analysis.continuityChecks.isEmpty {
                strengths.append("The local scan found no obvious name-similarity or cross-section readability discontinuity.")
            } else {
                concerns.append(contentsOf: analysis.continuityChecks.prefix(3).map { "\($0.title): \($0.detail)" })
            }
            questions.append("Do the tracked names, terms, and dates in the project Bible match your intended canon or source terminology?")
        }
        if focus.contains("evidence") || focus.contains("claim") || focus.contains("source") || focus.contains("skeptical") {
            if analysis.claimChecks.isEmpty {
                strengths.append("No obvious research-style or numeric claim without a nearby citation marker was found locally.")
            } else {
                concerns.append("\(analysis.claimChecks.count) claim-style sentence\(analysis.claimChecks.count == 1 ? "" : "s") may need a closer support or citation check.")
                questions.append("Which claims should read as sourced fact, and which are intentionally framed as interpretation or illustration?")
            }
        }
        if focus.contains("clarity") || focus.contains("accessibility") || focus.contains("general") {
            if analysis.averageSentenceWords > 22 {
                concerns.append("Sentences average \(format(analysis.averageSentenceWords)) words, which may make key explanations or action harder to follow.")
            } else {
                strengths.append("Sentence length averages \(format(analysis.averageSentenceWords)) words, a generally manageable surface rhythm.")
            }
            if !analysis.keyTerms.isEmpty {
                questions.append("Will a first-time reader understand the recurring terms \(analysis.keyTerms.prefix(4).map(\.value).joined(separator: ", ")) when they first appear?")
            }
        }
        if analysis.repeatedPhrases.isEmpty {
            strengths.append("No three-word phrase crossed the local repetition threshold in this scope.")
        } else {
            let examples = analysis.repeatedPhrases.prefix(3).map { "“\($0.value)” (\($0.count))" }.joined(separator: ", ")
            concerns.append("Repeated phrasing may be intentional, but these patterns deserve a read aloud: \(examples).")
        }

        if questions.isEmpty {
            questions.append(kind == .fiction
                ? "Where should a reader feel the strongest change in desire, danger, or understanding in this scope?"
                : "What single conclusion should a reader carry forward from this scope, and is it stated with the right degree of certainty?")
        }
        let reaction = reactionText(analysis, kind: kind)
        let summary = "Local, signal-based feedback from \(profile.name) for the \(scope.title.lowercased()). It measures textual patterns; it does not simulate a human reader or prove an editorial judgment."

        return BetaReaderFeedback(
            reader: profile,
            scope: scope,
            source: .local,
            summary: summary,
            reaction: reaction,
            strengths: Array(strengths.uniqued().prefix(6)),
            concerns: Array(concerns.uniqued().prefix(6)),
            questions: Array(questions.uniqued().prefix(6))
        )
    }

    private static func addStructureSignals(
        _ analysis: ManuscriptAnalysis,
        strengths: inout [String],
        concerns: inout [String],
        questions: inout [String]
    ) {
        guard analysis.chapters.count > 1 else {
            questions.append("Does this section establish a clear purpose early and deliver a meaningful turn or conclusion before it ends?")
            return
        }
        let counts = analysis.chapters.map(\.wordCount)
        let low = counts.min() ?? 0
        let high = counts.max() ?? 0
        if low > 0, high > low * 4 {
            concerns.append("Section lengths range from \(low.formatted()) to \(high.formatted()) words. Confirm the largest imbalance reflects intentional pacing.")
        } else {
            strengths.append("Section lengths are reasonably balanced at the manuscript level.")
        }
        questions.append("Does each section change what the reader knows, feels, or expects, or are any sections mainly connective tissue?")
    }

    private static func addCharacterSignals(
        _ analysis: ManuscriptAnalysis,
        strengths: inout [String],
        concerns: inout [String],
        questions: inout [String]
    ) {
        let people = analysis.entities.filter { $0.kind == .person || $0.kind == .other }
        if people.isEmpty {
            concerns.append("The local name scan could not confidently track recurring people or characters in this scope.")
        } else {
            strengths.append("Recurring people or character names are trackable across the scope, led by \(people.prefix(4).map(\.name).joined(separator: ", ")).")
        }
        if analysis.dialogueRatio > 0.05 {
            strengths.append("Dialogue or quoted speech provides an additional channel for voice and relationship cues.")
        }
        questions.append("Are the central person's immediate desire, pressure, and change legible without relying on information outside this scope?")
    }

    private static func reactionText(_ analysis: ManuscriptAnalysis, kind: WritingProjectKind) -> String {
        let pace = analysis.averageSentenceWords < 13 ? "brisk" : analysis.averageSentenceWords > 22 ? "deliberate" : "steady"
        let density = analysis.averageParagraphWords > 110 ? "dense" : analysis.averageParagraphWords < 45 ? "open" : "moderately dense"
        if kind == .fiction {
            return "On the page, the prose reads as \(pace) and \(density), with about \(Int((analysis.dialogueRatio * 100).rounded()))% dialogue or quoted speech."
        }
        return "On the page, the explanation reads as \(pace) and \(density), with \(analysis.citationCount) citation-like marker\(analysis.citationCount == 1 ? "" : "s") detected."
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

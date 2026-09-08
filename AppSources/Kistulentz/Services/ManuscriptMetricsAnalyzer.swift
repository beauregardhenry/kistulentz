import Foundation

struct ManuscriptMetricSummary {
    let chapters: [ManuscriptChapterMetrics]
    let totalWords: Int
    let totalSentences: Int
    let overallGrade: Double
    let averageSentenceWords: Double
    let averageParagraphWords: Double
    let dialogueRatio: Double
    let citationCount: Int
    let adverbCount: Int
    let passiveVoiceCount: Int
}

enum ManuscriptMetricsAnalyzer {
    private static let headingRegex = try! NSRegularExpression(pattern: #"(?m)^\s{0,3}#{1,6}\s+"#)
    private static let citationRegex = try! NSRegularExpression(
        pattern: #"(?:\[[^\]]+\]\([^\)]+\)|\[\^[^\]]+\]|https?://\S+|\([A-Z][A-Za-z-]+(?:\s+(?:and|&|et al\.)\s+[A-Z][A-Za-z-]+)?,\s*(?:18|19|20)\d{2}\))"#,
        options: [.caseInsensitive]
    )

    static func analyze(documents: [ManuscriptDocument]) -> ManuscriptMetricSummary {
        var chapters: [ManuscriptChapterMetrics] = []
        var totalDialogueWords = 0
        var totalParagraphWords = 0
        var totalParagraphs = 0

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

            chapters.append(ManuscriptChapterMetrics(
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
        }

        let totalWords = chapters.reduce(0) { $0 + $1.wordCount }
        let totalSentences = chapters.reduce(0) { $0 + $1.sentenceCount }
        let combinedText = documents.map(\.text).joined(separator: "\n\n")
        let overallStats = ReadabilityEngine.calculateStats(for: combinedText, targetGrade: 8)

        return ManuscriptMetricSummary(
            chapters: chapters,
            totalWords: totalWords,
            totalSentences: totalSentences,
            overallGrade: overallStats.gradeLevel,
            averageSentenceWords: totalWords == 0 ? 0 : Double(totalWords) / Double(max(totalSentences, 1)),
            averageParagraphWords: totalParagraphs == 0 ? 0 : Double(totalParagraphWords) / Double(totalParagraphs),
            dialogueRatio: totalWords == 0 ? 0 : Double(totalDialogueWords) / Double(totalWords),
            citationCount: chapters.reduce(0) { $0 + $1.citationCount },
            adverbCount: chapters.reduce(0) { $0 + $1.adverbCount },
            passiveVoiceCount: chapters.reduce(0) { $0 + $1.passiveVoiceCount }
        )
    }

    private static func nonemptyParagraphs(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}

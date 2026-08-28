import Foundation

struct EPUBReference: Identifiable {
    let id: UUID
    let fileName: String
    let title: String
    let author: String?
    let subjects: [String]
    let chapters: [ReferenceChapter]
    let profile: ReferenceProfile
    let learnedInsights: String?
    let sourceCount: Int

    init(
        id: UUID = UUID(),
        fileName: String,
        title: String,
        author: String?,
        subjects: [String] = [],
        chapters: [ReferenceChapter],
        profile: ReferenceProfile,
        learnedInsights: String? = nil,
        sourceCount: Int = 1
    ) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.author = author
        self.subjects = subjects
        self.chapters = chapters
        self.profile = profile
        self.learnedInsights = learnedInsights
        self.sourceCount = sourceCount
    }
}

struct ReferenceChapter: Identifiable, Codable {
    let id: Int
    let title: String
    let text: String
}

struct ReferenceProfile: Codable {
    let wordCount: Int
    let chapterCount: Int
    let gradeLevel: Double
    let averageSentenceWords: Double
    let sentenceVariation: Double
    let averageParagraphWords: Double
    let dialogueRatio: Double
    let firstPersonRatio: Double
    let thirdPersonRatio: Double
    let tempo: String
    let voice: String
    let tone: [String]
    let vocabulary: [String]
    let characters: [String]

    var aiSummary: String {
        let characterList = characters.prefix(20).joined(separator: ", ")
        let vocabularyList = vocabulary.prefix(20).joined(separator: ", ")
        return """
        Reading grade: \(gradeLevel.formatted(.number.precision(.fractionLength(1))))
        Average sentence: \(averageSentenceWords.formatted(.number.precision(.fractionLength(1)))) words
        Average paragraph: \(averageParagraphWords.formatted(.number.precision(.fractionLength(1)))) words
        Dialogue share: \((dialogueRatio * 100).formatted(.number.precision(.fractionLength(0))))%
        Voice: \(voice)
        Tempo: \(tempo)
        Tone signals: \(tone.joined(separator: ", "))
        Recurring vocabulary: \(vocabularyList.isEmpty ? "none identified" : vocabularyList)
        Character names: \(characterList.isEmpty ? "none identified" : characterList)
        """
    }
}

struct ReferenceAlignment {
    let score: Int
    let notes: [ReferenceNote]
    let issues: [WritingIssue]

    static let empty = ReferenceAlignment(score: 0, notes: [], issues: [])
}

struct ReferenceNote: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isAligned: Bool
}

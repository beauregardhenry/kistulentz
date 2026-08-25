import Foundation

struct EPUBReference: Identifiable {
    let id: UUID
    let fileName: String
    let title: String
    let author: String?
    let chapters: [ReferenceChapter]
    let profile: ReferenceProfile

    init(
        id: UUID = UUID(),
        fileName: String,
        title: String,
        author: String?,
        chapters: [ReferenceChapter],
        profile: ReferenceProfile
    ) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.author = author
        self.chapters = chapters
        self.profile = profile
    }
}

struct ReferenceChapter: Identifiable {
    let id: Int
    let title: String
    let text: String
}

struct ReferenceProfile {
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

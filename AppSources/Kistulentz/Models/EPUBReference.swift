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

    func addingStructuralProfile(_ structuralProfile: StructuralProfile?) -> EPUBReference {
        EPUBReference(
            id: id,
            fileName: fileName,
            title: title,
            author: author,
            subjects: subjects,
            chapters: chapters,
            profile: profile.addingStructuralProfile(structuralProfile),
            learnedInsights: learnedInsights,
            sourceCount: sourceCount
        )
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
    let structuralProfile: StructuralProfile?

    init(
        wordCount: Int,
        chapterCount: Int,
        gradeLevel: Double,
        averageSentenceWords: Double,
        sentenceVariation: Double,
        averageParagraphWords: Double,
        dialogueRatio: Double,
        firstPersonRatio: Double,
        thirdPersonRatio: Double,
        tempo: String,
        voice: String,
        tone: [String],
        vocabulary: [String],
        characters: [String],
        structuralProfile: StructuralProfile? = nil
    ) {
        self.wordCount = wordCount
        self.chapterCount = chapterCount
        self.gradeLevel = gradeLevel
        self.averageSentenceWords = averageSentenceWords
        self.sentenceVariation = sentenceVariation
        self.averageParagraphWords = averageParagraphWords
        self.dialogueRatio = dialogueRatio
        self.firstPersonRatio = firstPersonRatio
        self.thirdPersonRatio = thirdPersonRatio
        self.tempo = tempo
        self.voice = voice
        self.tone = tone
        self.vocabulary = vocabulary
        self.characters = characters
        self.structuralProfile = structuralProfile
    }

    func addingStructuralProfile(_ profile: StructuralProfile?) -> ReferenceProfile {
        ReferenceProfile(
            wordCount: wordCount,
            chapterCount: chapterCount,
            gradeLevel: gradeLevel,
            averageSentenceWords: averageSentenceWords,
            sentenceVariation: sentenceVariation,
            averageParagraphWords: averageParagraphWords,
            dialogueRatio: dialogueRatio,
            firstPersonRatio: firstPersonRatio,
            thirdPersonRatio: thirdPersonRatio,
            tempo: tempo,
            voice: voice,
            tone: tone,
            vocabulary: vocabulary,
            characters: characters,
            structuralProfile: profile
        )
    }

    var aiSummary: String {
        let characterList = characters.prefix(20).joined(separator: ", ")
        let vocabularyList = vocabulary.prefix(20).joined(separator: ", ")
        var result = """
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
        if let structuralProfile {
            result += "\n" + structuralProfile.summary
        }
        return result
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

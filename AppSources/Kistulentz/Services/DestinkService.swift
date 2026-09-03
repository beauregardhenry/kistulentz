import Foundation

// The rule taxonomy, report weighting, and portions of the phrase catalog are adapted from
// lex00/sentences' de-stink linter (MIT). Kistulentz implements the runtime natively in Swift and
// adds an optional tree-backed pass to its existing Benepar worker. See THIRD_PARTY_NOTICES.md.

enum DestinkService {
    static func analyze(
        documents: [ManuscriptDocument],
        useBenepar: Bool = true,
        benepar: BeneparService = .shared
    ) async -> DestinkReport {
        var reports: [DestinkDocumentReport] = []
        // Keep a whole-manuscript run bounded to roughly the same 400-sentence neural budget as a
        // single document while still sampling every chapter. Native rules always see all text.
        let parsedSentencesPerDocument = max(1, 400 / max(documents.count, 1))
        for document in documents {
            guard !Task.isCancelled else { break }
            let local = DestinkEngine.analyze(document.text)
            let parsed = useBenepar
                ? await benepar.destinkIfAvailable(
                    text: document.text,
                    maximumSentences: parsedSentencesPerDocument
                )
                : nil
            let merged = DestinkEngine.merge(local: local, benepar: parsed?.findings ?? [])
            reports.append(DestinkDocumentReport(
                relativePath: document.relativePath,
                title: document.title,
                wordCount: DestinkEngine.wordCount(document.text),
                findings: merged,
                usedBenepar: parsed != nil
            ))
        }
        return DestinkReport(documents: reports)
    }
}

enum DestinkEngine {
    private struct PhraseRule {
        let id: String
        let name: String
        let severity: DestinkSeverity
        let escalationAt: Int?
        let phrases: [String]
        let explanation: String
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \Character.isWhitespace).count
    }

    static func analyze(_ text: String) -> [DestinkFinding] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let prose = markdownProse(text)
        var findings = leakageFindings(in: text)
        findings += phraseFindings(in: prose, original: text)
        findings += syntacticFindings(in: prose, original: text)
        findings += formattingFindings(in: text)
        findings += discourseFindings(in: prose, original: text)
        findings += nativeAITellFindings(in: prose, original: text, existing: findings)
        findings += claudeCooccurrenceFinding(in: text, findings: findings)
        return normalized(findings, in: text)
    }

    static func merge(local: [DestinkFinding], benepar: [DestinkFinding]) -> [DestinkFinding] {
        var merged = local
        for parsed in benepar {
            let duplicate = merged.contains {
                $0.ruleID == parsed.ruleID && NSIntersectionRange($0.range, parsed.range).length > 0
            }
            if !duplicate { merged.append(parsed) }
        }
        return normalized(merged, in: nil)
    }

    // MARK: Markdown

    /// Removes Markdown syntax that is commonly mistaken for prose without moving offsets.
    /// Every replacement has exactly the same UTF-16 length as the source range.
    static func markdownProse(_ text: String) -> String {
        let masked = NSMutableString(string: text)
        let full = NSRange(location: 0, length: masked.length)
        let patterns = [
            #"(?ms)^\s*(```|~~~).*?^\s*\1[^\n]*$"#,
            #"(?m)^\s*\|.*\|\s*$"#,
            #"(?m)^\s*:::+[^\n]*$"#,
            #"(?s)<!--.*?-->"#,
            #"(?m)^\s*</?[A-Za-z][^>]*>\s*$"#,
            #"`+[^`\n]*`+"#,
            #"(?<=\])\([^\n)]*\)"#
        ]
        var ranges: [NSRange] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            ranges += regex.matches(in: text, range: full).map(\.range)
        }
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let source = masked.substring(with: range) as NSString
            let replacement = NSMutableString(capacity: source.length)
            for index in 0..<source.length {
                let value = source.character(at: index)
                replacement.append(value == 10 || value == 13 ? String(UnicodeScalar(value)!) : " ")
            }
            masked.replaceCharacters(in: range, with: replacement as String)
        }
        return masked as String
    }

    // MARK: Lexical rules

    private static let phraseRules: [PhraseRule] = [
        PhraseRule(
            id: "claude-assistant-voice", name: "Assistant voice", severity: .medium, escalationAt: 3,
            phrases: ["you're absolutely right", "you are absolutely right", "you're absolutely correct", "great question", "excellent question", "that's a great point", "great catch", "I appreciate your patience", "I apologize for the confusion", "happy to elaborate", "feel free to", "would you like me to", "a good starting point", "a solid starting point", "a great starting point", "there's no one-size-fits-all", "your mileage may vary", "reasonable people can disagree", "this matters because"],
            explanation: "This sounds like a chat reply addressing a user rather than finished prose. State the point directly in the document's own voice."
        ),
        PhraseRule(
            id: "claude-discourse-markers", name: "Stock transition", severity: .low, escalationAt: 3,
            phrases: ["the key insight is", "the trick is", "the catch is", "the upshot", "put differently", "said differently", "in other words", "more concretely", "zooming out", "taking a step back", "at a high level", "that said", "to be clear", "to be fair", "to be direct", "to be frank", "in practice", "in short", "in essence", "simply put", "long story short", "net-net", "worth calling out", "worth flagging", "one thing to note", "a few things to note", "key takeaways", "better posed", "double-click on", "lean into"],
            explanation: "The transition announces how to read the next sentence instead of letting the sentence do that work. Remove it when the connection remains clear."
        ),
        PhraseRule(
            id: "claude-stock-frames", name: "Stock urgency frame", severity: .low, escalationAt: 3,
            phrases: ["isn't slowing down", "isn't going anywhere", "can't afford to", "stay on the sidelines", "wake-up call", "the stakes couldn't be higher", "makes the case for", "the case for", "wasn't built for", "wasn't designed for", "the pace it brings", "here's why that matters", "from day one", "after the fact", "humans in the loop", "human in the loop", "baked into", "built in from the start", "full stop", "plain and simple", "it's that simple", "let that sink in", "read that again", "if this resonates", "repost if"],
            explanation: "This is a stock hook or sign-off that manufactures urgency. Say the concrete claim and let its consequences carry the emphasis."
        ),
        PhraseRule(
            id: "claude-technical-vocabulary", name: "Stock technical vocabulary", severity: .low, escalationAt: 4,
            phrases: ["worth stating plainly", "battle-tested", "footgun", "escape hatch", "happy path", "blast radius", "table stakes", "north star", "single source of truth", "paper cut", "sharp edges", "cognitive load", "mental model", "first-class citizen", "batteries included", "guardrails", "moving parts", "seamless", "seamlessly", "performant", "idiomatic", "opinionated", "principled", "pragmatic", "composable", "ergonomics", "ergonomic", "affordance", "surface area", "future-proof", "non-trivial", "meticulously", "thoughtfully", "gracefully", "holistic", "orthogonal", "flesh out", "round out", "wire up", "thread through", "plumb through", "spiritually", "morally equivalent"],
            explanation: "This phrase is common in generic technical prose. Prefer the specific behavior, cost, or constraint you mean."
        ),
        PhraseRule(
            id: "corporate-jargon", name: "Corporate jargon", severity: .medium, escalationAt: nil,
            phrases: ["actionable insights", "thought leadership", "pain points", "pain point", "move the needle", "low-hanging fruit", "paradigm shift", "deep dive", "value proposition", "key learnings", "circle back", "double down", "take this offline", "north star metric", "boil the ocean", "best-in-class", "at the end of the day"],
            explanation: "This phrase substitutes familiar business shorthand for a precise claim. Name the action, result, or problem directly."
        ),
        PhraseRule(
            id: "lex-delve-family", name: "Overused AI vocabulary", severity: .low, escalationAt: 2,
            phrases: ["delve", "delves", "delved", "delving", "certainly", "utilize", "utilizes", "utilized", "utilizing", "leverage", "leverages", "leveraged", "leveraging", "robust", "streamline", "streamlines", "streamlined", "streamlining", "harness", "harnesses", "harnessed", "harnessing"],
            explanation: "This word is disproportionately common in generic generated prose. Use the plain verb or name the specific quality instead."
        ),
        PhraseRule(
            id: "lex-false-suspense", name: "False suspense", severity: .medium, escalationAt: nil,
            phrases: ["here's the kicker", "here's the thing", "here's where it gets interesting", "here's what most people miss", "here's the deal"],
            explanation: "This delays the point to manufacture suspense. Lead with the information the phrase promises."
        ),
        PhraseRule(
            id: "lex-filler-transitions", name: "Filler transition", severity: .medium, escalationAt: nil,
            phrases: ["it's worth noting", "it bears mentioning", "importantly", "interestingly", "notably"],
            explanation: "This labels the next statement instead of strengthening it. Delete the label if the statement is important on its own."
        ),
        PhraseRule(
            id: "lex-magic-adverbs", name: "Magic adverb", severity: .low, escalationAt: 2,
            phrases: ["quietly", "deeply", "fundamentally", "remarkably", "arguably"],
            explanation: "This adverb asks the reader to accept emphasis or significance without evidence. Make the underlying claim more concrete."
        ),
        PhraseRule(
            id: "lex-ornate-nouns", name: "Ornate abstraction", severity: .low, escalationAt: 2,
            phrases: ["tapestry", "landscape", "paradigm", "synergy", "ecosystem"],
            explanation: "This broad metaphor often hides the actual actors and relationships. Name the concrete system or situation."
        ),
        PhraseRule(
            id: "lex-pedagogical-voice", name: "Stock teaching voice", severity: .medium, escalationAt: nil,
            phrases: ["let's break this down", "let's unpack", "let's dive in", "let's explore", "think of it as", "it's like a"],
            explanation: "This adopts a canned tutorial voice. Explain the idea directly, using the detail the reader actually needs."
        ),
        PhraseRule(
            id: "lex-signposts", name: "Signposted conclusion", severity: .low, escalationAt: 2,
            phrases: ["in conclusion", "to sum up", "in summary"],
            explanation: "The section already tells the reader it is ending. Let the conclusion begin with its strongest claim."
        ),
        PhraseRule(
            id: "lex-stakes-inflation", name: "Stakes inflation", severity: .medium, escalationAt: nil,
            phrases: ["fundamentally reshape", "will define the next era", "entirely new"],
            explanation: "This raises the stakes without supplying evidence. State the measurable change and who it affects."
        ),
        PhraseRule(
            id: "lex-vague-attribution", name: "Vague attribution", severity: .medium, escalationAt: nil,
            phrases: ["experts argue", "experts say", "observers have cited", "industry reports suggest"],
            explanation: "The authority is unnamed, so the reader cannot evaluate it. Name and cite the source or make the claim in your own voice."
        ),
        PhraseRule(
            id: "claude-fiction-frames", name: "Stock fiction frame", severity: .medium, escalationAt: 3,
            phrases: ["something else entirely", "barely above a whisper", "voice barely audible", "a breath she didn't know", "a breath he didn't know", "smile didn't reach", "didn't reach his eyes", "didn't reach her eyes", "quiet for a long moment", "a sound like", "like a held breath", "trying to sound casual", "something flickered across", "something shifted in", "seen better days", "couldn't shake the feeling", "for what seemed like an eternity", "little did she know", "little did he know", "the air was thick with", "sent shivers down", "a mix of", "eyes gleamed with", "knuckles whitened", "let out a breath"],
            explanation: "This is a familiar generated-fiction frame. Replace the stock cue with the character's particular action, perception, or consequence."
        )
    ]

    private static let excessVocabulary = [
        "showcasing", "underscores", "underscoring", "surpassing", "commendable", "advancement", "advancements", "aligns", "avenue", "avenues", "bolster", "bolstered", "bolstering", "boasts", "burgeoning", "compelling", "crafted", "crafting", "culminating", "delineates", "discern", "discernible", "elucidate", "elucidates", "elucidating", "embracing", "emphasizing", "encapsulates", "encompass", "encompassing", "endeavors", "endeavours", "exceptional", "foundational", "formidable", "garnered", "garnering", "groundbreaking", "grappling", "groundwork", "hinges", "illuminates", "illuminating", "imperative", "impressive", "innovative", "interconnectedness", "interplay", "intricate", "intricacies", "intricately", "invaluable", "juxtaposed", "multifaceted", "necessitate", "noteworthy", "nuanced", "nuances", "orchestrating", "paving", "pinpoint", "pinpointing", "pioneering", "pivotal", "poised", "propelling", "realm", "realms", "renowned", "revolutionize", "revolutionizing", "scrutinize", "scrutinizing", "showcase", "showcased", "showcases", "spurred", "substantiated", "surmount", "surpass", "surpassed", "surpasses", "transformative", "unparalleled", "unraveling", "underexplored", "underscore", "underscored", "unexplored", "uncharted", "unveil", "unveiling", "unveils", "unveiled", "unlock", "unlocking", "versatility", "notable", "comprehensive", "crucial", "insights", "enhancing"
    ]

    private static func phraseFindings(in prose: String, original: String) -> [DestinkFinding] {
        var rules = phraseRules
        rules.append(PhraseRule(
            id: "excess-vocabulary", name: "Excess LLM vocabulary", severity: .low, escalationAt: 3,
            phrases: excessVocabulary,
            explanation: "This word appears heavily in generated prose and often makes a sentence less specific. Prefer the ordinary word that names what happened."
        ))
        rules.append(PhraseRule(
            id: "demo/intensifier", name: "Filler intensifier", severity: .low, escalationAt: 3,
            phrases: ["very", "really", "quite", "extremely", "incredibly", "truly"],
            explanation: "This adds emphasis without adding information. Remove it or choose a more exact word."
        ))

        var findings: [DestinkFinding] = []
        for rule in rules {
            var hits: [NSRange] = []
            for phrase in rule.phrases { hits += literalRanges(of: phrase, in: prose) }
            hits = uniqueRanges(hits)
            let severity: DestinkSeverity
            if let threshold = rule.escalationAt {
                if rule.id.hasPrefix("claude") || rule.id == "demo/intensifier" {
                    severity = hits.count >= threshold ? steppedUp(rule.severity) : rule.severity
                } else {
                    severity = hits.count < threshold ? steppedDown(rule.severity) : rule.severity
                }
            } else {
                severity = rule.severity
            }
            for range in hits {
                findings.append(makeFinding(
                    ruleID: rule.id,
                    tier: .lexical,
                    severity: severity,
                    range: range,
                    text: original,
                    message: rule.name,
                    explanation: rule.explanation
                ))
            }
        }
        return findings
    }

    private static func leakageFindings(in text: String) -> [DestinkFinding] {
        let artifacts = ["oaicite", "contentReference", "oai_citation", "turn0search", "attributableIndex", "[cite: ", "[span_", "(start_span)", "grok_card", "grok_render_citation_card_json", "ppl-ai-file-upload", "attached_file", ":::writing", "regenerate response", "【", "】"]
        let boilerplate = ["as an AI language model", "as a language model, I", "as of my last knowledge update", "my last knowledge update", "up to my last training update", "my knowledge cutoff", "I don't have access to real-time", "I do not have personal", "I cannot fulfill this request", "I'm sorry, but as an AI", "certainly, here is", "certainly, here are", "I hope this helps", "let me know if you'd like me to", "would you like me to expand"]
        var findings: [DestinkFinding] = []
        for phrase in artifacts {
            for range in literalRanges(of: phrase, in: text, requiresBoundary: false) {
                findings.append(makeFinding(
                    ruleID: "claude/ai-leakage", tier: .lexical, severity: .high,
                    range: range, text: text, message: "Leaked assistant artifact",
                    explanation: "This is citation, tool, or interface debris copied into the document. Remove the tag and keep the prose it was attached to."
                ))
            }
        }
        for phrase in boilerplate {
            for range in literalRanges(of: phrase, in: text) {
                let softer = phrase == "I hope this helps" || phrase.hasPrefix("let me know") || phrase.hasPrefix("would you like")
                findings.append(makeFinding(
                    ruleID: "claude/ai-leakage", tier: .lexical, severity: softer ? .medium : .high,
                    range: range, text: text, message: "Assistant boilerplate",
                    explanation: "This belongs to a chat response, not finished prose. Delete the reply wrapper and keep the substantive answer."
                ))
            }
        }
        return findings
    }

    // MARK: Syntactic and formatting rules

    private static func syntacticFindings(in prose: String, original: String) -> [DestinkFinding] {
        var findings: [DestinkFinding] = []
        findings += regexFindings(
            pattern: #"(?is)\b(?:it|this|that)\s+(?:is|was|'s)\s+not\b[^.!?]{0,100}[.!?]\s*(?:it|this|that)\s+(?:is|was|'s)\b[^.!?]{1,120}[.!?]"#,
            in: prose, original: original, ruleID: "reframe", tier: .syntactic, severity: .medium,
            message: "Not X, but Y reframe",
            explanation: "The first sentence exists mainly to negate a weaker label before the second supplies the real one. Lead with the claim you mean."
        )
        findings += regexFindings(
            pattern: #"(?is)\b(?:serves?|served|serving|stands?|stood)\s+as\b"#,
            in: prose, original: original, ruleID: "serves-as-dodge", tier: .syntactic, severity: .medium,
            message: "“Serves as” may be doing “is”'s job",
            explanation: "Try a plain “is” or “was.” Keep the longer phrase only when it changes the meaning."
        )
        findings += regexFindings(
            pattern: #"(?is),\s+(?:\w+[ -]?){0,2}\w+ing\b[^.!?]{0,100}(?:[.!?]|$)"#,
            in: prose, original: original, ruleID: "ing-tackon", tier: .syntactic, severity: .low,
            message: "Trailing -ing clause",
            explanation: "The trailing participial clause can become a generic significance tag. Check that it describes an action with a clear actor rather than restating the sentence."
        )
        findings += regexFindings(
            pattern: #"(?is)\bnot\s+(?:just|only)\b[^.!?]{1,120}\bbut(?:\s+also)?\b[^.!?]{1,120}"#,
            in: prose, original: original, ruleID: "claude/mirrored-clauses", tier: .syntactic, severity: .low,
            message: "Mirrored not-only/but-also frame",
            explanation: "The mirrored frame can make an ordinary comparison sound staged. State the stronger half directly when the contrast adds no information."
        )
        findings += regexFindings(
            pattern: #"(?im)^[^\n:]{3,80}\b(?:truth|reality|answer|result|reason|lesson|point)\s*:\s+[^\n]{3,160}"#,
            in: prose, original: original, ruleID: "claude/colon-reveal", tier: .syntactic, severity: .low,
            message: "Colon used as a reveal",
            explanation: "The label before the colon announces a reveal. Start with the information after the colon if it stands on its own."
        )
        findings += regexFindings(
            pattern: #"(?is),\s*not\s+(?:just\s+)?[^,.!?]{1,80}(?:[.!?]|$)"#,
            in: prose, original: original, ruleID: "claude/contrast-tail", tier: .syntactic, severity: .candidate,
            message: "Contrast tail",
            explanation: "The trailing “not …” can dismiss a comparison the sentence did not need. Check whether cutting the tail makes the claim cleaner."
        )
        findings += selfPosedQuestionFindings(in: prose, original: original)
        return findings
    }

    private static func selfPosedQuestionFindings(in prose: String, original: String) -> [DestinkFinding] {
        let pattern = #"(?m)(?:^|(?<=[.!]))\s*([^.!?\n]{2,70}\?)\s+([^.!?\n]{1,100}(?:[.!]|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = prose as NSString
        let matches = regex.matches(in: prose, range: NSRange(location: 0, length: source.length))
        return matches.compactMap { match in
            let question = source.substring(with: match.range(at: 1))
            let answer = source.substring(with: match.range(at: 2))
            let questionWords = wordCount(question)
            let answerWords = wordCount(answer)
            guard questionWords <= 4 || answerWords <= 6 else { return nil }
            return makeFinding(
                ruleID: "syntactic/self-posed-question", tier: .syntactic,
                severity: matches.count >= 2 ? .medium : .low,
                range: NSUnionRange(match.range(at: 1), match.range(at: 2)), text: original,
                message: "Question answered in the next breath",
                explanation: "This asks a question only to deliver an immediate reveal. State the answer directly, or keep the question and answer it fully."
            )
        }
    }

    private static func formattingFindings(in text: String) -> [DestinkFinding] {
        var findings = regexFindings(
            pattern: #"(?m)^\s*(?:→|⇒|➜|➤|⟶)\s*"#,
            in: text, original: text, ruleID: "formatting/unicode-decoration", tier: .formatting,
            severity: .medium, message: "Decorative arrow replaces prose",
            explanation: "A bare arrow asks typography to carry a relationship. Write the verb or use a real Markdown list."
        )
        let labels = regexRanges(pattern: #"(?m)^\s*(?:[-*+]\s+)?(?:\*\*|__)[^\n]{1,60}(?:\*\*|__)[\s:—-]+"#, in: text)
        if labels.count >= 3 {
            findings += labels.map { range in
                makeFinding(
                    ruleID: "formatting/listicle-in-trench-coat", tier: .formatting, severity: .medium,
                    range: range, text: text, message: "Repeated bold run-in labels",
                    explanation: "Several mini-headings turn connected prose into a disguised listicle. Use a real list when these are separate items, or let the paragraphs carry their own openings."
                )
            }
        }
        return findings
    }

    // MARK: Discourse rules

    private static func discourseFindings(in prose: String, original: String) -> [DestinkFinding] {
        var findings: [DestinkFinding] = []
        let sentences = sentenceRanges(in: prose)

        var shortRun: [NSRange] = []
        func flushShortRun() {
            if shortRun.count >= 2 {
                let range = shortRun.dropFirst().reduce(shortRun[0], NSUnionRange)
                findings.append(makeFinding(
                    ruleID: "discourse/punchy-fragments", tier: .discourse,
                    severity: shortRun.count >= 3 ? .high : .medium,
                    range: range, text: original, message: "Run of short sentence fragments",
                    explanation: "One fragment can land. Several in a row create a mechanical drumbeat; let some of them become complete sentences."
                ))
            }
            shortRun = []
        }
        let verbPattern = #"(?i)\b(?:am|is|are|was|were|be|been|being|do|does|did|have|has|had|can|could|will|would|shall|should|may|might|must|\w+(?:ed|ing))\b"#
        let verbRegex = try? NSRegularExpression(pattern: verbPattern)
        for range in sentences {
            let sentence = (prose as NSString).substring(with: range)
            let words = wordCount(sentence)
            let hasVerb = verbRegex?.firstMatch(in: sentence, range: NSRange(location: 0, length: (sentence as NSString).length)) != nil
            if words > 0, words <= 4, !hasVerb, !sentence.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                shortRun.append(range)
            } else {
                flushShortRun()
            }
        }
        flushShortRun()

        for index in 0..<(max(0, sentences.count - 2)) {
            let group = Array(sentences[index...index + 2])
            let values = group.map { (prose as NSString).substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.allSatisfy({ wordCount($0) <= 5 }),
                  values.prefix(2).allSatisfy({ $0.range(of: #"^(?:not|no|never)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) else { continue }
            let range = group.dropFirst().reduce(group[0], NSUnionRange)
            findings.append(makeFinding(
                ruleID: "discourse/countdown", tier: .discourse, severity: .high,
                range: range, text: original, message: "Negated countdown",
                explanation: "The repeated short negations build an artificial reveal. State the final point and keep only the contrast that changes its meaning."
            ))
        }

        let normalizedSentences = sentences.map { range -> (String, NSRange) in
            let raw = (prose as NSString).substring(with: range)
            let value = raw.lowercased()
                .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return (value, range)
        }.filter { wordCount($0.0) >= 5 }
        let groups = Dictionary(grouping: normalizedSentences, by: \.0).values.filter { $0.count >= 2 }
        for group in groups {
            for (_, range) in group.dropFirst() {
                findings.append(makeFinding(
                    ruleID: "repetition/dilution", tier: .discourse, severity: .medium,
                    range: range, text: original, message: "A point is repeated almost verbatim",
                    explanation: "Repeating the same claim dilutes it rather than reinforcing it. Keep the strongest occurrence and use the space for evidence or consequence."
                ))
            }
        }

        let paragraphs = paragraphRanges(in: prose)
        let oneSentenceParagraphs = paragraphs.filter { paragraph in
            sentenceRanges(in: (prose as NSString).substring(with: paragraph)).count == 1
        }
        if sentences.count >= 6,
           Double(oneSentenceParagraphs.count) / Double(max(paragraphs.count, 1)) >= 0.65 {
            let punctuation = regexRanges(pattern: #"[,;:()]|[—–]"#, in: prose).count
            if Double(punctuation) / Double(sentences.count) < 0.8 {
                findings.append(makeFinding(
                    ruleID: "discourse/staccato-register", tier: .discourse, severity: .medium,
                    range: NSRange(location: 0, length: (original as NSString).length), text: original,
                    message: "The document stays in a clipped, one-sentence rhythm",
                    explanation: "Most paragraphs contain one sentence and very little internal punctuation. Join related thoughts so the prose can subordinate, qualify, and vary its pace."
                ))
            }
        }
        return findings
    }

    private static func claudeCooccurrenceFinding(in text: String, findings: [DestinkFinding]) -> [DestinkFinding] {
        let familyIDs = Set(findings.map(\.ruleID).filter {
            $0.hasPrefix("claude") || $0 == "ing-tackon"
        })
        guard familyIDs.count >= 4 else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return [makeFinding(
            ruleID: "claude/sounds-like-claude", tier: .discourse, severity: .high,
            range: range, text: text, message: "Several stock-writing families co-occur",
            explanation: "Any one phrase may be ordinary. Several distinct families in one document form a consistent generic register. Revise for a voice grounded in the document's specific subject."
        )]
    }

    /// Reuse the compact, always-on detector that powers editor highlights for its additional
    /// high-signal patterns. The scored review has a wider catalog, so near-identical spans are
    /// suppressed here rather than showing the author the same observation twice.
    private static func nativeAITellFindings(
        in prose: String,
        original: String,
        existing: [DestinkFinding]
    ) -> [DestinkFinding] {
        AITellEngine.analyze(prose).compactMap { issue in
            let overlapsExisting = existing.contains { finding in
                let overlap = NSIntersectionRange(finding.range, issue.range).length
                return overlap > 0 && Double(overlap) / Double(min(finding.range.length, issue.range.length)) >= 0.75
            }
            guard !overlapsExisting else { return nil }
            return makeFinding(
                ruleID: "native/ai-tell",
                tier: .lexical,
                severity: .medium,
                range: issue.range,
                text: original,
                message: "AI-sounding phrasing",
                explanation: issue.message
            )
        }
    }

    // MARK: Helpers

    private static func literalRanges(
        of phrase: String,
        in text: String,
        requiresBoundary: Bool = true
    ) -> [NSRange] {
        var body = NSRegularExpression.escapedPattern(for: phrase)
        body = body.replacingOccurrences(of: #"\ "#, with: #"\s+"#)
        let pattern = requiresBoundary
            ? #"(?<![\p{L}\p{N}_])"# + body + #"(?![\p{L}\p{N}_])"#
            : body
        return regexRanges(pattern: pattern, in: text, options: [.caseInsensitive])
    }

    private static func regexRanges(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: range).map(\.range)
    }

    private static func regexFindings(
        pattern: String,
        in text: String,
        original: String,
        ruleID: String,
        tier: DestinkTier,
        severity: DestinkSeverity,
        message: String,
        explanation: String
    ) -> [DestinkFinding] {
        regexRanges(pattern: pattern, in: text).map {
            makeFinding(
                ruleID: ruleID, tier: tier, severity: severity, range: $0,
                text: original, message: message, explanation: explanation
            )
        }
    }

    private static func makeFinding(
        ruleID: String,
        tier: DestinkTier,
        severity: DestinkSeverity,
        range: NSRange,
        text: String,
        message: String,
        explanation: String
    ) -> DestinkFinding {
        let source = text as NSString
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
        return DestinkFinding(
            ruleID: ruleID,
            tier: tier,
            severity: severity,
            range: safe,
            excerpt: source.substring(with: safe).trimmingCharacters(in: .whitespacesAndNewlines),
            message: message,
            explanation: explanation
        )
    }

    private static func sentenceRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?s)(?:^|(?<=[.!?]))\s*[^.!?\n][^.!?]*?(?:[.!?]+|(?=\n\s*\n)|$)"#) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map(\.range)
            .filter { !source.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func paragraphRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        let separators = regexRanges(pattern: #"\n[\t ]*\n+"#, in: text)
        var ranges: [NSRange] = []
        var start = 0
        for separator in separators + [NSRange(location: source.length, length: 0)] {
            var candidate = NSRange(location: start, length: max(0, separator.location - start))
            while candidate.length > 0,
                  CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: candidate.location))!) {
                candidate.location += 1
                candidate.length -= 1
            }
            while candidate.length > 0,
                  CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: NSMaxRange(candidate) - 1))!) {
                candidate.length -= 1
            }
            if candidate.length > 0 { ranges.append(candidate) }
            start = NSMaxRange(separator)
        }
        return ranges
    }

    private static func uniqueRanges(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<String>()
        return ranges.filter { seen.insert("\($0.location):\($0.length)").inserted }
    }

    private static func steppedUp(_ severity: DestinkSeverity) -> DestinkSeverity {
        switch severity {
        case .candidate: .low
        case .low: .medium
        case .medium, .high: .high
        }
    }

    private static func steppedDown(_ severity: DestinkSeverity) -> DestinkSeverity {
        switch severity {
        case .candidate, .low: .candidate
        case .medium: .low
        case .high: .medium
        }
    }

    private static func normalized(_ findings: [DestinkFinding], in text: String?) -> [DestinkFinding] {
        var seen = Set<String>()
        return findings
            .filter { finding in
                guard finding.range.location != NSNotFound, finding.range.length > 0 else { return false }
                if let text, NSMaxRange(finding.range) > (text as NSString).length { return false }
                return seen.insert("\(finding.ruleID):\(finding.range.location):\(finding.range.length)").inserted
            }
            .sorted {
                if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
                if $0.range.length != $1.range.length { return $0.range.length > $1.range.length }
                return $0.ruleID < $1.ruleID
            }
    }
}

#!/usr/bin/env python3
"""Local JSON-lines bridge between Kistulentz and the Benepar English model.

The worker reads one JSON object per line from stdin and writes one JSON object
per line to stdout. It never opens a network connection. Model and tokenizer
files must already exist inside the selected Kistulentz language pack.
"""

from __future__ import annotations

import json
import os
import re
import sys
import traceback
from dataclasses import dataclass
from typing import Iterable, Sequence

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import benepar  # noqa: E402
import spacy  # noqa: E402
from nltk import Tree  # noqa: E402


ENGINE_NAME = "Benepar English"
ENGINE_VERSION = "2"
CLAUSE_LABELS = {"S", "SBAR", "SBARQ", "SINV", "SQ"}
SUBORDINATE_LABELS = {"SBAR", "SBARQ"}
ADVERB_TAGS = {"RB", "RBR", "RBS"}
ADVERB_EXCEPTIONS = {
    "daily",
    "early",
    "family",
    "friendly",
    "likely",
    "lively",
    "lonely",
    "lovely",
    "only",
    "silly",
    "ugly",
    "weekly",
}
AUXILIARY_FORMS = {
    "am",
    "are",
    "be",
    "been",
    "being",
    "is",
    "was",
    "were",
    "get",
    "gets",
    "getting",
    "got",
}


@dataclass(frozen=True)
class SentenceRecord:
    start: int
    end: int
    text: str
    words: list[str]
    spaces: list[bool]
    token_starts: list[int]
    token_ends: list[int]


def utf16_length(value: str) -> int:
    return len(value.encode("utf-16-le")) // 2


def utf16_range(text: str, start: int, end: int) -> tuple[int, int]:
    location = utf16_length(text[:start])
    return location, utf16_length(text[start:end])


def label(tree: Tree) -> str:
    value = tree.label()
    return value.split("::", 1)[0] if isinstance(value, str) else str(value)


def subtrees(tree: Tree) -> Iterable[Tree]:
    return tree.subtrees(lambda node: isinstance(node, Tree))


def nested_label_depth(tree: Tree, target: str) -> int:
    child_depths = [nested_label_depth(child, target) for child in tree if isinstance(child, Tree)]
    child_max = max(child_depths, default=0)
    return child_max + 1 if label(tree) == target else child_max


def sentence_records(tokenizer, text: str) -> list[SentenceRecord]:
    doc = tokenizer(text)
    records: list[SentenceRecord] = []
    for sentence in doc.sents:
        words = [token.text for token in sentence]
        if not any(any(character.isalpha() for character in word) for word in words):
            continue
        records.append(
            SentenceRecord(
                start=sentence.start_char,
                end=sentence.end_char,
                text=sentence.text,
                words=words,
                spaces=[bool(token.whitespace_) for token in sentence],
                token_starts=[token.idx for token in sentence],
                token_ends=[token.idx + len(token.text) for token in sentence],
            )
        )
    return records


def evenly_sampled(records: Sequence[SentenceRecord], limit: int) -> list[SentenceRecord]:
    if limit <= 0 or len(records) <= limit:
        return list(records)
    return [records[index * len(records) // limit] for index in range(limit)]


def issue(text: str, start: int, end: int, category: str, message: str) -> dict:
    location, length = utf16_range(text, start, end)
    return {
        "category": category,
        "location": location,
        "length": length,
        "excerpt": text[start:end].strip(),
        "message": message,
    }


def destink_finding(
    text: str,
    start: int,
    end: int,
    rule_id: str,
    severity: str,
    message: str,
    explanation: str,
) -> dict:
    location, length = utf16_range(text, start, end)
    return {
        "ruleId": rule_id,
        "tier": "syntactic",
        "severity": severity,
        "location": location,
        "length": length,
        "excerpt": text[start:end].strip(),
        "message": message,
        "explanation": explanation,
    }


def passive_issues(text: str, record: SentenceRecord, tree: Tree) -> list[dict]:
    tagged = tree.pos()
    results: list[dict] = []
    for index, (_, tag) in enumerate(tagged):
        if tag != "VBN":
            continue
        start_index = None
        for candidate in range(index - 1, max(-1, index - 4), -1):
            if record.words[candidate].lower() in AUXILIARY_FORMS:
                start_index = candidate
                break
        if start_index is None:
            continue
        start = record.token_starts[start_index]
        end = record.token_ends[index]
        results.append(
            issue(
                text,
                start,
                end,
                "passiveVoice",
                "Benepar found a likely passive construction. Keep it when the actor is unknown or unimportant; otherwise name the actor and consider an active verb.",
            )
        )
    return results


def adverb_issues(text: str, record: SentenceRecord, tree: Tree) -> list[dict]:
    results: list[dict] = []
    for index, (_, tag) in enumerate(tree.pos()):
        word = record.words[index]
        if tag not in ADVERB_TAGS or word.lower() in ADVERB_EXCEPTIONS:
            continue
        if not any(character.isalpha() for character in word):
            continue
        results.append(
            issue(
                text,
                record.token_starts[index],
                record.token_ends[index],
                "adverb",
                "Benepar identified this as an adverb. Check whether it adds meaning or whether a more precise verb would carry the sentence better.",
            )
        )
    return results


def analyze_sentence(text: str, record: SentenceRecord, tree: Tree, include_issues: bool) -> tuple[dict, list[dict]]:
    nodes = list(subtrees(tree))
    labels = [label(node) for node in nodes]
    clause_count = sum(value in CLAUSE_LABELS for value in labels)
    subordinate_count = sum(value in SUBORDINATE_LABELS for value in labels)
    noun_phrase_lengths = [len(node.leaves()) for node in nodes if label(node) == "NP"]
    longest_noun_phrase = max(noun_phrase_lengths, default=0)
    prepositional_count = sum(value == "PP" for value in labels)
    nested_prepositional_depth = nested_label_depth(tree, "PP")
    coordination_count = sum(tag == "CC" for _, tag in tree.pos())
    tree_depth = max(0, tree.height() - 2)
    root_labels = {label(tree)} | {label(child) for child in tree if isinstance(child, Tree)}
    is_fragment = "FRAG" in labels or not bool(root_labels & CLAUSE_LABELS)
    has_subordination = subordinate_count > 0

    passives = passive_issues(text, record, tree)
    sentence_issues: list[dict] = []
    if include_issues:
        reasons: list[str] = []
        if is_fragment:
            reasons.append("a possible sentence fragment")
        if tree_depth >= 12:
            reasons.append(f"a parse depth of {tree_depth}")
        if clause_count >= 4:
            reasons.append(f"{clause_count} nested or coordinated clauses")
        if longest_noun_phrase >= 13:
            reasons.append(f"a {longest_noun_phrase}-word noun phrase")
        if prepositional_count >= 4 or nested_prepositional_depth >= 3:
            reasons.append("stacked prepositional phrases")
        if coordination_count >= 3:
            reasons.append("several coordinated elements")
        if reasons:
            sentence_issues.append(
                issue(
                    text,
                    record.start,
                    record.end,
                    "structuralComplexity",
                    "Benepar found " + ", ".join(reasons) + ". Check whether the structure is intentional and easy to follow; no automatic rewrite is applied.",
                )
            )
        sentence_issues.extend(passives)
        sentence_issues.extend(adverb_issues(text, record, tree))

    metrics = {
        "treeDepth": tree_depth,
        "clauseCount": clause_count,
        "subordinateCount": subordinate_count,
        "hasSubordination": has_subordination,
        "longestNounPhraseWords": longest_noun_phrase,
        "hasLongNounPhrase": longest_noun_phrase >= 13,
        "coordinationCount": coordination_count,
        "hasCoordination": coordination_count > 0,
        "passiveCandidateCount": len(passives),
        "isFragment": is_fragment,
    }
    return metrics, sentence_issues


def average(values: Sequence[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def handle_analyze(parser: benepar.Parser, tokenizer, request: dict) -> dict:
    text = request.get("text", "")
    if not isinstance(text, str):
        raise ValueError("text must be a string")
    maximum_sentences = int(request.get("maximumSentences", 40))
    maximum_sentences = max(1, min(maximum_sentences, 400))
    include_issues = bool(request.get("includeIssues", True))
    available = sentence_records(tokenizer, text)
    selected = evenly_sampled(available, maximum_sentences)
    inputs = [
        benepar.InputSentence(words=record.words, space_after=record.spaces)
        for record in selected
    ]
    trees = list(parser.parse_sents(inputs)) if inputs else []

    per_sentence: list[dict] = []
    issues: list[dict] = []
    for record, tree in zip(selected, trees):
        metrics, sentence_issues = analyze_sentence(text, record, tree, include_issues)
        per_sentence.append(metrics)
        issues.extend(sentence_issues)

    analyzed_count = len(per_sentence)
    metrics = {
        "sentencesAnalyzed": analyzed_count,
        "sentencesAvailable": len(available),
        "averageTreeDepth": average([item["treeDepth"] for item in per_sentence]),
        "maximumTreeDepth": max([item["treeDepth"] for item in per_sentence], default=0),
        "averageClausesPerSentence": average([item["clauseCount"] for item in per_sentence]),
        "subordinateSentenceRatio": average([1.0 if item["hasSubordination"] else 0.0 for item in per_sentence]),
        "averageLongestNounPhraseWords": average([item["longestNounPhraseWords"] for item in per_sentence]),
        "longNounPhraseRatio": average([1.0 if item["hasLongNounPhrase"] else 0.0 for item in per_sentence]),
        "coordinationRatio": average([1.0 if item["hasCoordination"] else 0.0 for item in per_sentence]),
        "passiveCandidateRatio": average([1.0 if item["passiveCandidateCount"] else 0.0 for item in per_sentence]),
        "fragmentRatio": average([1.0 if item["isFragment"] else 0.0 for item in per_sentence]),
    }
    return {"metrics": metrics, "issues": issues}


def has_finite_verb(tree: Tree) -> bool:
    return any(tag.startswith("VB") or tag == "MD" for _, tag in tree.pos())


def handle_destink(parser: benepar.Parser, tokenizer, request: dict) -> dict:
    """Find structural writing tics using Benepar's real POS tags and phrase tree.

    Lexical, Markdown, and document-layout rules live in Swift so the feature remains
    useful without the optional pack. This pass owns only patterns for which a parse
    materially improves precision.
    """
    text = request.get("text", "")
    if not isinstance(text, str):
        raise ValueError("text must be a string")
    maximum_sentences = max(1, min(int(request.get("maximumSentences", 400)), 400))
    records = sentence_records(tokenizer, text)[:maximum_sentences]
    inputs = [benepar.InputSentence(words=r.words, space_after=r.spaces) for r in records]
    trees = list(parser.parse_sents(inputs)) if inputs else []
    findings: list[dict] = []

    # Patterns that live inside one sentence.
    for record, tree in zip(records, trees):
        lowered = [word.lower() for word in record.words]
        tagged = tree.pos()

        # "serves as" is only interesting as a verb phrase. POS gating avoids the
        # noun uses that a raw substring scan cannot distinguish.
        for index in range(len(lowered) - 1):
            if lowered[index] not in {"serve", "serves", "served", "serving", "stand", "stands", "stood"}:
                continue
            if lowered[index + 1] != "as" or not tagged[index][1].startswith("VB"):
                continue
            findings.append(destink_finding(
                text,
                record.token_starts[index],
                record.token_ends[index + 1],
                "serves-as-dodge",
                "medium",
                "A parsed verb phrase uses ‘serves as’ where ‘is’ may be enough",
                "Benepar confirmed that this is a verb phrase, not a noun mention. Try a plain ‘is’ or ‘was’ and keep the longer form only when it changes the meaning.",
            ))

        # A comma-set-off VBG clause at the end often restates significance without
        # giving the participle a clear actor.
        for index, (_, tag) in enumerate(tagged):
            if tag != "VBG" or index == 0:
                continue
            prefix = text[record.start:record.token_starts[index]]
            comma = prefix.rfind(",")
            if comma < 0:
                continue
            start = record.start + comma
            findings.append(destink_finding(
                text,
                start,
                record.end,
                "ing-tackon",
                "low",
                "Benepar found a trailing participial clause",
                "Check that the -ing clause has a clear actor and adds a distinct action. If it merely announces significance or repeats the main clause, cut it.",
            ))
            break

        # Tree-backed three-part coordination. The finding is the sentence because
        # constituency leaves do not retain a direct source span for each subtree.
        comma_count = sum(word == "," for word in record.words)
        conjunction_count = sum(tag == "CC" for _, tag in tagged)
        if comma_count >= 2 and conjunction_count >= 1:
            coordinated = any(
                label(node) in {"NP", "VP", "ADJP"}
                and sum(child.label() == "CC" for child in node if isinstance(child, Tree)) >= 1
                and len(node.leaves()) >= 3
                for node in subtrees(tree)
            )
            if coordinated:
                findings.append(destink_finding(
                    text,
                    record.start,
                    record.end,
                    "tricolon/comma-series",
                    "candidate",
                    "Benepar found a three-or-more-part coordinated series",
                    "A list of three may be exactly what the sentence needs. Review repeated three-part cadences across the piece; the pattern becomes conspicuous through density, not one use.",
                ))

        lowered_text = record.text.lower()
        if re.search(r"\bnot\s+(?:just|only)\b.+\bbut(?:\s+also)?\b", lowered_text):
            findings.append(destink_finding(
                text,
                record.start,
                record.end,
                "claude/mirrored-clauses",
                "low",
                "Benepar confirmed a mirrored not-only/but-also sentence",
                "The balanced frame can make an ordinary comparison sound staged. Lead with the stronger half when the contrast adds no information.",
            ))

    # Patterns whose signal is the relation between adjacent parsed sentences.
    self_questions: list[tuple[SentenceRecord, SentenceRecord]] = []
    reframes: list[tuple[SentenceRecord, SentenceRecord]] = []
    for index in range(len(trees) - 1):
        first, second = records[index], records[index + 1]
        first_tree, second_tree = trees[index], trees[index + 1]
        first_words = [word.lower() for word in first.words]
        second_words = [word.lower() for word in second.words]

        if first.text.rstrip().endswith("?"):
            strong = len(first_words) <= 5 and not has_finite_verb(first_tree)
            short_answer = len(second_words) <= (12 if strong else 6)
            if short_answer and (strong or not has_finite_verb(second_tree)):
                self_questions.append((first, second))

        first_reframe = (
            len(first_words) >= 3
            and first_words[0] in {"it", "this", "that"}
            and any(word in {"not", "n't"} for word in first_words)
            and any(tag.startswith("VB") for _, tag in first_tree.pos())
        )
        second_claim = (
            len(second_words) >= 2
            and second_words[0] in {"it", "this", "that"}
            and any(tag.startswith("VB") for _, tag in second_tree.pos())
            and not any(word in {"not", "n't"} for word in second_words)
        )
        if first_reframe and second_claim:
            reframes.append((first, second))

    question_severity = "high" if len(self_questions) >= 3 else "medium" if len(self_questions) >= 2 else "low"
    for first, second in self_questions:
        findings.append(destink_finding(
            text,
            first.start,
            second.end,
            "syntactic/self-posed-question",
            question_severity,
            "A parsed question is answered in the next short beat",
            "The question creates a reveal rather than opening an inquiry. State the answer directly, or keep the question and answer it fully.",
        ))

    for first, second in reframes:
        findings.append(destink_finding(
            text,
            first.start,
            second.end,
            "reframe",
            "medium",
            "Two parsed copular clauses form a not-X/it-is-Y reframe",
            "The first clause exists mainly to reject a weaker label. Start with the second claim unless the distinction genuinely matters.",
        ))

    findings.sort(key=lambda item: (item["location"], -item["length"], item["ruleId"]))
    return {"destinkFindings": findings}


def respond(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    model_path = os.environ.get("KISTULENTZ_BENEPAR_MODEL", "benepar_en3")
    parser = benepar.Parser(model_path)
    tokenizer = spacy.blank("en")
    tokenizer.add_pipe("sentencizer")
    for raw_line in sys.stdin:
        request_id = None
        try:
            request = json.loads(raw_line)
            request_id = request.get("id")
            command = request.get("command")
            if command == "ping":
                result = {"engine": ENGINE_NAME, "engineVersion": ENGINE_VERSION}
            elif command == "analyze":
                result = handle_analyze(parser, tokenizer, request)
            elif command == "destink":
                result = handle_destink(parser, tokenizer, request)
            else:
                raise ValueError(f"Unsupported command: {command}")
            respond({"id": request_id, "ok": True, **result})
        except Exception as error:  # The Swift side needs a structured failure.
            traceback.print_exc(file=sys.stderr)
            respond({"id": request_id, "ok": False, "error": str(error)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

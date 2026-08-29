# Kistulentz 0.9.3 — Friend Preview

Version 0.9.3 adds an optional, completely local English structural-analysis pack powered by Benepar. The base app remains fully usable without the pack and continues to use its native readability analysis.

## What is new

- Optional English Language Pack managed from Kistulentz Settings, with explicit installation and removal
- Deeper local sentence analysis for clause density, subordination, coordination, phrase depth, fragments, long noun phrases, stacked prepositional phrases, adverbs, and passive voice
- Orange advisory structure highlights that do not automatically rewrite prose
- Structural analysis in live Markdown editing, manuscript reports, individual EPUB references, and combined reference profiles
- Resumable bulk analysis for selected books, authors, and genres, designed for large Reference Libraries
- Cached per-book structural profiles stored in the user-chosen Markdown knowledge base
- Native Kistulentz analysis remains available whenever the optional pack is not installed or is temporarily unavailable
- A manually triggered, checksum-verified build workflow for both Apple-silicon and Intel language packs

## Privacy

Benepar analysis runs entirely on the Mac. Installing the optional pack downloads only its runtime and English model from Kistulentz's GitHub release. It does not send prose, EPUB excerpts, manuscript text, or analysis results to OpenAI, Anthropic, or another service. **Deepen w/ AI** remains a separate, previewed command.

## Important limits

Sentence-structure results are editorial signals, not grammar verdicts. They are intended to help an author inspect rhythm and complexity. The optional language pack is architecture-specific, may require more than 1 GB after installation, and can take longer on its first analysis while the local model starts.

## Friend-preview installation

Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. Drag the app to Applications. If macOS blocks the first launch, try once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or run Terminal commands.

The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. The optional language pack must match the Mac's processor architecture.

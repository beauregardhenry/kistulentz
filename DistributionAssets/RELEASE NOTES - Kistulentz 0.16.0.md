# Kistulentz 0.16.0 — De-stink Review and Local AI-Tell Detection

Version 0.16.0 adds a native De-stink Review pass, on-device AI-tell phrasing
detection in the readability engine, and per-project learning for declined
advisory flags — plus editor font/size choice and a manuscript-export bug fix.

## Added

- **De-stink Review**: a native pass across four tiers — word choice, sentence
  shape, formatting, and rhythm/repetition — for a selection, chapter,
  standalone document, or whole manuscript, with a deterministic weighted
  score and an optional Benepar-backed structural pass for deeper analysis.
  The rule taxonomy, report weighting, and portions of the phrase catalog are
  adapted from the MIT-licensed `lex00/sentences` de-stink linter and
  reimplemented natively in Swift; see `THIRD_PARTY_NOTICES.md`.
- Local, on-device detection of AI-sounding phrasing in the readability
  engine — correlative constructions ("isn't just X, it's Y"), stock
  rhetorical wind-ups and openers, stacked hedge words, filler "just"/
  "actually," and marketing staccato triads — surfaced as advisory
  highlights, never applied automatically.
- `Kistulentz Style.md` now learns per project: an advisory flag (AI-tell
  phrasing, adverbs, passive voice, and similar) stops appearing, live and in
  Local Polish, once it has been declined there a couple of times. It's
  recorded under "No longer flagged in this project" and reversible with
  Clear Learned Preferences.
- Editor font and size are now user-configurable in Settings.

## Fixed

- Footnote and endnote anchors that fell inside italic or underscore emphasis
  were sometimes swallowed by the emphasis regex during manuscript export;
  they're now correctly preserved.

## Under the hood

- `WritingProjectStore` has been reorganized and partially decomposed into
  independent per-concern stores (Research & Bibliography, Publication, Beta
  Readers, Style Learning, Search) for maintainability. No behavior change.
- Expanded automated test coverage across publication writers, the AI
  request-building layer, the keychain store, and De-stink analysis, with a
  one-way coverage ratchet enforced in CI.

## Privacy and compatibility

All De-stink Review and AI-tell detection analysis runs locally on the Mac;
no manuscript text is sent to OpenAI, Anthropic, Ollama, or another service
unless you separately choose and confirm an AI-backed command.

This universal application supports Apple silicon and Intel Macs running
macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry
does not yet have an Apple Developer account. The ZIP and DMG contain the
same application, first-open instructions, GPL license, corresponding-source
notice, and these release notes.

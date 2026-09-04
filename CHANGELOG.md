# Changelog

All notable changes to Kistulentz are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dated,
versioned sections are added as releases are tagged (see `RELEASE_CHECKLIST.md`); until then,
merged changes are recorded under [Unreleased].

## [Unreleased]

## [0.16.0] - 2026-09-04

### Added

- **De-stink Review**: a native pass that flags AI-writing tells across four tiers — word
  choice, sentence shape, formatting, and rhythm/repetition — with an optional Benepar-backed
  syntactic pass for deeper analysis on top of the always-on native rules. The rule taxonomy,
  report weighting, and portions of the phrase catalog are adapted from the MIT-licensed
  `lex00/sentences` de-stink linter and reimplemented natively in Swift; see
  `THIRD_PARTY_NOTICES.md`. (#7)
- Local, on-device detection of AI-sounding phrasing in the readability engine --
  correlative constructions, stock rhetorical openers, stacked hedge words, filler
  words, and marketing staccato triads -- surfaced as advisory highlights, never
  applied automatically. (#2)
- Project-local learning for advisory highlights: a flag stops appearing, live and
  in Local Polish, once declined a couple of times in that project, recorded in
  `Kistulentz Style.md` and reversible with Clear Learned Preferences. (#6)
- Editor font and size are now user-configurable in Settings. (#14, #15)

### Fixed

- Footnote and endnote anchors inside italic or underscore emphasis were
  sometimes swallowed by the emphasis regex during manuscript export. (#17)

### Changed

- Reorganized `WritingProjectStore.swift` into MARK-delimited sections by concern (Project
  Lifecycle, Chapters & Editing, Style Learning, Research & Bibliography, Systemic Revision,
  Publication, Outline, Bible, Beta Readers, Manuscript AI & Report, Snapshots, Search, and
  others) to make the ~1,700-line store easier to navigate. No behavior change. (#9)
- Decomposed `WritingProjectStore` further: Research & Bibliography, Publication,
  Beta Readers, Style Learning, and Search are now independent `ObservableObject`
  stores rather than extensions on the combined store. The remaining six concerns
  (Chapters & Editing, Outline, Systemic Revision, Manuscript Report, Bible,
  Snapshots) stay combined -- they're coupled by real production behavior that a
  future pass will need to address deliberately. No behavior change. (#19, #20)

### Testing

- CI now runs `swift test --enable-code-coverage` and enforces a one-way coverage ratchet via
  `scripts/check-coverage.sh`: the build fails if line coverage over the app sources (excluding
  `Views/`, which is exercised separately by the macOS UI regression suite) drops below the
  floor recorded in `coverage-baseline.txt`. (#8)
- Added direct unit tests for `KeychainStore` and `KeychainError`; raised the coverage baseline
  from 71.16% to 71.38%. (#10)
- Added direct unit tests for the three publication writers (`DOCXPublicationWriter`,
  `EPUBPublicationWriter`, `PDFPublicationWriter`) — 29 tests covering document structure,
  citation-mode-dependent notes sections, header/footer rules, cover-image handling,
  accessibility metadata, and print-bleed/recto-chapter pagination. (#11)
- Added direct unit tests for the AI request-building layer (`StructuredAIClient`,
  `ManuscriptAIService`, `SystemicRevisionAIService`) — 32 tests covering the exact request
  shape sent to each provider, response parsing, error-guard behavior, and the untrusted-AI-output
  verification in `SystemicRevisionAIService.deepen` that drops any proposed finding whose
  chapter path, revision pass, or excerpt doesn't check out against the real manuscript text.
  (#12)
- Added direct unit tests for `PublicationRenderer` and `DestinkService.analyze`.
  (#16, #18)

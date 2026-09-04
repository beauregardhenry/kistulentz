# Changelog

All notable changes to Kistulentz are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dated,
versioned sections are added as releases are tagged (see `RELEASE_CHECKLIST.md`); until then,
merged changes are recorded under [Unreleased].

## [Unreleased]

### Added

- **De-stink Review**: a native pass that flags AI-writing tells across four tiers — word
  choice, sentence shape, formatting, and rhythm/repetition — with an optional Benepar-backed
  syntactic pass for deeper analysis on top of the always-on native rules. The rule taxonomy,
  report weighting, and portions of the phrase catalog are adapted from the MIT-licensed
  `lex00/sentences` de-stink linter and reimplemented natively in Swift; see
  `THIRD_PARTY_NOTICES.md`. (#7)

### Changed

- Reorganized `WritingProjectStore.swift` into MARK-delimited sections by concern (Project
  Lifecycle, Chapters & Editing, Style Learning, Research & Bibliography, Systemic Revision,
  Publication, Outline, Bible, Beta Readers, Manuscript AI & Report, Snapshots, Search, and
  others) to make the ~1,700-line store easier to navigate. No behavior change. (#9)

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

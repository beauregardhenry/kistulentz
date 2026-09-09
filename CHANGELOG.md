# Changelog

All notable changes to Kistulentz are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dated,
versioned sections are added as releases are tagged (see `RELEASE_CHECKLIST.md`); until then,
merged changes are recorded under [Unreleased].

## [Unreleased]

## [0.17.1] - 2026-09-09

### Changed

- Project opening now constructs and validates a complete project snapshot before replacing the
  project currently on screen, and refuses to switch away from unsaved document changes.
- Project research, beta readers, style learning, search, and publication stores now persist
  through explicit injected operations rather than retaining weak links back to the project store.
- Editor sheet and document-import coordination now use explicit, independently tested state
  objects that reject obsolete dismissals and late results from superseded operations.
- Publish & Export state, plan reconciliation, preflight, history, and asynchronous export work now
  live in a dedicated view model instead of the SwiftUI view.
- Kistulentz now builds in Swift 6 language mode with complete concurrency checking.

### Fixed

- A project that fails during a late loading phase no longer partially replaces the open project.
- Cancelled or failed publication exports no longer record stale success results or leave incomplete
  submission-package folders behind.
- Removing or replacing a publication cover now refreshes the export plan and invalidates stale
  preflight results immediately.
- Apple spell-check callbacks and network-backed test doubles now cross concurrency boundaries
  without unsafe shared mutable state.

### Testing

- Added failure-injection coverage for transactional project loading and project sub-store saves.
- Added race and cancellation coverage for editor presentation, single-document imports, and
  publication export coordination.
- The complete native suite now runs under Swift 6 concurrency rules.

## [0.17.0] - 2026-09-08

### Changed

- Decomposed the main editor workspace into focused toolbar, readability, review, and
  polished-draft components while preserving the existing interface and commands.
- Split document importing into a small coordinator plus dedicated plain-text, attributed-text,
  HTML, and DOCX implementations without changing supported formats or conversion behavior.
- Moved Project Import Assistant state, ordering, tracked-change decisions, conversion,
  cancellation, and output operations into a dedicated view model.
- Split manuscript analysis into independent metrics, continuity/language, and Markdown-report
  components while retaining the existing `ManuscriptAnalyzer` interface and generated output.

### Testing

- Added direct tests for Project Import Assistant discovery and deduplication, state transitions,
  tracked-change decisions, reordering, removal, cancellation, partial-failure retry, and every
  output destination.
- Added component-wiring tests that ensure manuscript metrics, continuity results, and rendered
  reports are assembled unchanged through the public analyzer facade.
- Kept v0.17.0 under a strict behavior freeze: it contains no new writing workflow, file-format,
  AI, storage, or privacy behavior.

## [0.16.1] - 2026-09-08

### Added

- Added frozen older-project upgrade fixtures that verify migration, backup creation,
  clean reopening, and byte-for-byte preservation of manuscript Markdown.
- Added deterministic System Check dependencies so its complete report can be tested
  without contacting Ollama or launching the optional language-pack worker.
- Added a nontechnical friend-testing guide covering safe installation, representative writing
  workflows, optional recovery and AI checks, and privacy-safe problem reports.
- Added an upgrade-aware What’s New screen, available again from the Help menu.
- Diagnostic exports now include the app/build environment and privacy-safe prompts that help
  friends describe the shortest reproduction steps without including manuscript text.
- The opt-in Apple-silicon and Intel scale suite now records timings for large-project load,
  search, import, reference filtering, Project Polish, and cancellation, and fails when an
  explicit release budget is exceeded.

### Fixed

- Research Library mutations now keep the persisted index, visible records, managed attachment
  copies, and extracted-text indexes consistent when a save, copy, extraction, or cancellation
  fails.
- Manuscript search now cancels superseded work, ignores late results from older queries, clears
  progress on reset, and reports search failures without leaving the interface busy.
- Project Import now removes staged assets when its final combined output cannot be written.
- DOCX and EPUB handling now reject oversized, malformed, traversal, symlink, and duplicate-section
  cases without writing output or crashing.
- The What’s New screen now displays the application version instead of placeholder text.
- The Project Import Assistant now compresses vertically so its destination controls and action
  buttons remain reachable on smaller or scaled Mac displays.
- Project Polish now applies after its review sheet closes and registers one document-level Undo
  transaction; automatic Project Bible refreshes no longer hide that author-facing Undo action.
- Preferences from the former `com.beauhenry.kistuletz` identity now carry forward editor font,
  reference and research library locations, and persisted dismissed suggestions without replacing
  a newer value.

### Testing

- Added failure-injection and adversarial tests for Research Library persistence, managed-file
  rollback, indexing cancellation, search races, failed import writes, and unsafe document archives.
- The coverage gate now always creates a fresh profile before measuring, preventing a prior
  non-coverage build from producing stale or unreadable results.
- Added release-candidate interface checks for the exit paths in Project Organization, Systemic
  Revision, Project Research, Publish & Export, Reference Library, and Research Library, with the
  critical exit-path smoke checks also running on a native Intel release runner.
- Raised the non-view line-coverage ratchet from 71.38% to architecture-specific floors of
  74.01% on Apple silicon and 75.21% on Intel, avoiding false failures from instrumentation
  differences without weakening either platform's baseline.
- Expanded macOS UI coverage from basic smoke checks to document edit/save/reopen/Undo/Redo,
  crash recovery, stale-file refusal, real document imports, Project Import Assistant failure and
  cancellation paths, Project Polish stages and stale passages, provider controls, keyboard
  operation, and accessibility identifiers.

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

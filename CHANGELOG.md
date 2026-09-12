# Changelog

All notable changes to Kistulentz are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dated,
versioned sections are added as releases are tagged (see `RELEASE_CHECKLIST.md`); until then,
merged changes are recorded under [Unreleased].

## [Unreleased]

## [0.17.2] - 2026-09-12

Primarily an internal quality release — most of it is test coverage, dead-code removal, and
hot-path efficiency work with no behavior change — plus a handful of real fixes below.

### Fixed

- EPUB chapter titles were silently discarded on import: `<title>` always lives inside `<head>`,
  which is itself skipped when collecting body text, and the code that captured the title text
  was mistakenly skipped along with it — so every chapter's title silently fell back to
  "Section N" instead of its real title. This affected both the Reference Library's EPUB
  comparison feature and Research Library attachment extraction. (#40)
- `WritingProjectStore.createChapter` could crash if called while a project's manifest was
  unexpectedly absent; it now declines safely instead. (#44)
- Installing a new English language pack, importing documents into a project, and reorganizing
  project files could each understate a failure when their own automatic rollback also failed —
  potentially leaving `manifest.json`/`outline.json` or on-disk chapter files out of sync with no
  clear warning. All three now report a distinctly more severe message naming what could not be
  undone, instead of a message that implies the rollback was clean. (#47)
- The crash-recovery auto-save could fail (disk full, permissions) with no indication anywhere,
  silently disabling crash recovery for as long as the failure lasted. A failed save now surfaces
  once instead of doing nothing indefinitely. (#47)

### Changed

- `ReferenceLibraryStore.analyzeStructure` and `.deepen` now take injectable seams for the
  Benepar language-pack check, the structural analyzer, and the AI deepening service (mirroring
  `SystemCheckService`'s existing evaluator hooks), so their async pipelines can be tested without
  contacting the real language pack or the network. No behavior change. (#35)
- `EditorViewModel`'s structural-analysis pipeline now takes the same kind of injectable Benepar
  seam, for the same reason. No behavior change. (#38)
- Removed one confirmed-dead method (`ManuscriptEditCoordinator.resetBibleEditingBaseline`, never
  called from anywhere) and stopped several regex patterns on the live per-keystroke analysis path
  (word/sentence tokenization, Markdown stripping, protected-range detection) from recompiling on
  every call instead of once. No behavior change. (#46)
- `coverage-baseline.txt` is now raised automatically by a post-merge CI workflow instead of by
  each pull request, so two PRs open at once no longer conflict with each other over the same
  baseline number. (#34)

### Testing

- Closed the two largest remaining coverage gaps by absolute line count: `ReferenceLibraryStore`
  (67.6% → 95.6% including the dependency-injection change above) and `PublicationPlanning`
  (68.4% → 89.9%) — citation-key validation, structural-analysis and AI-deepening guards and async
  pipelines, and the destination-specific EPUB/print preflight checks (Apple Books, Kindle,
  IngramSpark) among them. (#30, #32, #33, #35)
- Added direct coverage for `RevisionDiff`'s long-manuscript diff path, `WritingAIService`'s guard
  clauses, `SystemCheckService`'s branch logic, `BetaReaderEngine`'s persona routing, `SearchStore`'s
  real (non-test-double) search implementation, `ManuscriptEditCoordinator`'s Bible-editing path,
  and `WritingProjectStore`'s snapshot-restore and publication branches. (#30, #31)
- Closed further real coverage gaps: the real (non-injected) `PublishExportViewModel`/
  `SystemCheckService` paths, `ManuscriptAnalyzer.context`'s truncation/sampling logic,
  `ResearchLibraryDisk`/`ResearchTextExtractor`, `AIRequestModels`' display and prompt-assembly
  logic, and `WritingProjectStore`'s lifecycle entry points, computed properties, and sub-store
  closure wiring. (#37, #39, #40, #41, #42, #43)
- Added a UI test covering the Manuscript Insights beta-reader flow end to end — the one
  remaining gap in the UI suite. (#45)
- Audited every `try!`/`as!`/force-unwrap outside `Views/`; all but one (the `createChapter` fix
  above) were already safe by construction. (#44)
- 466 → 599 tests. Line coverage (app sources outside `Views/`) rose from 83.61% to 88.64%.

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

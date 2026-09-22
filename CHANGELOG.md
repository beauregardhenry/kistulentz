# Changelog

All notable changes to Kistulentz are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dated,
versioned sections are added as releases are tagged (see `RELEASE_CHECKLIST.md`); until then,
merged changes are recorded under [Unreleased].

## [Unreleased]

## [0.23.10] - 2026-09-22

Two new ways to see your own progress -- Craft Examples and a writing-activity heatmap -- plus
two new De-stink checks and a reliability fix for Ollama.

### Added

- **Show a Strong Example.** On a flagged craft-judgment issue (an adverb, passive voice, a stock
  phrase, and similar), ask Kistulentz to find a short excerpt from your own Reference Library
  that handles the same craft element well, with a one-line note on why it works. Grounded by
  having the AI select an excerpt by id from ones Kistulentz already holds verbatim, rather than
  generating or reproducing quote text itself, so a hallucinated or misattributed quote is
  structurally impossible.
- **A calendar heatmap, streak, and daily word goal** in Your Writing Growth. A GitHub-style grid
  shows which days you wrote, a counter tracks consecutive days, and today's word count is shown
  against a goal you set in Settings. Presence on the heatmap (did you show up) and its color (how
  clean the writing was, ranked against your own history) are deliberately separate signals, so
  nothing here rewards raw word volume over writing quality.
- **Two new De-stink checks: anaphora and epistrophe.** De-stink Review now flags 3 or more
  consecutive sentences that all open the same way (anaphora) or all end the same way
  (epistrophe) -- a rhetorical device when it's deliberate, a tic when it isn't.

### Fixed

- Ollama requests no longer inherit `URLSession`'s 60-second default timeout. Local CPU inference
  on a larger model can legitimately take several minutes; a request that ran past 60 seconds was
  previously misreported as "Kistulentz could not reach Ollama," even when Ollama was reached and
  actively computing the whole time. Ollama requests now get a 300-second timeout, and a genuine
  timeout is reported distinctly from an unreachable Ollama.
- A sentence-splitting bug that silently dropped the first sentence of a paragraph immediately
  following a heading (or other non-punctuated line) from every discourse-tier De-stink rule, not
  only the two new ones above.

### Testing

- The verified suite now contains 801 Swift tests and 54 macOS interface tests.

## [0.23.9] - 2026-09-21

A small release: reliability hardening plus a refresh of the De-stink phrase catalog.

### Changed

- De-stink Review's phrase catalog is refreshed against the current upstream `lex00/sentences`
  de-stink linter, which has grown substantially since Kistulentz first adapted it in 0.16.0. New
  phrases across 5 existing rules (assistant voice, discourse markers, stock frames, technical
  vocabulary, fiction frames), 5 new excess-vocabulary words, and a new rule, Stock gesture
  cluster, which flags a density-gated cluster of ordinary gesture and atmosphere words (blinked,
  murmured, stillness, ...) that only reads as a tell when several show up together.

### Fixed

- The systemic revision scan's "in progress" flag now clears after its archive save completes
  rather than one line before it -- a defensive reorder, not an active bug fix (there was no
  `await` between the two lines, so nothing could interleave), matching the save-then-report-done
  pattern applied to the Reference Library fixes in 0.23.8.
- Kistulentz now also saves the current chapter, Bible, and outline directly during app
  termination, as a backstop alongside each project window's existing save-on-close path, in case
  a window's own teardown doesn't run (or hasn't finished) before the process exits during Quit.

### Testing

- The verified suite now contains 759 Swift tests and 54 macOS interface tests.

## [0.23.8] - 2026-09-20

### Fixed

- Deepen w/ AI (Reference Library) and manual book-metadata corrections now wait for the save to
  actually land on disk before reporting the action done, instead of reporting done as soon as the
  save was requested. Closes a narrow window where quitting Kistulentz at just the wrong moment
  could silently lose a freshly generated AI insight or an edited title/author/genre correction,
  with no error shown.

### Testing

- The verified suite now contains 754 Swift tests and 54 macOS interface tests.

## [0.23.7] - 2026-09-20

### Changed

- Self-Edit Exercises now sample adaptively instead of uniformly at random: practice leans toward
  the categories a writer's cross-project writing growth history shows they keep declining, rather
  than whatever a given document happens to flag most. A category with no recorded decisions yet
  -- including every category on a fresh install -- falls back to plain uniform sampling.

### Testing

- The verified suite now contains 754 Swift tests and 54 macOS interface tests.

## [0.23.6] - 2026-09-20

### Added

- Self-Edit Exercises (toolbar's highlights menu): a small, session-scoped set of the writer's own
  currently-flagged passages to attempt a fix on before Kistulentz reveals its own suggestion for
  comparison. Drawn only from issues already flagged in the open document, restricted to the same
  craft-judgment categories Practice Mode already treats as worth practicing. The writer's attempt
  is never overwritten, and finishing or skipping an exercise never affects the underlying flag.

### Fixed

- Closing every window without quitting, then reactivating Kistulentz from the Dock, no longer
  falls back to macOS's raw system "Open" panel -- it opens Kistulentz's own blank document instead.
- Quitting with a saved document open and relaunching no longer sometimes opens a second, genuinely
  blank window alongside the restored one.

### Testing

- The verified suite now contains 745 Swift tests and 54 macOS interface tests.

## [0.23.5] - 2026-09-18

### Added

- Practice Mode (toggle it in the toolbar's highlights menu): withholds one-click fixes --
  Accept, per-issue Rewrite, Apply All, and Polish -- for flag categories with a craft judgment
  behind them (adverbs, passive voice, hard sentences, structural complexity, complex phrases,
  AI-sounding phrasing, reference voice, avoided words), showing a diagnostic question instead so
  the author practices the edit themselves. Objective categories (spelling, grammar, continuity,
  an already-reviewed AI suggestion) stay fixable either way. Decline remains available always.
- A "Why this matters" disclosure on every local flag, explaining the underlying craft principle
  behind the category rather than just restating what's wrong. Collapsed by default so the
  Suggestions sidebar stays scannable.
- Cross-project writing growth tracking ("Your Writing Growth..." in the Projects menu): how many
  suggestions of each category have been accepted vs. declined, bucketed by month, independent of
  any single project's lifecycle. Local only; never included in exports, publication packaging,
  or any AI request preview.

### Testing

- The verified suite now contains 716 Swift tests and 53 macOS interface tests.

## [0.23.4] - 2026-09-17

### Changed

- The toolbar's leading icon is now Kistulentz's own orange quill-K mark instead of a generic
  placeholder (a plain rounded square with an SF Symbol pencil icon). The "Kistulentz" text next
  to it is unchanged and stays a native text label, not part of the icon artwork.

### Testing

- The verified suite now contains 701 Swift tests and 53 macOS interface tests.

## [0.23.3] - 2026-09-17

### Fixed

- Replaced the app icon's source artwork with a version that has a real transparent background
  around the rounded-square mark, instead of a flat white export margin. The previous source's
  corners were opaque white inset from the canvas edge, which macOS's own rounded-corner mask
  (applied on top at render time) could reveal as a faint white sliver at each corner.

### Testing

- The verified suite now contains 701 Swift tests and 53 macOS interface tests.

## [0.23.2] - 2026-09-16

### Added

- Kistulentz now has its own app icon (a navy rounded-square mark with an orange quill-feather
  "K"), used by both the manual application build and the Xcode project. Previously there was no
  custom icon at all; every build fell back to the generic macOS app icon.

### Testing

- The verified suite now contains 701 Swift tests and 53 macOS interface tests.

## [0.23.1] - 2026-09-16

### Fixed

- Fixed a bug where quitting Kistulentz with every window already closed (not just a genuine
  first-ever launch) reliably showed AppKit's own system Open panel on the next launch instead
  of Kistulentz's own Welcome screen, every time. `KistulentzAppDelegate` now explicitly opens a
  document ahead of AppKit's own "is there anything to resume" decision, so that fallback has
  nothing left to trigger on.

### Testing

- The verified suite now contains 701 Swift tests and 53 macOS interface tests.

## [0.23.0] - 2026-09-16

### Added

- Kistulentz Style.md has a new "### Words to avoid" section: list a word or short phrase as
  its own bullet, and Kistulentz's local checks will flag it while you write — no AI, no
  network — the same way it already flags adverbs or passive voice. Previously, nothing in the
  style guide fed the local, offline checks at all; only optional AI-backed Rewrite/Deepen
  requests ever read it, despite the file's own text inviting "words to avoid" since it was
  first introduced.

### Fixed

- Fixed a real, independent bug found while verifying the above: "Edit Kistulentz Style…"
  could open to a blank editor instead of a project's real style guide, and any style-guide
  content became invisible to Kistulentz at runtime past the first render. The underlying
  `styleLearningStore` reference was silently rebinding to a disconnected, never-populated
  object on every subsequent view update.

### Testing

- The verified suite now contains 701 Swift tests and 53 macOS interface tests.

## [0.22.2] - 2026-09-16

### Fixed

- Kistulentz now remembers which project you had open and reopens it automatically after
  quitting and relaunching, the same way document resume already worked. A project is a folder
  loaded on top of the window's single underlying document, invisible to AppKit's own window
  restoration — quitting while a project was open silently lost it on relaunch, back to whatever
  plain document had last been open (or the system Open-panel fallback again, if there'd never
  been one). This was a real, previously-missing feature, not a regression from 0.22.0 or 0.22.1.
  A project that's since been moved or deleted is forgotten silently, with no error dialog.

### Testing

- The verified suite now contains 687 Swift tests and 53 macOS interface tests.

## [0.22.1] - 2026-09-16

### Fixed

- Fixed the actual root cause of 0.22.0's own launch-reliability fix falling short:
  `KistulentzAppDelegate` never implemented `applicationSupportsSecureRestorableState`. Since
  macOS 12, AppKit treats an app delegate that omits this method as opting out of state
  restoration entirely, so there was never anything to resume — meaning the system "nothing to
  resume" Open panel appeared on every single launch, not only a genuine first-ever one, which
  is exactly what 0.22.0 was supposed to have already fixed. Confirmed directly against a real
  installed build, both before this fix (the panel appeared every launch) and after (a saved
  document now reopens automatically, with no system panel).

### Testing

- The verified suite now contains 683 Swift tests and 53 macOS interface tests.

## [0.22.0] - 2026-09-16

### Fixed

- Kistulentz now reliably reopens a document or project across a normal quit and relaunch,
  including for a user whose own System Settings has "Close windows when quitting
  applications" turned on. Without this, AppKit's own "nothing to resume" fallback for a
  document-based app — the plain system Open panel, with its own "New Document" button — could
  appear at launch instead of anything Kistulentz itself draws, ahead of the Welcome landing
  page. A truly first-ever launch (nothing has ever existed to resume) can still show that
  system panel once; FIRST OPEN's install notes now say what to do if that happens.

### Testing

- The verified suite now contains 682 Swift tests and 53 macOS interface tests.

## [0.21.0] - 2026-09-15

### Added

- An AI provider error (a missing or invalid API key, a provider HTTP error, an unreachable
  Ollama, or a network failure reaching one) now offers an "Open Settings" button directly in
  the alert.
- The Welcome screen now doubles as a landing page: it reappears on every launch, not only the
  first, in front of whatever document or project the previous session left open.

### Fixed

- A file-chooser sheet (the Research Library folder picker and others) left open when Kistulentz
  quits no longer reappears on the next launch ahead of anything the app itself draws.
- The De-stink toolbar icon no longer tracks the System Settings accent color; it now renders
  the same as every other icon in that row regardless of the chosen accent color.
- Adding a Research Library attachment now reports distinctly when an automatic rollback from a
  failed attempt cannot fully complete, instead of silently leaving an orphaned file behind.

### Changed

- Systemic revision persistence now uses the same shared atomic writer as other project
  metadata.
- `EditorWorkspace.swift`, the largest file in the app, is split into per-concern files with no
  change in behavior.

### Testing

- Added CI checks that hold `as!`, `fatalError(`, `print(`, and TODO/FIXME comment markers at a
  fixed floor of zero, and that the Swift and Xcode UI test counts only move up, the same shape
  as the existing coverage ratchet.
- Added a genuine reproduction of the Research Library attachment rollback also failing, not
  just the attachment add itself failing.
- The verified suite now contains 680 Swift tests and 53 macOS interface tests.

## [0.20.0] - 2026-09-14

### Changed

- Manuscript, project, import, recovery, reference, research, diagnostics, and publication
  persistence now uses one atomic writer with explicit staging, commit, and cleanup behavior.
- Long document import, project import, publication export, reference import, and structural
  analysis operations now share one cancellation and stale-result boundary.
- Large publication, organization, and research screens have begun moving self-contained editors
  and sheets into focused components without changing their workflows.

### Security

- DOCX, ODT, and EPUB readers now reject traversal and absolute paths, symbolic links, canonical
  filename collisions, excessive entry counts, oversized entries, excessive expanded data, and
  extreme compression ratios before reading or extracting archive contents.
- Tagged release builds now publish SLSA build-provenance and SPDX SBOM attestations through
  GitHub Actions. The ZIP and DMG include an SPDX 2.3 software bill of materials, which is also a
  separately checksummed release asset.

### Testing

- Added deterministic archive-security tests for traversal, symlinks, collisions, entry and total
  size limits, extreme compression, and malformed metadata.
- Added disk-full, interrupted-commit, rollback-cleanup, unsafe-destination, cancellation, and
  stale-result tests for the new shared primitives.
- Added opt-in timing budgets for rapid typing and large paste analysis alongside the existing
  large-project search, Project Polish, reference filtering, and publication measurements.

## [0.19.0] - 2026-09-13

### Added

- Settings now has a "Custom Fonts" section for adding your own TrueType or OpenType font
  files. Added fonts become available everywhere Kistulentz offers a font choice, including
  the editor and publication layouts, without a separate Font Book install.
- A font a project's publication layout references is now bundled into that project's own
  hidden metadata folder, so opening the project on a different Mac gives access to the font
  file without separately adding it there first.

### Testing

- Added coverage for adding, removing, and re-registering custom fonts (including duplicate
  detection and rollback on a failed manifest save), for bundling a referenced font into a
  project and re-registering a project's already-bundled fonts, and an end-to-end interface
  test for the Settings Add/Remove flow.
- The verified suite now contains 656 Swift tests and 52 macOS interface tests. App-source line
  coverage outside the view layer is approximately 89.4%.

## [0.18.1] - 2026-09-13

### Fixed

- Dragging an outline item onto another item or a new parent now correctly rolls back the
  in-memory outline if the follow-up chapter-list sync fails, matching how reordering a sibling
  with Move Earlier/Later already behaved.
- A failed "Deepen with AI" manuscript report no longer gets silently written to disk on the
  next successful analysis after the user was told the request failed.
- Project-format migration on open, file reorganization, systemic revision, and heading splits
  now report it distinctly when an automatic rollback from a failed attempt cannot fully
  complete, instead of a message implying the change was cleanly undone.
- HTML import now rejects an oversized embedded image by its encoded size before decoding it,
  rather than after.

### Testing

- Added end-to-end coverage for every rollback path above, including a genuine reproduction of
  project-migration-then-rollback both failing at once.
- Added coverage for HTML-import embedded images: successful, malformed, and non-image data URIs.
- Removed dead AI-review "Polish" code path (superseded by always-local Polish) along with its
  now-obsolete tests, and extracted two shared helpers (asset writing during import, rollback
  bookkeeping) that had previously been hand-copied across several call sites.
- The verified suite now contains 643 Swift tests and 51 macOS interface tests. App-source line
  coverage outside the view layer is approximately 89.6%.

## [0.18.0] - 2026-09-13

### Fixed

- Snapshot creation now removes an uncommitted manuscript copy when its history index cannot be
  saved. Reference-library regeneration commits its JSON index only after every derived Markdown
  file succeeds, and publication settings remain at their last persisted value after a failed
  save.
- A publication cover collision with an existing folder is refused without deleting that folder
  or its contents.
- Managed research attachments can no longer use corrupt relative paths to read or delete files
  outside their library. Imported asset names also remove path traversal, separators, and control
  characters before anything is written.
- HTML import strips executable link schemes and event-handler attributes. Malformed BibTeX, RIS,
  CSL-JSON, ODT, RTF, and RTFD inputs are rejected without producing partial sources or Markdown.
- Long-manuscript AI context now stays within its requested character budget, distributes space
  across every selected section, and always samples both the beginning and ending.
- Large De-stink reviews now expose a working Cancel action and discard obsolete background
  results instead of continuing to occupy the editor.

### Testing

- Added transactional failure tests for snapshots, publication metadata and assets, reference
  indexes, imported assets, and managed research attachments.
- Added hostile and malformed import coverage for HTML, EPUB, bibliography exchange, office,
  rich-text, path traversal, filename collisions, and temporary-file cleanup.
- Added provider-boundary tests for empty, oversized, wrong-purpose, malformed, schema-invalid,
  and fenced-JSON writing requests, plus deeper local beta-reader and manuscript-context coverage.
- Added a frozen upgrade-fixture matrix covering every prior project schema without changing
  manuscript Markdown.
- Added opt-in endurance tests for repeated edit/snapshot/search/reopen cycles, repeated publication
  exports, 2,000-document projects, 5,000-book reference libraries, and 1,000-file imports.
- Added nine end-to-end interface journeys covering project search, Bible and beta-reader
  persistence, named snapshots, reading-grade preferences, English-pack failure and retry, DOCX
  and PDF publication, De-stink filtering/navigation, and large-analysis cancellation. UI tests now
  use isolated preferences so they cannot open or modify a tester's real libraries.
- The verified suite now contains 629 Swift tests and 51 macOS interface tests. App-source line
  coverage outside the view layer is 88.85%.

## [0.17.3] - 2026-09-13

### Fixed

- The readability grade indicator showed "On target" (green) for a document far *below* the
  target grade — e.g. 5th-grade writing against a 12th-grade target — because it only checked
  whether the current grade was too high, never too low. It now shows "Below target" when the
  gap runs the other way, using the same tolerance in both directions.
- **Polish** used to silently switch to sending the draft to whichever AI provider happened to be
  configured (even one set up only for an unrelated feature like Selection Rewrite), instead of
  always running its local, rule-based review. Polish now always runs locally regardless of
  provider configuration; AI-assisted rewriting stays available separately through Rewrite.
- The De-stink toolbar button rendered in a muted grey rather than the accent-tinted look of
  every other toolbar control, because it was the only one implemented as a plain borderless
  button rather than a borderless-style menu. Its resting tint now matches its siblings.

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

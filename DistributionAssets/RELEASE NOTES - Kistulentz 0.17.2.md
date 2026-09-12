# Kistulentz 0.17.2 — Test Coverage, Reliability, and CI Hardening

Version 0.17.2 is primarily an internal quality release — most of it is test coverage, dead-code
removal, and efficiency work with no visible change. It also includes a few real fixes, described
below.

## Fixed

- **EPUB chapter titles are no longer silently discarded.** Importing an EPUB (for reference
  comparison, or as a Research Library attachment) used to always show each chapter as
  "Section 1", "Section 2", and so on, instead of that chapter's real title — a parsing bug that
  had gone unnoticed because nothing checked an individual chapter's title directly. Chapter
  titles now come through correctly.
- **Recovering from a failed operation is more honest when the recovery itself runs into
  trouble.** Installing the English language pack, importing documents into a project, and
  reorganizing project files all try to undo a partial change automatically if something goes
  wrong partway through. Previously, if that automatic undo also hit a problem, Kistulentz would
  still just report the original error — leaving you to discover on your own that something
  hadn't fully reverted. All three now tell you plainly when the undo itself didn't fully
  succeed, and what to check.
- **Crash recovery no longer fails invisibly.** The background snapshot that powers crash
  recovery could, in rare cases (a full disk, a permissions problem), silently stop saving with
  no indication anywhere. Kistulentz now tells you once if that happens, instead of leaving you to
  discover it only after a crash.
- A rare crash in chapter creation is now a safe no-op instead.

## Test coverage

- Closed the two largest remaining coverage gaps by absolute line count: `ReferenceLibraryStore`
  and `PublicationPlanning`. Coverage now includes citation-key validation and deduplication,
  the reference-library import/reimport pipeline, structural-analysis and AI-deepening guards,
  export-plan reconciliation, and the destination-specific EPUB and print preflight checks for
  Apple Books, Kindle, and IngramSpark.
- Added direct coverage for the long-manuscript diff path, the writing-AI service's guard
  clauses, the System Check report's branch logic, beta-reader persona routing, the project
  search store's real (non-test-double) implementation, the manuscript edit coordinator's
  Bible-editing path, and the writing project store's snapshot-restore and publication branches.
- Closed further coverage gaps in the publish/export view model, System Check, the AI-context
  sampling logic, the research library's disk layer, AI request assembly, and the writing
  project store's lifecycle and sub-store wiring — including a UI test for the Manuscript
  Insights beta-reader flow, the one remaining gap in the interface test suite.
- Audited every forced unwrap outside the view layer; all but one (behind the chapter-creation
  fix above) were already safe.
- Line coverage over the app sources outside the view layer rose from 83.61% to 88.64%, and the
  test suite grew from 466 to 599 tests, all passing.

## Testability

- `ReferenceLibraryStore` and `EditorViewModel`'s structural-analysis and AI-deepening pipelines
  now accept injectable seams for their language-pack check, analyzer, and deepening service,
  matching the pattern already used by System Check. This is a testability change only;
  production behavior is unchanged.

## CI

- The test-coverage floor is now raised automatically by a post-merge workflow instead of by each
  pull request, so two pull requests open at the same time no longer conflict with each other
  over the recorded baseline.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

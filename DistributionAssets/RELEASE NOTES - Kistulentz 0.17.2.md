# Kistulentz 0.17.2 — Test Coverage and CI Hardening

Version 0.17.2 is an internal quality release. It adds no writing workflow and changes no
supported format, storage rule, AI choice, or privacy behavior.

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
- Line coverage over the app sources outside `Views/` rose from 83.61% to 86.71%, and the test
  suite grew from 466 to 533 tests, all passing.

## Testability

- `ReferenceLibraryStore`'s structural-analysis and AI-deepening pipelines now accept injectable
  seams for their language-pack check, analyzer, and deepening service, matching the pattern
  already used by System Check. This is a testability change only; production behavior is
  unchanged.

## CI

- The test-coverage floor is now raised automatically by a post-merge workflow instead of by each
  pull request, so two pull requests open at the same time no longer conflict with each other
  over the recorded baseline.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

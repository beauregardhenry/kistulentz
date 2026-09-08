# Kistulentz 0.16.1 — Storage, Cancellation, and Archive Hardening

Version 0.16.1 is a hardening release. It does not add a major writing workflow;
it makes the existing local libraries, search, indexing, import, upgrade, and
publication paths safer under failure and cancellation.

## Fixed

- Research Library changes now persist their index before removing managed
  attachments. If persistence fails, the existing record and file remain intact.
- A managed attachment copied during a failed add is rolled back instead of being
  orphaned in the library folder.
- Cancelled attachment indexing leaves a retryable unindexed attachment and cleans
  up any extracted-text artifact that could not be committed to the index.
- Manuscript search now cancels superseded work, clears progress on reset, reports
  failures consistently, and ignores late results from an older query.
- Project Import removes staged assets when the final combined Markdown output
  cannot be written.
- The What’s New title now displays the actual application version.

## Defensive document handling

- DOCX import rejects oversized files before extraction, unsafe archive paths,
  and malformed document XML without creating output.
- EPUB reference and publication handling reject unsafe archive links and
  duplicate section identifiers with an actionable error instead of crashing.
- Long-running local text extraction checks cancellation before and during work.

## Release safeguards

- Added deterministic failure-injection tests for Research Library persistence,
  managed-file rollback, indexing cancellation, Project Import cleanup, search
  races, search cancellation, and search errors.
- Added a frozen project fixture from the older format. The upgrade test verifies
  migration, pre-migration backup creation, reopening, and byte-for-byte
  preservation of manuscript Markdown.
- The opt-in 2-million-word, 2,000-document, 1,000-file-import, and 5,000-book
  scale suite now enforces explicit time and cancellation budgets. Each budget can
  be deliberately recalibrated through a named environment variable.
- Added interface checks that Project Organization, Systemic Revision, Project
  Research, Publish & Export, Reference Library, and Research Library always keep
  a usable exit path at the release-candidate window size.
- The complete System Check can now be tested without contacting Ollama or starting
  the optional language-pack worker.

## Privacy and compatibility

All safeguards in this release run locally. No writing is sent to an AI provider
unless the author separately chooses and confirms an AI-backed command.

This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet
have an Apple Developer account. The ZIP and DMG contain the same application,
first-open instructions, GPL license, corresponding-source notice, and these
release notes.

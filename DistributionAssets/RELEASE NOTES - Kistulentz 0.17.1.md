# Kistulentz 0.17.1 — Transaction and Concurrency Hardening

Version 0.17.1 tightens the boundaries between project loading, feature storage,
editor presentation, importing, and publication export. It is a hardening release:
the existing writing, format, provider, storage, and privacy choices remain intact.

## Safer project and feature state

- A new project is fully loaded and validated before it replaces the project on screen.
- If a late loading step fails, the current project and its document remain intact.
- Kistulentz refuses to switch projects while the current document has unsaved changes.
- Research, beta-reader, style-learning, search, and publication state now save through
  explicit operations that can fail and be tested independently.

## Editor and import coordination

- One presentation coordinator now owns the editor’s sheets and rejects obsolete
  dismissals from a sheet that has already been replaced.
- Single-document imports have a dedicated cancellable coordinator.
- Results from cancelled or superseded imports cannot overwrite the current document.

## Publication export safety

- Publish & Export now keeps its plan, preflight, history, and asynchronous work in a
  dedicated view model.
- Temporary export order and exclusions survive plan refreshes while missing source files
  remain safely excluded.
- A visible Cancel Export action stops active work.
- Cancelled or failed exports cannot record a stale success and incomplete submission
  packages are removed.
- Cover changes immediately refresh the plan and invalidate obsolete preflight results.

## Swift 6 and regression protection

- The app and complete native test suite now build in Swift 6 language mode.
- Asynchronous Apple spell-check callbacks and test network handlers use explicit,
  concurrency-safe value boundaries.
- New tests cover transactional loading, project sub-store persistence, competing sheets,
  stale imports, export plan reconciliation, cancellation, failure, and success recording.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an
AI-backed command. This universal application supports Apple silicon and Intel Macs
running macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry
does not yet have an Apple Developer account.

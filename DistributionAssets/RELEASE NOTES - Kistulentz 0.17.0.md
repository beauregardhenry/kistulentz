# Kistulentz 0.17.0 — Behavior-Frozen Architecture Refactor

Version 0.17.0 reorganizes several of Kistulentz’s largest source files before
the final 1.0 hardening cycle. It intentionally adds no writing workflow and
changes no supported format, storage rule, AI choice, or privacy behavior.

## Editor organization

- The main editor workspace now composes focused toolbar, readability-sidebar,
  review-sidebar, and polished-draft-review components.
- Toolbar commands are grouped in one explicit action object, making command
  wiring easier to verify without changing menus, shortcuts, or labels.

## Document and project importing

- The document import service is now a small safety and output coordinator.
- Plain-text, attributed-text (RTF, RTFD, and ODT), HTML, and DOCX conversion
  implementations live in dedicated source files.
- Project Import Assistant state, ordering, tracked-change decisions, conversion,
  retry, cancellation, preview, and output operations now live in a dedicated
  observable view model.

## Manuscript analysis

- Per-document readability and pacing metrics are calculated by a focused metrics
  component.
- Entities, terminology, repeated phrases, timeline markers, claims, and
  continuity findings are handled by a separate continuity component.
- Markdown manuscript reports and Bible blocks are rendered independently behind
  the unchanged `ManuscriptAnalyzer` entry point.

## Regression protection

- Added direct tests for Project Import Assistant discovery and deduplication,
  reordering, removal, reset, tracked-change decisions, cancellation,
  partial-failure retry, and every output destination.
- Added component-wiring tests for manuscript metrics, continuity findings, and
  report rendering.
- Existing real-format import, manuscript, native, UI, coverage, scale, and
  universal-package release gates remain required.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an
AI-backed command. This universal application supports Apple silicon and Intel
Macs running macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau
Henry does not yet have an Apple Developer account.

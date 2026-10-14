# Kistulentz 0.24.1 — Import and Outline Fixes

Version 0.24.1 is a small release: two bug fixes found by new test coverage, plus internal
cleanup.

## Fixed

- **Older text files now import with their accents intact.** Markdown, plain-text, and HTML files
  saved in the older Latin-1 encoding used to import with garbled characters in the imported
  copy, because Kistulentz tried UTF-16 before Latin-1 and UTF-16 decoding accepts almost any
  bytes. UTF-16 is now tried only when a file starts with a byte-order mark. Your original files
  were never modified. One consequence: UTF-16 text with no byte-order mark is no longer
  recognized, which is rare.
- **No stray files when an outline item disappears.** Adding a chapter, scene, or section under
  an outline item that was removed in the meantime used to leave an unlisted Markdown file in
  your project folder. Kistulentz now checks the parent first and tells you the item no longer
  exists.

## Changed

- Removed two unused code paths, and moved the calendar heatmap's week-grid date math into a
  place where it is unit-tested (including across daylight-saving changes). No user-visible
  behavior changes.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

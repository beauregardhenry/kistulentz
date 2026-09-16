# Kistulentz 0.21.0 — Landing Page and Smaller Fixes

Version 0.21.0 is a focused round of interface fixes and reliability work, most of it reported
directly during friend testing.

## Added

- An AI provider error (a missing or invalid API key, a provider HTTP error, an unreachable
  Ollama, or a network failure reaching one) now offers an "Open Settings" button directly in
  the alert, instead of leaving you to find Settings on your own.
- The Welcome screen now doubles as a landing page: it reappears on every launch, not only the
  first, in front of whatever document or project the previous session left open.

## Fixed

- A file-chooser sheet (the Research Library folder picker and others) left open when Kistulentz
  quits no longer reappears on the next launch ahead of anything the app itself draws — a real
  bug in how macOS's own window-state restoration was interacting with these transient panels.
- The De-stink toolbar icon no longer tracks the System Settings accent color; it now renders
  the same as every other icon in that row regardless of the chosen accent color.
- Adding a Research Library attachment now reports distinctly when an automatic rollback from a
  failed attempt cannot fully complete, instead of silently leaving an orphaned file behind —
  closing out the same class of rollback-reliability fix made across seven other spots in 0.18.1.

## Internal quality

- Systemic revision persistence now uses the same shared atomic writer as other project
  metadata.
- Added CI checks that hold `as!`, `fatalError(`, `print(`, and TODO/FIXME comment markers at a
  fixed floor of zero, and that the Swift and Xcode UI test counts only move up, the same shape
  as the existing coverage ratchet.
- `EditorWorkspace.swift`, the largest file in the app, is split into per-concern files with no
  change in behavior.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

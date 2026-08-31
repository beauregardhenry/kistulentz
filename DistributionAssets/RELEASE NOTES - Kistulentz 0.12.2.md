# Kistulentz 0.12.2 — Reliability and UI-Test Foundation

Version 0.12.2 hardens the local setup, document import, diagnostics, and Research Library paths before the next writing-feature releases.

## File panels that remain usable

- Research Library folder selection is presented as a Finder sheet attached to the active Kistulentz window
- Authors can select an existing folder, create a new one, or cancel and return to the library
- The Research Library retains both Close and Escape exits
- Diagnostic export uses the same nonblocking save-sheet behavior

## Safer optional components

- Ollama becomes the active writing provider only after its downloaded model is detected and verified
- A failed follow-up detection leaves the current provider untouched and explains how to recover
- Benepar catalog, HTTP, checksum, archive, architecture, and unsafe-path failures cannot replace an existing working pack
- Native manuscript reports and Bible updates no longer wait for a cold optional Benepar worker

## Import and interface regression testing

- A minimal checked-in Xcode project hosts real macOS UI tests while Swift Package Manager remains the canonical build
- UI coverage exercises first-launch dismissal, Research Library folder cancellation and closure, and diagnostic export cancellation
- Permanent macOS-saved DOCX, RTF, RTFD, HTML, ODT, and TXT fixtures supplement generated packages for tracked changes, comments, notes, tables, links, and images
- GitHub release-candidate testing now requires the UI suite as well as native Intel, Apple-silicon, and universal-package checks

## Verification

- Kistulentz remains local-first, ad-hoc signed, GPL-3.0-or-later software for macOS Sequoia 15 or later
- Release packaging still produces one universal application for Apple silicon and Intel Macs

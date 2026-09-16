# Kistulentz 0.22.0 — Reliable Relaunch

Version 0.22.0 fixes a launch-reliability issue reported directly during friend testing.

## Fixed

- Kistulentz now reliably reopens a document or project across a normal quit and relaunch,
  including for a user whose own System Settings has "Close windows when quitting
  applications" turned on. Without this, AppKit's own "nothing to resume" fallback for a
  document-based app — the plain system Open panel, with its own "New Document" button — could
  appear at launch instead of anything Kistulentz itself draws, ahead of the Welcome landing
  page.

A truly first-ever launch (nothing has ever existed to resume yet) can still show that system
panel once — this is normal, confirmed macOS behavior for document-based apps generally, not a
Kistulentz-specific defect (Apple's own TextEdit shows the identical panel under the same
condition). If you see it, click New Document once; it will not happen again after that.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

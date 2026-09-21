# Kistulentz 0.23.9 — Reliability Hardening

Version 0.23.9 is a small, backend-only reliability release. There are no new features and no
change to how Kistulentz looks or behaves day to day.

## Fixed

- **Project saves now also flush directly when you quit.** Kistulentz already saves your current
  chapter, Bible, and outline when a project window closes normally. This release adds a second,
  independent save pass during app termination itself, as a backstop in case a window's own
  close-time save doesn't get a chance to run before the app exits.
- **A defensive reorder in the systemic revision scan.** The scan's "in progress" indicator now
  clears after its results are saved, not one line before -- not an active bug (there was nothing
  that could interleave between the two), just closing off a pattern that has caused real problems
  elsewhere in the app.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

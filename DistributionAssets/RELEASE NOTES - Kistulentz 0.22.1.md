# Kistulentz 0.22.1 — Reliable Relaunch, For Real This Time

Version 0.22.1 fixes the actual root cause of a launch-reliability bug that 0.22.0 was
supposed to have already fixed.

## Fixed

- 0.22.0 shipped a fix for Kistulentz sometimes showing a plain macOS file browser instead of
  your last document or project at launch, but missed the load-bearing piece: the app never told
  macOS it supports state restoration in the first place. The practical effect was that the
  system panel kept appearing — now confirmed to be on every single launch, not just an
  occasional or first-ever one. Kistulentz now reliably reopens your last document or project
  after quitting and relaunching, including if your own System Settings has "Close windows when
  quitting applications" turned on.

A truly first-ever launch (nothing has ever existed to resume yet) can still show that system
panel once — this is normal, confirmed macOS behavior for document-based apps generally, not a
Kistulentz-specific defect. If you see it, click New Document once; it will not happen again
after that.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

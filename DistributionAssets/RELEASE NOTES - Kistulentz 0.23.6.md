# Kistulentz 0.23.6 — Self-Edit Exercises and a Smoother Launch

Version 0.23.6 adds a new way to practice editing on your own material, and fixes two rough edges
in how Kistulentz starts up.

## Added

- **Self-Edit Exercises.** A new entry in the toolbar's highlights menu, next to Practice Mode.
  It samples a small set of your own currently-flagged passages, lets you attempt a fix in a
  scratch field, then reveals Kistulentz's own suggestion for comparison only after your attempt.
  Exercises are drawn only from issues already flagged in the open document -- never invented or
  fetched -- and finishing or skipping one never changes how that flag appears in the regular
  editor view.

## Fixed

- Closing every window without quitting, then reactivating Kistulentz from the Dock, no longer
  falls back to macOS's raw system "Open" panel -- it opens Kistulentz's own blank document instead.
- Quitting with a saved document open and relaunching no longer sometimes opens a second, genuinely
  blank window stacked on top of the restored one.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

# Kistulentz 0.17.3 — Readability, Polish, and Toolbar Fixes

## Fixed

- **The readability grade indicator no longer misreads writing far below the target grade.** It
  previously only checked whether the current grade was too *high*, so a document written well
  below the target — for example, 5th-grade prose against a 12th-grade target — showed a green
  "On target" badge despite the mismatch. It now shows "Below target" when the gap runs that
  direction, using the same tolerance it already used for writing that's too advanced.
- **Polish now always runs locally, with no exceptions.** It used to silently switch to sending
  the whole draft to whichever AI provider happened to be configured — even one set up only for
  an unrelated feature like Selection Rewrite — instead of running its safe, local, rule-based
  review. Polish always runs on this Mac now, regardless of provider configuration.
  AI-assisted rewriting stays available separately, through Rewrite.
- **The De-stink toolbar button now matches the rest of the toolbar.** It previously rendered in
  a muted grey instead of the accent-tinted look every other toolbar control has, because it was
  built differently from its siblings. Its resting color now matches.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

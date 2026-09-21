# Kistulentz 0.23.9 — Reliability Hardening and a De-stink Refresh

Version 0.23.9 is a small release: reliability hardening plus a refresh of the De-stink Review
phrase catalog.

## Changed

- **De-stink Review's phrase catalog is refreshed from its upstream source.** Kistulentz adapted
  the `lex00/sentences` de-stink linter's rule taxonomy back in 0.16.0; this pulls forward what's
  new there since. New phrases across five existing rules, five new excess-vocabulary words, and a
  new rule -- Stock gesture cluster -- that flags a cluster of ordinary gesture and atmosphere
  words (blinked, murmured, stillness, and similar) that only reads as a tell when several of them
  show up together on the page.

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

# Kistulentz 0.23.8 — More Reliable Reference Library Saves

Version 0.23.8 closes a narrow but real data-loss window in the Reference Library.

## Fixed

- **Deepen w/ AI and manual book-metadata corrections now confirm the save before reporting
  done.** Previously, both operations could report themselves finished as soon as a save was
  requested, not once it actually landed on disk. If Kistulentz quit in that gap -- normally a
  matter of milliseconds, but a real window all the same -- a freshly generated AI insight or an
  edited title/author/genre correction could be silently lost, with no error shown. Both now wait
  for the write to genuinely complete first.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

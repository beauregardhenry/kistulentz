# Kistulentz 0.23.0 — Words to Avoid, and a Style Guide That Actually Loads

Version 0.23.0 makes Kistulentz Style.md's "words to avoid" idea real, and fixes a bug that
kept the style guide from reliably reaching Kistulentz at all.

## Added

- Kistulentz Style.md has a new "Words to avoid" section: list a word or short phrase as its
  own bullet, and Kistulentz's local checks will flag it while you write — no AI, no network —
  the same way it already flags adverbs or passive voice. Previously, nothing in the style
  guide fed the local, offline checks at all; only optional AI-backed Rewrite/Deepen requests
  ever read it, despite the file's own text inviting "words to avoid" since it was first
  introduced.

## Fixed

- Fixed a real, independent bug found while verifying the above: "Edit Kistulentz Style…"
  could open to a blank editor instead of a project's real style guide, and any style-guide
  content became invisible to Kistulentz at runtime past the first render. If this ever
  affected you, your style guide file itself was never touched — only the app's in-memory view
  of it.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

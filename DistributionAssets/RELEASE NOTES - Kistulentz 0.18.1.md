# Kistulentz 0.18.1 — Rollback Reliability

Version 0.18.1 closes out a focused audit of every place Kistulentz undoes a partial change
after something fails partway through, so an interrupted operation is never reported as "cleanly
undone" when it wasn't.

## Fixed

- Dragging an outline item onto another item or a new parent now correctly rolls back the
  in-memory outline if the follow-up chapter-list sync fails, matching how reordering a sibling
  with Move Earlier or Move Later already behaved.
- A failed "Deepen with AI" manuscript report no longer gets silently written to disk on the next
  successful analysis after the request was reported as failed.
- Opening a project that needs a format upgrade, reorganizing project files, applying a systemic
  revision, and splitting a chapter by heading now each report distinctly when an automatic
  rollback from a failed attempt cannot fully complete, instead of a message implying the change
  was cleanly undone.
- HTML import now rejects an oversized embedded image by its encoded size before decoding it,
  rather than after — a small hardening step against pathological import files.

## Internal quality

- Removed a dead AI-review "Polish" code path left over from an earlier release, once Polish
  started always running locally.
- Extracted two shared helpers — one for writing imported assets to disk, one for the
  rollback-bookkeeping pattern behind the fixes above — that had previously been hand-copied
  across several call sites.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

# Kistulentz 0.24.0 — Toolbar Fix and Reliability Hardening

Version 0.24.0 is a small release: a toolbar visual-consistency fix, plus internal reliability
and performance hardening.

## Fixed

- **The De-stink toolbar button now matches its neighbors.** It previously rendered visibly
  bolder than Rewrite, Grade, and Reference beside it. SwiftUI's `.borderless` button style
  applies its own automatic label emphasis that a `Menu`'s `.borderlessButton` style does not;
  switching to `.plain` renders the label exactly as authored, matching the rest of the toolbar.

## Changed

- **Faster, simpler day-key formatting in Your Writing Growth.** The calendar heatmap's
  day-lookup logic now reuses a single cached date formatter instead of constructing a new one on
  every call -- most noticeable on the heatmap, which looks one up per visible day-square. No
  user-visible behavior changes.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

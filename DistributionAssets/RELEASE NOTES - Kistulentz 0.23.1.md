# Kistulentz 0.23.1 — Welcome, Every Time

Version 0.23.1 fixes a launch-reliability bug reported directly during friend testing.

## Fixed

- Quitting Kistulentz with every window already closed — the red traffic-light button, then
  Quit from the Dock or the app menu — reliably showed a plain macOS file browser instead of
  Kistulentz's own Welcome screen on the next launch, every time, not just on a genuine
  first-ever launch. Kistulentz now explicitly opens a document ahead of macOS's own "is there
  anything to resume" decision, so that fallback has nothing left to trigger on. Verified live,
  repeatedly, against a real installed build, for both a single document and a project.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

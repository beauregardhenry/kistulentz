# Kistulentz 0.22.2 — Projects Remember Where You Left Off

Version 0.22.2 fixes project reopening across a normal quit and relaunch — a real, previously
missing feature, reported directly after 0.22.1 shipped.

## Fixed

- Kistulentz now remembers which project you had open and reopens it automatically after
  quitting and relaunching, the same way document resume already worked. A project is a folder
  loaded on top of the window's single underlying document, invisible to AppKit's own window
  restoration — quitting while a project was open silently lost it on relaunch, back to whatever
  plain document had last been open, or the system Open-panel fallback again if there'd never
  been one. If your usual workflow is a project rather than a single loose Markdown file, this is
  the fix that actually addresses what you were seeing.

A project that's since been moved or deleted is forgotten silently on the next launch, with no
error dialog. A truly first-ever launch (nothing has ever existed to resume yet) can still show
the system panel once — this is normal, confirmed macOS behavior for document-based apps
generally. If you see it, click New Document once; it will not happen again after that.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

# Kistulentz 0.19.0 — Custom Fonts

Version 0.19.0 lets you bring your own fonts into Kistulentz, both for the app itself and for
individual projects.

## Added

- Settings now has a "Custom Fonts" section for adding your own TrueType or OpenType font
  files. Added fonts become available everywhere Kistulentz offers a font choice, including the
  editor and publication layouts, without installing them through Font Book separately.
- A font referenced by a project's publication layout — its body or heading font — is now
  bundled into that project's own hidden metadata folder. Opening the project on a different
  Mac gives that Mac access to the font file automatically, without its user separately adding
  the font through Settings first.

## Privacy and compatibility

Custom fonts added through Settings are copied into a local Kistulentz folder in Application
Support and registered for use across the app; removing one deletes its copy. A font bundled
into a project stays inside that project's hidden metadata folder and is only ever registered
for the current session, never installed system-wide — opening a project never makes a
permanent change to a Mac that isn't the one the font was originally added on. None of this
contacts an AI provider or leaves your Mac.

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

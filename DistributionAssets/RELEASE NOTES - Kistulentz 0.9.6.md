# Kistulentz 0.9.6 — Research Library Hotfix

Version 0.9.6 fixes a first-use Research Library screen that could not be dismissed before choosing a storage folder.

## Fixed

- The Research Library now always displays a **Close** button
- Its initial folder-selection screen includes a second visible **Close** action
- Pressing Escape dismisses the Research Library from both setup and normal library views
- **Choose Folder…** now opens the native macOS folder chooser
- The folder chooser can select an existing folder or create a new one
- Closing the screen does not choose a folder, alter the existing library location, or modify stored research records

## Packaging

The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. The ZIP and DMG contain the same app, GPL license, first-open instructions, source-code notice, and these release notes. Use `SHA256SUMS.txt` to verify either download.

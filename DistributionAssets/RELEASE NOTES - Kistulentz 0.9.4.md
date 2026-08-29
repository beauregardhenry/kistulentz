# Kistulentz 0.9.4 — Friend Preview

Version 0.9.4 is a reliability and release-readiness update. It adds a private System Check, makes bulk Reference Library work recoverable after interruption, improves VoiceOver support, and strengthens testing for both Mac processor architectures.

## What is new

- **Kistulentz System Check…** in the application menu and Settings
- Local checks for Markdown file registration, native writing analysis, optional Benepar and Ollama readiness, Reference Library persistence, and publishing tools
- An author-triggered diagnostic Markdown export that excludes writing, EPUB excerpts, titles, filenames, paths, API keys, account identifiers, and AI model names
- A built-in Benepar worker test using only a fixed Kistulentz sample sentence
- Per-book hidden recovery checkpoints for bulk EPUB imports and structural profiles
- Safe continuation after reopening: select the same EPUBs or folders and Kistulentz skips unchanged work
- Isolation between canceled and newly started bulk jobs so an older operation cannot overwrite current progress
- Added VoiceOver labels for the Markdown editor, Reference Library progress, project tools, suggestion refresh, and publication-matter locks
- A manual release-candidate workflow that tests natively on Apple silicon and Intel before building a universal package
- Automated checks for app identity, macOS Sequoia compatibility, Markdown file declarations, both executable architectures, bundled notices, signature integrity, ZIP, DMG, and checksums
- Current Node 24 GitHub Actions for checkout and artifact handling

## Privacy

System Check runs locally. It never submits a connectivity test to OpenAI or Anthropic, and its shareable report omits author content and private configuration values. Ollama is checked only through localhost. If the optional English language pack is installed, Kistulentz tests it with its own sample sentence rather than manuscript or reference text.

## Friend-preview installation

Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. Drag the app to Applications. If macOS blocks the first launch, try once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or run Terminal commands.

The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. The optional English language pack must match the Mac's processor architecture.

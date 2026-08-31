# Kistulentz 0.12.0 — 1.0 Hardening

Version 0.12.0 focuses on trust, recovery, accessibility, and large-manuscript responsiveness rather than adding another major writing system.

## First-launch guidance

- A Welcome window offers Create Project, Open Document, Import Documents, and Continue to Editor
- Optional fiction and nonfiction sample projects are created as editable copies in a folder chosen by the author
- The Welcome window explains which work remains local and can be reopened from the Help menu

## Draft recovery

- Active editing windows maintain local recovery journals in Application Support
- Journals are removed after a successfully saved normal close or application quit; unresolved local work remains available
- After an abnormal quit, Recovery Review compares the saved file and recovered draft side by side
- Authors may save the full recovered text as a separate Markdown copy, discard it, or replace the saved file after confirmation
- Replacement is refused if the saved file changed after its recovery preview loaded
- Long previews are capped for interface responsiveness, but save and replacement actions always use the complete recovered text

## Large-work responsiveness

- Live readability and selected-reference comparison run outside the interface thread
- Manuscript-wide project loading and analysis begin after the editing pause and run in background work
- Project chapter titles and word counts use a change-aware local index on reopen
- Cached chapter metadata is invalidated when a Markdown file's size or modification date changes
- Opt-in scale tests cover two million manuscript words across 2,000 documents, 1,000 imported files, and 5,000 Reference Library books

## Accessibility and release discipline

- New onboarding and recovery flows use semantic text, keyboard actions, and explicit VoiceOver descriptions
- Previously ambiguous icon controls in importing, research, revision goals, and project organization now have descriptive accessibility labels
- The repository includes dedicated accessibility and release checklists plus a manual native-architecture scale-test workflow

Kistulentz remains local-first and ad-hoc signed. It supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. Because Beau Henry does not yet have an Apple Developer account, this release does not add automatic updates.

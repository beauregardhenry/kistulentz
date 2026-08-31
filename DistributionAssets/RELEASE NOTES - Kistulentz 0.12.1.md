# Kistulentz 0.12.1 — Local Writing Improvements

Version 0.12.1 makes Kistulentz more useful before an author connects a cloud AI provider and simplifies two optional local-analysis setups.

## Local Polish without an AI account

- **Polish Document** now falls back to Local Polish when the selected AI provider is not ready
- Safe built-in phrase corrections appear in the same changed-passage review used by an AI polish
- Authors can accept individual passages or replace the complete document after confirmation
- Local Polish never sends manuscript or reference text off the Mac
- Markdown code fences, inline code, links, images, URLs, autolinks, and HTML remain protected
- Stale, overlapping, and rule-violating replacements are refused
- Advisory highlights remain visible for decisions that require an author's judgment
- Sentence-opening phrase replacements preserve capitalization

## Easier optional Benepar setup

- A prominent first-launch prompt explains the optional English structural-analysis pack
- Download and installation still require explicit confirmation
- The installed pack activates automatically and immediately refreshes document analysis
- Only one document window presents the first-launch prompt
- Native Kistulentz analysis remains available when the author chooses **Not Now**

## Guided Ollama setup

- Settings links to Ollama's official macOS installer and watches for the local service to start
- Installed models appear in a menu instead of requiring a typed model name
- Kistulentz recommends `qwen3.5:4b` for local writing tasks
- The recommended model download requires confirmation and shows status, transferred data, progress, and Cancel
- A successfully downloaded model is selected automatically; Kistulentz never silently installs Ollama or a model
- Server errors, incomplete downloads, malformed progress, invalid model names, and cancellation are reported safely

## Verification

- 151 automated tests pass with no failures
- The opt-in real Benepar-model test and three extreme-scale benchmarks remain separate from the normal suite
- The release bundle was rebuilt and verified for Apple silicon and Intel Macs
- Kistulentz remains local-first, ad-hoc signed, GPL-3.0-or-later software for macOS Sequoia 15 or later

# Kistulentz release checklist

Use this checklist for every staged release. Do not publish when a data-loss, accidental-overwrite, unusable-screen, uncancellable-operation, or reproducible hang remains open.

## Source and version

- Working tree contains only intended release changes
- Version, build number, release notes, First Open guide, source-code notice, README, DOCX metadata, and research user agent agree
- GPL-3.0-or-later license and corresponding source tag are present
- `git diff --check` passes

## Automated verification

- Full test suite passes locally
- Test release candidate workflow passes natively on Apple silicon and Intel
- Test 1.0 scale targets workflow passes at the approved limits
- Universal app contains arm64 and x86_64 executables
- Ad-hoc signature and designated requirement verify
- ZIP, DMG, contents, and SHA-256 checksums pass `verify-release.sh`

## Manual clean-install and upgrade testing

- First launch from a clean preferences profile presents Welcome and every action works
- Existing preferences, API model choices, dismissed suggestions, libraries, and v0.11 projects reopen correctly
- A clean friend installation follows the documented Privacy & Security “Open Anyway” path without Terminal commands
- Normal close and quit leave no recovery prompt; a deliberately interrupted test session does
- Recovery save-copy, changed-file refusal, confirmed replacement, discard, and reopen behavior all work

## Author workflows

- Open, edit, autosave, Save As, close, reopen, Undo, and Redo Markdown and plain-text documents
- Import real DOCX, RTF, RTFD, HTML, ODT, and TXT documents with images, tables, notes, comments, and tracked changes where supported
- Project Import Assistant handles mixed files, recursive folders, cancellation, retry, partial failure, combined Markdown, new project, and current project
- Research and Reference Library folder choosers open, cancel, create a folder, and persist the selected location
- Local Polish and Rewrite fallback behavior, OpenAI, Anthropic, and installed Ollama paths show the correct request preview and never expose keys
- Suggestion acceptance, decline, Apply All, polished-passage staging, and one-step Undo behave as described
- Project Organization, systemic revisions, snapshots, recovery, publication preflight, and every export format complete without overwriting unrelated files

## Accessibility, diagnostics, and publication

- Complete [ACCESSIBILITY.md](ACCESSIBILITY.md)
- Export and inspect the privacy-safe diagnostic report
- Validate EPUB with EPUBCheck when installed and perform the documented external/manual checks
- Verify release notes describe limitations, ad-hoc signing, Sequoia requirement, and lack of automatic updates
- Create the annotated version tag from the verified commit, upload DMG, ZIP, and checksums, then verify the public release assets

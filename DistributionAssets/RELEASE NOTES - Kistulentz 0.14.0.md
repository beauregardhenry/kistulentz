# Kistulentz 0.14.0 — Staged Project Polish

Version 0.14.0 brings Kistulentz’s guarded passage review to an entire Markdown project and makes optional AI setup easier to verify.

## Polish a whole project locally

- **Polish Project** scans every current project document using local readability rules, Apple spelling and grammar, and learned project-style choices
- Proposed passages are grouped into **Spelling & Grammar**, **Clarity & Readability**, and **Style & Voice** stages
- Authors can enable or defer whole stages, then include, exclude, and edit each individual proposal
- Progress names the current document, Cancel stops after the current document, and completed results remain reviewable
- A failed document is reported clearly while the remaining project continues

## Guarded multi-file application

- Every included passage is rechecked against the current Markdown before any file is written
- Stale, duplicated, and overlapping passages are marked as conflicts and block the entire application
- Every affected file receives a project snapshot
- All accepted project changes register as one normal macOS Undo action
- If validation or writing fails, Kistulentz leaves the manuscript unchanged or restores the pre-application contents

## Provider connection tests without manuscript text

- Settings now provides **Test Connection** for OpenAI, Anthropic, and local Ollama
- OpenAI and Anthropic checks use the providers’ model-metadata endpoints to verify the saved key and selected model
- Ollama verifies that the local service is running and the selected model is installed
- These requests contain no manuscript, project, reference, style-guide, excerpt, or prompt text

## Verification

- New regression tests cover staged selection, cancellation, continue-past-failure behavior, stale-file protection, cloud request methods and headers, rejected credentials, and missing Ollama models
- The complete native suite, macOS UI regression suite, Intel build, Apple-silicon build, and universal-package integrity checks remain release gates
- Kistulentz remains ad-hoc signed, GPL-3.0-or-later software for macOS Sequoia 15 or later

# Kistulentz 0.14.1 — Large Paste Reliability

Version 0.14.1 fixes an editor stall that could occur after pasting a long document.

## Fixed

- Apple spelling and grammar analysis now runs asynchronously instead of blocking the editor interface
- The Markdown editor no longer performs a duplicate live spelling and grammar pass while Kistulentz prepares its own review cards
- Full-document highlights are repainted only when the document or its findings change
- Grammar suggestions no longer trigger repeated candidate-analysis passes for every possible correction
- Project Polish remains responsive and cancellable while native writing analysis is running
- A large-paste regression test now verifies that the macOS interface remains responsive during native analysis

## Privacy and compatibility

The corrected spelling, grammar, and highlighting work remains local to the Mac. No pasted text is sent to OpenAI, Anthropic, Ollama, or another service unless the author separately chooses and confirms an AI-backed command.

This universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. The ZIP and DMG contain the same application, first-open instructions, GPL license, corresponding-source notice, and these release notes.

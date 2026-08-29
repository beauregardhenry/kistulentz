# Kistulentz 0.9.5 — Friend Preview

Version 0.9.5 makes AI-assisted revision easier to inspect, stage, reverse, and trust. It also improves at-a-glance readability information throughout a project and simplifies model selection for OpenAI and Anthropic.

## Polished-draft review

- **Review polished draft…** opens a passage-by-passage comparison instead of replacing the document immediately
- Every changed passage shows its current and polished text with separate **Accept** and **Decline** decisions
- **Apply Selected** stages only the accepted passages as one normal macOS Undo action
- **Replace All** remains available after a separate confirmation when the complete polished draft passes local safeguards
- Stale comparisons are rejected if the Markdown document changes while the review is open

## Safer suggestions and rewrites

- AI suggestions that introduce a new local readability flag are withheld from the normal suggestion cards
- Conflicting polished passages remain visible for inspection but cannot be accepted
- Safety checks consider the surrounding sentence and the complete result, not only the replacement fragment
- Advisory cards without a direct replacement now offer **Rewrite…** and request three alternatives targeted to that card
- Grammar and mechanics have a dedicated rewrite operation

## Undo and review continuity

- Undo reverses an accepted suggestion, selected polished passages, or the complete polished draft without discarding the AI review
- Redo restores the applied change while preserving the same review
- Background analysis and highlight formatting no longer create misleading Undo entries
- An unrelated manual edit still clears a stale AI review

## Project and provider usability

- Project document lists show the reading grade for every Markdown file
- The readability meter more clearly separates measured grade, target grade, and distance from the target
- OpenAI and Anthropic settings provide model menus instead of requiring a blank model field
- Previously selected compatible model identifiers remain supported

## Packaging

The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. The ZIP and DMG contain the same app, GPL license, first-open instructions, source-code notice, and these release notes. Use `SHA256SUMS.txt` to verify either download.

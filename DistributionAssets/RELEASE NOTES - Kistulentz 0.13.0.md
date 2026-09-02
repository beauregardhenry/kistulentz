# Kistulentz 0.13.0 — Native Writing Corrections

Version 0.13.0 makes local editing substantially more useful without requiring an AI provider.

## Apple spelling and grammar cards

- Kistulentz turns Apple’s built-in English spelling and grammar results into normal sidebar cards
- Spelling cards include the best local dictionary guess when macOS supplies one
- Grammar cards include a replacement only when it reduces Apple’s grammar findings for that sentence
- Fenced code, inline code, Markdown links, URLs, and HTML remain protected from these corrections
- All processing stays on the Mac and works without OpenAI, Anthropic, Ollama, or Benepar

## Style-aware Local Polish

- Local Polish includes safe Apple spelling and grammar replacements alongside Kistulentz’s readability substitutions
- Accepted project style replacements can be reused across the current passage
- A replacement the author has declined is never applied automatically, even if an older accepted record also exists
- Every concrete change still passes Kistulentz’s local rule validator and opens in the existing passage-by-passage polished-draft review

## Verification

- New regression tests cover actionable Apple corrections, protected Markdown ranges, accepted style choices, and declined-style precedence
- The complete native suite, macOS UI regression suite, Intel build, Apple-silicon build, and universal-package integrity checks remain release gates
- Kistulentz remains ad-hoc signed, GPL-3.0-or-later software for macOS Sequoia 15 or later

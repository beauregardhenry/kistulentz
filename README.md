# Kistulentz

Kistulentz is a native, document-based Markdown editor for macOS Sequoia. It combines live Hemingway-style readability guidance with optional OpenAI or Anthropic editing.

## Included

- Native `.md` open, edit, save, autosave, and Undo support
- Live reading-grade estimate, word count, sentence count, and reading time
- Color highlights for long sentences, very long sentences, adverbs, passive voice, and complex phrases
- macOS spelling and grammar checking while you type
- A target reading-grade setting
- EPUB reference books for local style, vocabulary, tone, character, continuity, voice, and tempo analysis
- Live local comparison between the Markdown draft and the selected EPUB
- OpenAI Responses API and Anthropic Messages API support
- AI grammar, spelling, clarity, continuity, and rewriting suggestions informed by selected EPUB excerpts
- A complete polished Markdown revision with a confirmation step before replacement
- API keys stored in the macOS Keychain

## Build the Mac app

Xcode 26 or newer must be installed in `/Applications/Xcode.app`.

```sh
./scripts/build-app.sh
```

The universal application is created at `dist/Kistulentz.app`. Copy it to `/Applications` if desired. The local build is ad-hoc signed; warning-free public distribution requires an Apple Developer ID certificate and notarization.

## Development

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --disable-sandbox DraftSmith
```

Run tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
```

## API setup

Open Kistulentz Settings and paste an API key for OpenAI, Anthropic, or both. Model names remain editable so the app can use models enabled for each account without requiring a new app release.

Document text and EPUB reference books are analyzed locally until the user chooses **Polish**. At that point, the current Markdown, the local reference profile, and selected relevant excerpts from the EPUB are sent only to the selected provider. The complete EPUB is not uploaded.

DRM-protected and image-only EPUB files do not expose readable book text and cannot be analyzed.

# Kistulentz

Kistulentz is a native, document-based Markdown editor for macOS Sequoia. It combines live Hemingway-style readability guidance with optional OpenAI, Anthropic, or local Ollama editing.

## Included

- Native `.md` open, edit, save, autosave, and Undo support
- Normal-folder projects for fiction and nonfiction manuscripts
- Ordered Markdown chapters, manuscript-wide search, and combined project word counts
- A project-local, editable `Kistulentz Style.md` that learns from accepted and declined suggestions
- Persistent project snapshots with named versions, visual line comparisons, and protected restoration
- Distraction-free Write mode and individually configurable highlight categories
- Live reading-grade estimate, word count, sentence count, and reading time
- Color highlights for long sentences, very long sentences, adverbs, passive voice, and complex phrases
- macOS spelling and grammar checking while you type
- A target reading-grade setting
- EPUB reference books for local style, vocabulary, tone, character, continuity, voice, and tempo analysis
- Live local comparison between the Markdown draft and the selected EPUB
- A user-chosen Markdown Reference Library designed for thousands of EPUB files
- Individual EPUB and recursive folder imports with unchanged-file skipping
- Combined profiles by book, author, and genre, with overlapping selections deduplicated
- In-app corrections for titles, authors, and genres
- Short attributed excerpts retained in per-book and combined Markdown profiles
- Optional **Deepen w/ AI** analysis that never runs during local imports
- OpenAI Responses API, Anthropic Messages API, and local Ollama support
- Automatic discovery of Ollama models already installed on the Mac; Kistulentz never installs Ollama or downloads models
- AI grammar, spelling, clarity, continuity, and rewriting suggestions informed by selected EPUB excerpts
- Selection rewrites for target-grade simplification, shortening, grounded expansion, stronger verbs, a user-described tone, and matching selected references
- Three distinct rewrite alternatives with explanations and grade estimates
- A mandatory request preview showing provider, model, destination, exact instructions, draft or selection, project style guide, and reference excerpts before an AI action runs
- Optional style-guide and reference material can be removed or redacted in the request preview
- Accept or decline individual local and AI suggestions directly in the sidebar
- Declined suggestions stay hidden after reopening a document until that exact passage or its nearby context changes
- A confirmed **Apply All** action applies only concrete, non-overlapping replacements as one macOS Undo step
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

For local AI, install and start Ollama separately, then choose **Detect Models** in Kistulentz Settings. Kistulentz lists models already present at Ollama's local address and does not install Ollama or download a model. Apple silicon uses Ollama's supported acceleration; Intel Macs use CPU inference and may be substantially slower for large models.

Document text and EPUB reference books are analyzed locally until the user chooses **Polish**, **Rewrite**, or **Deepen w/ AI**. Local imports never contact an AI provider. Before an AI request runs, Kistulentz shows its destination and the exact writing material assembled for the request. OpenAI and Anthropic requests send only the confirmed material to the selected cloud provider. Ollama requests stay on the Mac at `localhost:11434`. Complete EPUB files and the complete Reference Library are not uploaded.

The chosen Reference Library folder contains `Kistulentz Library.md`, per-book profiles, combined author and genre profiles, AI insight files, and a hidden machine-readable index used for fast loading. Make metadata corrections inside Kistulentz so generated profiles remain synchronized.

Declined-suggestion records are stored in Kistulentz's local app preferences, not inside the Markdown document. They are removed automatically when the matching passage or nearby context changes.

DRM-protected and image-only EPUB files do not expose readable book text and cannot be analyzed.

## Projects

Use the folder menu in the editor toolbar to create a project inside a chosen parent folder or open an existing folder. Existing Markdown files remain unchanged when a folder is set up as a project. Kistulentz adds:

- `.kistulentz/project.json` for the project type and chapter order
- `.kistulentz/history/` for persistent revision snapshots
- `.kistulentz/style-decisions.json` for local accepted/declined preference records
- `Kistulentz Style.md` at the project root for editable style instructions and learned preferences

The manuscript itself remains a normal collection of `.md` files. Kistulentz saves a baseline snapshot before the first edit to a chapter in a session, before programmatic replacements, and before restoring an older snapshot. Named snapshots can be created at any time.

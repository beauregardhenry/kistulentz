# Kistulentz

Kistulentz is a native, document-based Markdown editor for macOS Sequoia. It combines live Hemingway-style readability guidance with optional OpenAI, Anthropic, or local Ollama editing.

## Included

- Native `.md`, `.markdown`, `.mdown`, `.txt`, and `.text` open, edit, save, autosave, and Undo support
- A first-launch Welcome window with create, open, multi-document import, and optional editable fiction and nonfiction sample projects
- Local abnormal-quit draft journals with side-by-side Recovery Review, save-copy, confirmed replacement, stale-file protection, and discard actions
- Safe single-Markdown import for DOCX, RTF/RTFD, HTML, and OpenDocument Text files, with a conversion preview that never rewrites the source
- A Project Import Assistant for multiple explicit files, recursively selected folders, or both, with editable order and Part, Chapter, Scene, or Section assignments before conversion
- Per-file batch progress, cancellation, conversion reports, tracked-change decisions, and failures that do not stop the remaining documents
- Batch output as one hierarchically headed Markdown file, a new fiction or nonfiction project, or additional documents in the open project
- Word tracked changes presented as accept-or-reject review cards before an imported Markdown copy can be saved
- Imported headings, lists, emphasis, links, notes, comments, tables, and embedded images preserved where the source format exposes them; images go into a sibling assets folder
- Local-only HTML import that refuses to download remote images or execute scripts
- Normal-folder projects for fiction and nonfiction manuscripts
- Ordered Markdown chapters, manuscript-wide search, and combined project word counts
- Change-aware cached chapter metadata for faster reopening of large projects
- A visual Project Organization workspace with Corkboard and Outliner views for Parts, Chapters, and fiction Scenes or nonfiction Sections
- Drag-and-drop outline ordering that does not move files in Finder unless the user separately previews and approves **Organize Files to Match Outline**
- Editable outline cards with synopsis, status, purpose, labels, notes, export inclusion, target length, and fiction- or nonfiction-specific planning fields
- Local synopsis suggestions, kept separate from the author’s synopsis, with an optional previewed **Deepen w/ AI** command
- Previewed level-two-heading splitting into Scene or Section Markdown files, with snapshots and normal macOS Undo
- Previewed physical file organization that retains filenames by default, allows destination edits, blocks conflicts, snapshots affected files, and supports Undo
- A project-local, editable `Kistulentz Style.md` that learns from accepted and declined suggestions and safely informs later Local Polish reviews
- An automatically updated, local `Kistulentz Manuscript Report.md` covering structure, pacing, continuity, people and characters, evidence, readability, repetition, voice, and priorities
- An editable `Kistulentz Bible.md` that tracks names, places, organizations, terminology, timeline markers, and chapter facts while preserving author corrections and manual notes
- Bible change summaries, normal macOS Undo, and persistent pre-update snapshots in Revision History
- Six built-in beta readers for general, fiction, and nonfiction concerns, plus editable project-local custom readers
- Local beta feedback for a selection, chapter, or whole manuscript, with optional previewed **Deepen w/ AI** feedback that remains in the app for the current session
- Persistent project snapshots with named versions, visual line comparisons, and protected restoration
- Automatic project-format migration with a pre-migration metadata backup, rolling last-known-good snapshots, and guided recovery that never replaces manuscript Markdown
- Distraction-free Write mode and individually configurable highlight categories
- Live reading-grade estimate, word count, sentence count, and reading time
- Background readability, reference comparison, and manuscript-wide analysis that keeps large-document work away from the interface thread
- Color highlights for long sentences, very long sentences, adverbs, passive voice, and complex phrases
- A prominent first-run prompt for the optional English Benepar pack, which turns on automatically after its confirmed local installation
- Orange advisory sentence-structure highlights that never trigger automatic prose replacement
- Actionable spelling and grammar cards from Apple’s built-in English writing services, with code, links, URLs, and HTML excluded
- A target reading-grade setting
- EPUB reference books for local style, vocabulary, tone, character, continuity, voice, and tempo analysis
- Live local comparison between the Markdown draft and the selected EPUB
- A user-chosen Markdown Reference Library designed for thousands of EPUB files
- Per-book recovery checkpoints that preserve completed bulk EPUB and structural-analysis work across interruption or relaunch
- Individual EPUB and recursive folder imports with unchanged-file skipping
- Combined profiles by book, author, and genre, with overlapping selections deduplicated
- In-app corrections for titles, authors, and genres
- Short attributed excerpts retained in per-book and combined Markdown profiles
- Optional **Deepen w/ AI** analysis that never runs during local imports
- Resumable, user-triggered Benepar analysis for selected books, authors, or genres, with completed profiles cached into the editable Markdown knowledge base, skipped on later missing-only runs, and combined across references
- OpenAI Responses API, Anthropic Messages API, and local Ollama support
- Guided Ollama setup with automatic local-service detection, an installed-model menu, and a confirmed, cancellable recommended-model download with progress
- A safe Local Polish fallback that combines concrete readability, Apple spelling and grammar, and accepted project-style replacements; protects Markdown code and links; honors declines; and never invents prose
- A cancellable whole-project Polish scan with separate Spelling & Grammar, Clarity & Readability, and Style & Voice stages; editable passage previews; per-document failure reporting; exact-text validation; per-file snapshots; and one guarded Undo action
- No-manuscript **Test Connection** controls for OpenAI, Anthropic, and Ollama that verify the saved key and selected model without sending project, reference, prompt, or manuscript text
- AI grammar, spelling, clarity, continuity, and rewriting suggestions informed by selected EPUB excerpts
- Selection rewrites for target-grade simplification, shortening, grounded expansion, stronger verbs, a user-described tone, and matching selected references
- Three distinct rewrite alternatives with explanations and grade estimates
- A mandatory request preview showing provider, model, destination, exact instructions, draft or selection, project style guide, and reference excerpts before an AI action runs
- Optional style-guide and reference material can be removed or redacted in the request preview
- Accept or decline individual local and AI suggestions directly in the sidebar
- Declined suggestions stay hidden after reopening a document until that exact passage or its nearby context changes
- A confirmed **Apply All** action applies only concrete, non-overlapping replacements as one macOS Undo step
- A global, user-chosen Research Library for books, articles, web sources, reports, and other evidence shared across projects
- Manual source entry plus explicit DOI lookup through Crossref and ISBN lookup through Open Library
- BibTeX, RIS, and CSL-JSON import and export with duplicate detection and editable citation keys
- Managed-copy or link-only PDF, EPUB, web archive, image, and text attachments with local indexing and Apple Vision OCR
- Project-specific source lists, quotations, claim links, an editable `Kistulentz Research Notes.md`, and Pandoc-style Markdown citation insertion
- Chicago Notes & Bibliography, Chicago Author-Date, APA, MLA, and numbered bibliography previews
- A persistent Systemic Revision Center with seven passes, revision goals, and findings labeled by evidence strength
- Explicit, previewed **Deepen w/ AI** revision analysis that adds suggestions but never edits manuscript files
- Coordinated multi-file change previews with per-change inclusion, editable replacements, passage and overlap checks, per-file snapshots, rollback protection, and one guarded Undo/Redo action
- A local Publish & Export workspace with an exact in-app content plan that follows Parts, Chapters, Scenes or Sections and respects each outline item's export inclusion
- Four built-in starting profiles—Fiction Book, Nonfiction Book, Agent Submission, and Accessible EPUB—plus editable named custom profiles
- Editable publication metadata, digital cover images, separate supplied print-cover PDFs, and generated front/back matter that can be edited or locked against regeneration
- EPUB 3 with navigation, accessibility metadata, cover and inline images, citations, notes, and bibliography output
- Print-interior PDF, reader PDF, and editable DOCX output with configurable trim/page size, type, spacing, margins, running matter, page numbers, and chapter openings
- Parenthetical, footnote, and endnote citation modes using the project's bibliography system
- A blocking local preflight for missing manuscript files, images, citation records, footnotes, and incompatible image formats, with explicit approval required for nonblocking warnings
- Independent multi-select publication destinations for Generic EPUB 3.3, Apple Books, Kindle/KDP eBook, KDP Print, IngramSpark eBook, and IngramSpark Print
- Explicit destination presets that apply the required format and locally checkable minimum settings without replacing author-controlled trim and typography
- Target-specific local checks for format, cover, navigation, accessibility structure, image dimensions, estimated print resolution, margins, bleed geometry, and final KDP gutter brackets
- Complete submission folders containing the publication, a separate supplied cover when available, checksums, a package manifest, and Markdown and PDF Submission Readiness Reports
- Explicit **Passed Locally**, **Action Required**, **External Validation Required**, and **Manual Review Required** statuses that never promise retailer acceptance
- No-bleed and 0.125-inch outside-bleed print PDFs with MediaBox, TrimBox, and BleedBox data, no gutter bleed, and no printer marks
- Automatic EPUBCheck execution when its command-line tool is already installed, with local detection of Kindle Previewer and Apple Transporter
- Shareable publication diagnostics that exclude manuscript prose and excerpts
- An in-app, local-only System Check with an explicitly exported privacy-safe diagnostic report
- Finder-style Research Library and diagnostic panels that remain cancellable and keep their parent screen usable
- A checked-in Xcode UI-test host covering first launch, Research Library folder selection and closure, and diagnostic export cancellation
- Project-local publication profiles, setup, assets, checksums, and export history; finished publications go only to a folder chosen by the author
- A complete polished Markdown revision with a confirmation step before replacement
- API keys stored in the macOS Keychain

## Build the Mac app

```sh
./scripts/build-app.sh
```

The application is created at `dist/Kistulentz.app`. Copy it to `/Applications` if desired. The local build is ad-hoc signed; warning-free public distribution requires an Apple Developer ID certificate and notarization.

Xcode 26 or newer produces the universal application. The script finds Xcode automatically, so `DEVELOPER_DIR` only needs to be set when Xcode is installed somewhere other than `/Applications/Xcode.app`. With only the Command Line Tools installed, the script reports that it is building for this Mac's architecture alone and produces a `dist/Kistulentz.app` that runs normally.

## Development

```sh
swift run --disable-sandbox Kistulentz
```

Run tests with:

```sh
swift test --disable-sandbox
```

The canonical application continues to build with Swift Package Manager. `Kistulentz.xcodeproj` is a minimal UI-test host generated from `project.yml`; maintainers can regenerate it with `./scripts/regenerate-xcode-project.sh` after installing XcodeGen.

The test suite uses XCTest, which ships with Xcode. On a Mac with only the Command Line Tools, `swift build` and `swift run` work but `swift test` reports `no such module 'XCTest'`.
Before sharing a release candidate, build its ZIP and DMG and run the local integrity checks:

```sh
./scripts/package-release.sh
./scripts/verify-release.sh dist/Kistulentz.app --release-assets
```

Maintainers can run the **Test or publish release** GitHub Actions workflow manually. It runs macOS UI regressions, tests natively on Apple silicon and Intel, then builds and verifies the universal package without publishing it. Pushing an annotated upstream version tag that matches `CFBundleShortVersionString`, such as `v0.14.1`, runs the same gates and publishes the verified ZIP, DMG, and checksums as a GitHub Release.

The manual **Test 1.0 scale targets** workflow exercises the approved large-work targets on native Apple silicon and Intel runners. See [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) and [ACCESSIBILITY.md](ACCESSIBILITY.md) before publishing a release candidate.

### Optional English structural-analysis pack

The base app always keeps its native local analysis. On first launch, Kistulentz prominently offers a separately confirmed download of the large English pack; the same control remains available in **Kistulentz Settings**. Once installed, Benepar turns on automatically and augments live Markdown guidance, manuscript reports, and selected EPUB profiles. Analysis stays on the Mac; the pack is not an AI provider and it does not rewrite prose automatically.

Language packs are architecture-specific for Apple silicon and Intel. Maintainers can build the native pack with the pinned, checksum-verified standalone Python runtime:

```sh
./scripts/fetch-benepar-python-runtime.sh "$(uname -m)"
./scripts/build-benepar-language-pack.sh ".build/benepar-runtimes/$(uname -m)" "$(uname -m)" 1.0.0
```

The manual **Build English language packs** GitHub Actions workflow builds and validates both architectures. It only publishes the dedicated pack release when its `publish_release` input is explicitly enabled.

## API setup

Open Kistulentz Settings and paste an API key for OpenAI, Anthropic, or both. Model names remain editable so the app can use models enabled for each account without requiring a new app release.

For local AI, Kistulentz Settings links to Ollama’s official macOS installer and watches for the local service to start. It lists models already present at Ollama's local address. With explicit confirmation, Kistulentz can ask that local service to download and select the recommended `qwen3.5:4b` writing model, showing progress and a Cancel command. Kistulentz does not silently install Ollama or a model. Apple silicon uses Ollama's supported acceleration; Intel Macs use CPU inference and may be substantially slower for large models.

Document text, manuscript reports, project Bibles, beta-reader signals, research attachments, and EPUB reference books are analyzed locally until the user chooses an AI-backed **Polish**, **Rewrite**, metadata lookup, or **Deepen w/ AI**. If no selected AI provider is ready, **Polish** instead creates a review of safe rule-based changes entirely on the Mac. Local imports, OCR, indexing, Benepar parsing, revision scans, Local Polish, and automatic manuscript updates never contact an AI provider. Installing the optional English pack downloads only its program files and model from Kistulentz’s GitHub release. A confirmed Ollama model download sends the chosen model name to the Ollama service on this Mac; Ollama manages the model download. DOI and ISBN lookup sends only the identifier to Crossref or Open Library. Before an AI request runs, Kistulentz shows its destination and the exact writing material assembled for the request. OpenAI and Anthropic requests send only the confirmed material to the selected cloud provider. Ollama writing requests stay on the Mac at `localhost:11434`. Complete EPUB files and the complete Reference Library are not uploaded automatically.

The chosen Reference Library folder contains `Kistulentz Library.md`, per-book profiles, combined author and genre profiles, AI insight files, and a hidden machine-readable index used for fast loading. Make metadata corrections inside Kistulentz so generated profiles remain synchronized.

Declined-suggestion records are stored in Kistulentz's local app preferences, not inside the Markdown document. They are removed automatically when the matching passage or nearby context changes.

DRM-protected and image-only EPUB files do not expose readable book text and cannot be analyzed.

## Projects

Use the folder menu in the editor toolbar to create a project inside a chosen parent folder or open an existing folder. Existing Markdown files remain unchanged when a folder is set up as a project. Kistulentz adds:

Use **Project Import Assistant…** in the same folder menu to bring in several Markdown, TXT, DOCX, RTF, RTFD, HTML, or ODT documents at once. Add files, folders, or both; review their discovered order; edit each title and structural assignment; then convert. A failed source remains visible with its error while other sources continue. After previewing the converted Markdown and deciding any tracked changes, create one combined Markdown file, create and open a new project, or add the successful documents to the current project. Kistulentz never changes the source files and refuses to replace an existing combined Markdown export.

- `.kistulentz/project.json` for the project type and chapter order
- `.kistulentz/outline.json` for the visual Part, Chapter, Scene or Section hierarchy and planning fields
- `.kistulentz/history/` for persistent revision snapshots
- `.kistulentz/style-decisions.json` for local accepted/declined preference records
- `.kistulentz/manuscript-cache.json` for the last generated Bible baseline, cached sentence-structure profile, and requested AI report notes
- `.kistulentz/beta-readers.json` for custom beta-reader definitions
- `.kistulentz/bibliography.json` for project source references, quotations, claim links, and citation style
- `.kistulentz/revisions.json` for persistent systemic findings, classifications, statuses, and goals
- `.kistulentz/publication.json` for publication metadata, named profiles, editable generated matter, checksums, and export history
- `.kistulentz/publication-assets/` for project-local copies of selected cover assets
- `.kistulentz-backups/` for hidden pre-migration, last-known-good, and pre-recovery metadata snapshots
- `Kistulentz Style.md` at the project root for editable style instructions and learned preferences
- `Kistulentz Manuscript Report.md` at the project root for the combined local and requested AI report
- `Kistulentz Bible.md` at the project root for the editable project knowledge base
- `Kistulentz Research Notes.md` at the project root for editable project-specific research notes

The manuscript itself remains a normal collection of `.md` files; Kistulentz excludes its Style, Report, Bible, and Research Notes support files from the chapter list and manuscript word count. The report and Bible update locally after a short writing pause. Manual Bible corrections, deletions, and notes survive later updates. Kistulentz saves a baseline snapshot before the first edit to a chapter in a session, before programmatic replacements, before the first automatic Bible change in a session, before requested AI Bible notes, and before restoring an older snapshot. Named snapshots can be created at any time.

When an older project opens, Kistulentz first copies its structured metadata into `.kistulentz-backups/`, then migrates that metadata to the current format. A successful open maintains up to three rolling last-known-good snapshots. If structured metadata later becomes unreadable, the recovery window can restore one of those snapshots; immediately before restoring, Kistulentz preserves the current failed metadata as another snapshot. These operations do not restore, replace, or edit manuscript Markdown files.

Open **Research Library** from the Reference menu in the toolbar. The library folder is separate from any one writing project and contains a visible generated `Kistulentz Research Library.md`, managed attachment copies when selected, extracted local text indexes, and a hidden structured source index. Open **Project Research** to attach shared sources to a project, set its bibliography style, save quotations and claim links, edit its Research Notes, and insert citations without replacing selected manuscript prose.

Open **Systemic Revision Center** from the project sidebar or project menu. **Scan Locally** creates evidence-labeled findings without sending data anywhere. **Deepen w/ AI** always shows the normal request preview. AI results remain suggestions in the ledger. To edit files, select concrete findings and review the coordinated change set; Kistulentz rechecks exact passages immediately before applying and refuses ambiguous or overlapping changes.

Open **Manuscript Insights** from the project sidebar or project menu. The Report and Bible are persistent Markdown files inside the project. Built-in and AI beta feedback is displayed in Kistulentz for the current session and does not create feedback files. Custom beta-reader definitions remain in the hidden project metadata so they are available when the project reopens.

Open **Project Organization** from the project sidebar or project menu to use the Corkboard and Outliner. Kistulentz imports existing first-level folders as Parts, nested folders as Chapters, and Markdown files as the available Chapter, Scene, or Section items. Reordering cards changes only the outline and project reading order. It never moves a Markdown file in Finder by itself.

Open **Publish & Export** from the project sidebar or project menu. Choose a named layout profile, output format, and one or several independent publication destinations, then review the exact local content preview. Inclusion and ordering changes in this preview remain temporary unless you explicitly save inclusions back to Project Organization. Publication Setup holds book metadata and cover assets. Generated Matter provides editable, lockable title, copyright, contents, notes, bibliography, and other pages; regeneration skips anything locked or manually edited. Print profiles can use no bleed or 0.125-inch top, bottom, and outside bleed.

Run Preflight before export, resolve every error, and explicitly approve any remaining warnings. Kistulentz creates a complete submission folder in the location you choose. It contains the exported EPUB, PDF, or DOCX, a separate supplied cover when available, a package manifest, SHA-256 checksums, and Submission Readiness Reports in Markdown and PDF. The report separates locally verified conditions from required external validation and manual review; it is not retailer certification. Kistulentz runs EPUBCheck when its command-line tool is already installed and detects Kindle Previewer and Apple Transporter, but it does not bundle or install those tools. The report and manifest intentionally exclude manuscript prose and excerpts. No publication export uses an AI provider.

Choose **Organize Files to Match Outline…** only when you want the folder layout to follow the outline. Kistulentz shows every source and destination, keeps the existing filename unless you edit it, and refuses to proceed while a destination is unsafe or occupied. It snapshots affected documents before moving them, and the entire operation can be undone from the normal Edit menu. A Chapter’s level-two Markdown headings can likewise be previewed and selectively split into separate Scene or Section files; unchecked headings stay in the Chapter.

Each outline item has an editable author synopsis and a separate suggested synopsis. **Suggest Locally** analyzes only project text on the Mac. **Deepen w/ AI** uses the standard request preview before sending the confirmed item and optional context to OpenAI or Anthropic, or to local Ollama. Neither command overwrites the author synopsis automatically.

## License

Copyright © 2026 Beau Henry.

Kistulentz is free software licensed under the GNU General Public License, version 3 or any later version. See [LICENSE](LICENSE).

See [CONTRIBUTING.md](CONTRIBUTING.md), [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [SUPPORT.md](SUPPORT.md) for project policies and help.

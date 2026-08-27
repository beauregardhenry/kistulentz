# Kistulentz 0.9.0 — Friend Preview

Version 0.9.0 adds a complete, local Publish & Export workspace for turning a Kistulentz Markdown project into an EPUB 3 book, print-interior PDF, reader PDF, or editable DOCX manuscript.

## What is new

- Exact in-app export planning based on the project’s Parts, Chapters, Scenes, or Sections
- Temporary inclusion and ordering changes that do not alter the outline unless the author explicitly saves inclusions
- Four built-in starting profiles: Fiction Book, Nonfiction Book, Agent Submission, and Accessible EPUB
- Named custom profiles for fonts, sizes, spacing, margins, page or trim size, running matter, page numbers, citations, and chapter openings
- Editable publication metadata, digital cover images, and separately supplied print-cover PDFs
- Generated title, copyright, contents, notes, bibliography, and other front/back matter that authors can edit or lock
- Parenthetical, footnote, and endnote citation modes using project bibliography records
- Cover and inline image support in digital and document exports
- Local preflight for missing manuscript files, images, footnotes, citations, incompatible image types, metadata, fonts, and accessible heading structure
- Blocking errors must be resolved; nonblocking warnings require explicit approval
- SHA-256 checksums and export history stored inside the project’s hidden `.kistulentz` folder

## Privacy

Publication planning, preflight, rendering, and export are completely local. They do not require an API key and never send writing to OpenAI, Anthropic, or Ollama.

## Friend-preview installation

Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. Drag the app to Applications. If macOS blocks the first launch, try once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or run Terminal commands.

This universal build supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. The ZIP and DMG contain the same application and first-open instructions. Use `SHA256SUMS.txt` to verify either download.

# Kistulentz 0.10.0 — Document Import

Version 0.10.0 expands Kistulentz beyond Markdown-only workflows while keeping Markdown as the safe, portable editing format. Writers can import common word-processing and web formats, inspect the conversion, and save a new Markdown copy without changing the source document.

## New import formats

- **Import Document…** accepts TXT, DOCX, RTF, RTFD, HTML, HTM, and ODT files
- TXT and plain-text files can also open directly as editable documents
- Imported documents become a new Markdown file chosen by the writer
- The original file is never overwritten or silently modified

## Conversion review

- A preview shows the converted Markdown before it is saved
- A conversion report identifies preserved structure, extracted assets, and anything that may need attention
- DOCX tracked insertions and deletions appear as review cards with individual **Accept** and **Reject** decisions
- **Accept All** and **Reject All** are available, but saving remains disabled until every tracked change is resolved

## Structure and assets

- Headings, lists, bold and italic text, links, footnotes, comments, tables, and images are retained where the source format represents them clearly
- Imported images are copied to a uniquely named assets folder beside the Markdown file
- HTML import removes scripts, embedded active content, inline styling, and remote-image downloads
- Local and embedded images can be preserved without contacting an external service

## Privacy and compatibility

- Document conversion runs locally and does not send the imported document to OpenAI, Anthropic, or another service
- The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later
- Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account
- The ZIP and DMG contain the same app, GPL license, first-open instructions, source-code notice, and these release notes. Use `SHA256SUMS.txt` to verify either download

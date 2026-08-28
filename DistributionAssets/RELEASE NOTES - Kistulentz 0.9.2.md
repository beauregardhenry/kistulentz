# Kistulentz 0.9.2 — Friend Preview

Version 0.9.2 is a publication-confidence release. It adds destination-aware checks and complete submission folders while keeping the manuscript and every validation step local.

## What is new

- Independent, multi-select publication destinations for Generic EPUB 3.3, Apple Books, Kindle/KDP eBook, KDP Print, IngramSpark eBook, and IngramSpark Print
- Explicit destination presets that choose the required format and raise locally checkable minimum settings without replacing the author's typography or trim decisions
- Target-specific checks for accepted formats, covers, Apple Books image limits, Kindle navigation, print margins, estimated image resolution, and other locally verifiable requirements
- Print profiles with no-bleed or 0.125-inch outside bleed; bleed PDFs include MediaBox, TrimBox, and BleedBox data without gutter bleed or printer marks
- A complete submission folder containing the publication, a separate supplied cover when available, SHA-256 checksums, a machine-readable package manifest, and readiness reports in Markdown and PDF
- Submission Readiness Reports that distinguish **Passed Locally**, **Action Required**, **External Validation Required**, and **Manual Review Required** without claiming retailer certification
- Automatic EPUBCheck execution when its command-line tool is already installed, plus local detection of Kindle Previewer and Apple Transporter
- Final print page-count reporting and KDP gutter-bracket checks after PDF generation
- Safer EPUB accessibility metadata that does not claim alternative text, textual sufficiency, or absence of hazards unless the generated content supports that claim
- Shareable diagnostics that intentionally omit manuscript prose and excerpts

## Important limits

Kistulentz cannot guarantee acceptance by a retailer. Apple Transporter, Kindle Previewer, retailer upload validation, current cover templates, and human visual/accessibility review remain authoritative where the report identifies them. Kistulentz does not convert print artwork to a printer-specific CMYK profile, and it copies supplied print-cover PDFs without modifying them.

## Privacy

Target checks, installed-tool detection, EPUBCheck execution, packaging, checksums, and report generation run locally. The shareable report and package manifest contain settings, filenames, findings, and checksums but no manuscript prose or excerpts. Publication export does not contact an AI provider.

## Friend-preview installation

Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. Drag the app to Applications. If macOS blocks the first launch, try once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or run Terminal commands.

This universal build supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. The ZIP and DMG contain the same application, first-open instructions, GPL license, corresponding-source notice, and release notes. Use `SHA256SUMS.txt` to verify either download.

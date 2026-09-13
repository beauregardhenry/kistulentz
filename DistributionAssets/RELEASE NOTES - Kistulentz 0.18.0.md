# Kistulentz 0.18.0 — Storage, Import, and Reliability Hardening

Version 0.18.0 concentrates on protecting work when files are malformed, disks refuse a write,
or a large background operation is cancelled.

## Safer saves and libraries

- Snapshot, reference-library, and publication changes now become current only after their
  on-disk records succeed. An interrupted write keeps the last known-good state and cleans up
  uncommitted snapshot copies.
- A publication cover cannot replace an existing folder with the same name.
- Corrupt managed-attachment paths cannot reach outside the chosen Research Library.

## More defensive imports

- Imported filenames remove path traversal, separators, and control characters before files are
  created.
- HTML import strips executable links and event handlers while preserving safe prose and links.
- Malformed EPUB, BibTeX, RIS, CSL-JSON, ODT, RTF, and RTFD inputs are rejected without creating
  partial documents or sources.

## Long-project analysis

- Manuscript context sent through an approved AI command now respects its size budget, shares that
  budget across the selected sections, and retains both the opening and ending.
- Large De-stink reviews can be cancelled and closed without leaving the editor stuck or accepting
  a late result from obsolete work.

## Expanded reliability coverage

- New end-to-end journeys exercise project search, the Bible and custom beta readers, named
  snapshots, reading-grade settings, English-pack failure and retry, DOCX and PDF publication,
  De-stink navigation, and large-run cancellation.
- Upgrade fixtures cover every prior project schema while verifying that manuscript Markdown is
  unchanged.
- Opt-in scale tests cover two-million-word projects, 2,000 documents, 5,000 reference books,
  1,000 imported files, repeated project lifecycles, and repeated publication exports.
- UI tests now use isolated preferences and cannot accidentally open a tester's real libraries.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS
Sequoia 15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple
Developer account.

# Kistulentz 0.11.0 — Project Import Assistant

Version 0.11.0 adds a guided workflow for turning a collection of existing documents into an ordered Markdown manuscript or a structured Kistulentz project. The entire import remains local, every source stays untouched, and nothing is written until the author has reviewed the plan and converted results.

## Multiple files and folders

- Add several individual documents, recursively selected folders, or both
- Import Markdown, TXT, DOCX, RTF, RTFD, HTML, HTM, and ODT sources together
- Duplicate selections are removed automatically
- Arrange files before conversion with explicit earlier and later controls
- Edit the document title and assign Part, Chapter, Scene, or Section in the preview

## Progress, review, and recovery

- Conversion reports progress one document at a time and can be cancelled
- A failure remains attached to its source and does not stop later documents
- Failed documents can be retried without reconverting successful ones
- Every successful document has its own Markdown, conversion-warning, image, and tracked-change preview
- Tracked insertions and deletions still require Accept or Reject decisions before output

## Three author-controlled outputs

- Save one combined Markdown manuscript
- Create and open a new fiction or nonfiction Kistulentz project
- Add the successful documents to the currently open project
- Combined Markdown uses level-one headings for Parts, level-two for Chapters, and level-three for Scenes or Sections
- Existing source headings shift down to preserve the imported hierarchy; fenced code is left unchanged
- Scenes and Sections must follow a Chapter, with a clear correction shown before project creation

## File safety

- Original documents are never rewritten or moved
- Imported images receive collision-free filenames in a separate local assets folder
- Existing project documents are never replaced; duplicate titles receive numbered Markdown filenames
- Existing combined Markdown exports are not overwritten
- Project metadata and newly created files roll back if a project write fails

The universal application supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. Kistulentz remains ad-hoc signed because Beau Henry does not yet have an Apple Developer account.

# Kistulentz 0.20.0 — Internal Hardening

Version 0.20.0 concentrates on protecting an author's work and making the preview release easier
to verify. It deliberately avoids a broad new author-facing feature while tightening the systems
under the editor, imports, references, projects, and publishing tools.

## Safer local files

- Manuscripts, project metadata, imports, recovery copies, research and reference data,
  diagnostics, and publication settings now use one tested safe-write path.
- A full disk or interrupted write leaves the last known-good destination intact. Staged files are
  cleaned up, and Kistulentz reports separately if that cleanup cannot be completed.
- DOCX, ODT, and EPUB archives are inspected before use. Kistulentz rejects unsafe paths, symbolic
  links, filename collisions, oversized entries, excessive total expansion, too many entries, and
  extreme compression ratios.

## More predictable long operations

- Document import, Project Import, publication export, reference import, and Benepar reference
  analysis now share consistent cancellation and stale-result handling.
- Opt-in performance checks now measure rapid typing, large paste analysis, project search,
  Project Polish, reference filtering, publication export, large imports, and project endurance.
- Several large interface files have been separated into focused editors and sheets so future
  fixes can remain smaller and easier to test.

## Verifiable packages

- The ZIP and DMG include an SPDX 2.3 software bill of materials. The SBOM is also published as a
  separately checksummed release asset.
- Tagged GitHub builds record both build-provenance and SBOM attestations using GitHub's supported
  artifact-attestation service.

## Privacy and compatibility

All analysis remains local unless the author separately previews and approves an AI-backed
command. This universal application supports Apple silicon and Intel Macs running macOS Sequoia
15 or later. Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer
account; the documented first-open process remains unchanged.

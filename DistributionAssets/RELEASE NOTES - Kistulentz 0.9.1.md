# Kistulentz 0.9.1 — Friend Preview

Version 0.9.1 is a reliability and open-source readiness release. It preserves the editorial and publication features of 0.9.0 while making older projects safer to open and recover.

## What is new

- Automatic, versioned migration of project metadata created by earlier Kistulentz previews
- A complete pre-migration metadata snapshot before an older project is updated
- Up to three rolling last-known-good metadata snapshots after successful project opens
- A recovery window for restoring a known-good, pre-migration, or pre-recovery snapshot when project metadata cannot be read
- A safety snapshot of the failed metadata before any recovery is performed
- Recovery changes project metadata only and never replaces manuscript Markdown
- Internal source and test names now consistently use Kistulentz
- GNU GPL v3-or-later licensing, contributor, privacy, security, and support documentation
- License and corresponding-source information included in both the application and shareable package
- Generated personal Reference Library data and obsolete release archives removed from the current source tree

## Privacy

Migration, backup, and recovery run entirely on the Mac. Recovery snapshots are kept in a hidden `.kistulentz-backups` folder beside the project's hidden `.kistulentz` metadata folder. No manuscript, project, or snapshot is sent to an AI provider automatically.

## Friend-preview installation

Kistulentz is ad-hoc signed because Beau Henry does not yet have an Apple Developer account. Drag the app to Applications. If macOS blocks the first launch, try once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper or run Terminal commands.

This universal build supports Apple silicon and Intel Macs running macOS Sequoia 15 or later. The ZIP and DMG contain the same application, first-open instructions, GPL license, corresponding-source notice, and release notes. Use `SHA256SUMS.txt` to verify either download.

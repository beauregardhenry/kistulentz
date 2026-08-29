# Contributing to Kistulentz

Thank you for helping improve Kistulentz. Contributions for fiction, nonfiction, accessibility, privacy, reliability, and publication quality are welcome.

## Before opening a change

- Search existing GitHub issues and pull requests for related work.
- For a bug, describe the Kistulentz version, macOS version, Mac architecture, expected result, actual result, and minimal reproduction steps.
- Do not upload manuscripts, copyrighted reference libraries, API keys, private research, or other sensitive material. Use small original fixtures in tests.
- Keep generated builds, release archives, user libraries, and project backups out of the repository.

## Build and test

Kistulentz requires macOS Sequoia 15 or later and Xcode 26 or newer installed at `/Applications/Xcode.app`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
```

To build the universal Mac application:

```sh
./scripts/build-app.sh
```

The optional Benepar language pack is deliberately separate from the application. Its Python runtime, dependency versions, model, architecture, license files, archive size, and SHA-256 checksum must remain reproducible and pinned. Use the manual **Build English language packs** workflow to validate both Apple-silicon and Intel packs; leave publishing disabled for test builds.

Changes that affect project metadata should include compatibility tests. Changes that can alter prose should preserve normal macOS Undo, create the appropriate project snapshot, and never overwrite manuscript Markdown without explicit author approval.

## Pull requests

Keep each pull request focused. Explain the user-visible result, privacy or migration implications, and tests performed. Update public documentation and release notes when behavior changes.

By contributing, you agree that your contribution is licensed under the GNU General Public License, version 3 or any later version, as described in [LICENSE](LICENSE).

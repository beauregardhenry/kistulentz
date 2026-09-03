# Contributing to Kistulentz

Thank you for helping improve Kistulentz. Contributions for fiction, nonfiction, accessibility, privacy, reliability, and publication quality are welcome.

## Before opening a change

- Search existing GitHub issues and pull requests for related work.
- For a bug, describe the Kistulentz version, macOS version, Mac architecture, expected result, actual result, and minimal reproduction steps.
- Do not upload manuscripts, copyrighted reference libraries, API keys, private research, or other sensitive material. Use small original fixtures in tests.
- Keep generated builds, release archives, user libraries, and project backups out of the repository.

## Build and test

Kistulentz requires macOS Sequoia 15 or later. Xcode 26 or newer is needed to run the tests and to produce the universal application; the Command Line Tools alone are enough to build and run Kistulentz on your own Mac.

```sh
swift test --disable-sandbox
```

Pull requests and pushes to `main` run the same SwiftPM tests in CI, check the coverage ratchet, build and verify the universal application bundle, and run the bounded macOS UI regression suite.

`swift test` reports `no such module 'XCTest'` when only the Command Line Tools are installed, because XCTest ships with Xcode.

## Test coverage

Line coverage over the app sources only moves up. CI measures it after the tests and fails when it drops below the floor in [coverage-baseline.txt](coverage-baseline.txt), so a change that adds untested logic has to account for it rather than quietly diluting the suite. `Views/` is excluded: SwiftUI view bodies are about a third of the source and are exercised by the separate macOS UI regression job, which never reaches this profile.

```sh
swift test --enable-code-coverage --disable-sandbox
./scripts/check-coverage.sh
```

The check prints the current percentage and the five least-covered files. When coverage climbs, lock the gain in and commit the result:

```sh
./scripts/check-coverage.sh --update
```

Lowering the baseline is allowed but never incidental: do it in its own commit and say why.

To build the Mac application:

```sh
./scripts/build-app.sh
```

The script finds Xcode automatically and builds the universal application when it is present, so `DEVELOPER_DIR` only needs to be set when Xcode is installed somewhere other than `/Applications/Xcode.app`. Without Xcode it builds for the current architecture and says so. `./scripts/package-release.sh` always requires the universal build, so a release archive can never be published with one architecture missing.
The optional Benepar language pack is deliberately separate from the application. Its Python runtime, dependency versions, model, architecture, license files, archive size, and SHA-256 checksum must remain reproducible and pinned. Use the manual **Build English language packs** workflow to validate both Apple-silicon and Intel packs; leave publishing disabled for test builds.

Changes that affect project metadata should include compatibility tests. Changes that can alter prose should preserve normal macOS Undo, create the appropriate project snapshot, and never overwrite manuscript Markdown without explicit author approval.

## Pull requests

Keep each pull request focused. Explain the user-visible result, privacy or migration implications, and tests performed. Update public documentation and release notes when behavior changes.

By contributing, you agree that your contribution is licensed under the GNU General Public License, version 3 or any later version, as described in [LICENSE](LICENSE).

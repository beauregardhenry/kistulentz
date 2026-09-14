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

Pull requests and pushes to `main` run the same SwiftPM tests in CI, check for banned patterns, check the coverage and test count ratchets, build and verify the universal application bundle, and run the bounded macOS UI regression suite.

`swift test` reports `no such module 'XCTest'` when only the Command Line Tools are installed, because XCTest ships with Xcode.

## Banned patterns

`as!`, `fatalError(`, `print(`, and `TODO`/`FIXME` comment markers hold at zero in `AppSources/Kistulentz`. None of these have a legitimate use in shipped app code: a forced downcast or `fatalError` should be a real, reported error instead; a `print(` is leftover debug output; a `TODO`/`FIXME` is deferred work that should become a tracked issue instead of a comment nobody revisits.

```sh
./scripts/check-banned-patterns.sh
```

This is a fixed floor of zero, not a ratchet against a baseline file — there's no legitimate reason for any of these counts to ever be nonzero, so the check just fails the moment one appears. (`try!` is deliberately not included: every current use compiles a literal, known-good `NSRegularExpression` pattern at static-initialization time, a well-established safe idiom, not the same risk as the four patterns above.)

## Test coverage

Line coverage over the app sources only moves up. CI measures it after the tests and fails when it drops below the floor in [coverage-baseline.txt](coverage-baseline.txt), so a change that adds untested logic has to account for it rather than quietly diluting the suite. `Views/` is excluded: SwiftUI view bodies are about a third of the source and are exercised by the separate macOS UI regression job, which never reaches this profile.

```sh
swift test --enable-code-coverage --disable-sandbox
./scripts/check-coverage.sh
```

The check prints the current percentage and the five least-covered files. Don't run `--update` and commit the result yourself: a `coverage-ratchet` GitHub Actions job re-measures on every push to `main` and commits the raised baseline itself, so two PRs open at the same time never both edit `coverage-baseline.txt` and conflict with each other. Your PR only needs the plain form above to pass.

Lowering the baseline is allowed but never incidental: do it in its own commit with `./scripts/check-coverage.sh --update` and say why.

## Test count

The Swift and Xcode UI test counts only move up too, the same shape as coverage: CI fails if either drops below the floor in [test-count-baseline.txt](test-count-baseline.txt). Coverage mostly catches a deleted test as well, since removing one usually lowers the percentage, but a raw count is a more direct signal and catches a test quietly commented out or `.skip`ped even when coverage barely moves.

```sh
./scripts/check-test-count.sh
```

The check counts `func test...()` methods statically, so it needs no build products and runs in seconds. As with coverage, don't run `--update` and commit the result yourself: a `test-count-ratchet` GitHub Actions job re-measures on every push to `main` and commits the raised baseline itself. Lowering it is allowed but never incidental: do it in its own commit with `./scripts/check-test-count.sh --update` and say why.

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

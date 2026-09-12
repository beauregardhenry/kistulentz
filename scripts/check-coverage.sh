#!/bin/zsh
set -euo pipefail

# Test coverage only ratchets one way. This measures line coverage over the app sources and fails
# when it slips below the number recorded in coverage-baseline.txt, so a change that adds untested
# code has to say so out loud instead of quietly diluting the suite.
#
# Views/ is excluded on purpose: SwiftUI view bodies are ~a third of the source and are exercised
# by the Xcode UI tests, which run in a separate job and never reach this profile. Counting them
# here would swamp the signal from Models/ and Services/ with code this suite cannot touch.
# App/ stays in even though the @main entry point is untestable the same way; at ~180 lines it is
# a constant drag on the number, not a growing one, and excluding it invites excluding more.
#
# Do NOT bump coverage-baseline.txt from a feature branch. A .github/workflows/coverage-ratchet.yml
# job re-measures on every push to main and commits the raised number itself, so two PRs in flight
# at once never both edit the same line and conflict with each other on merge. A feature branch
# only needs the plain (no-flag) form below to pass; leave the file alone.
#
#   ./scripts/check-coverage.sh                 measure and enforce the baseline (what a PR runs)
#   ./scripts/check-coverage.sh --update-if-higher
#       measure and raise the baseline only if it climbed past the ratchet slack; never lowers it.
#       This is what the post-merge workflow runs on main -- not meant for a feature branch.
#   ./scripts/check-coverage.sh --update        measure and unconditionally rewrite the baseline.
#       For deliberately lowering it (with a reason in the commit) or fixing up the file by hand;
#       not the normal way coverage climbs.

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/coverage-baseline.txt"
IGNORE_REGEX='(^|/)(\.build|Tests|AppSources/Kistulentz/Views)/'

architecture="${COVERAGE_ARCHITECTURE:-$(uname -m)}"
case "$architecture" in
    arm64|arm64e) architecture="arm64" ;;
    x86_64) ;;
    *)
        print -u2 "Coverage check failed: unsupported architecture '$architecture'."
        exit 1
        ;;
esac

# How far coverage may drift below the baseline before the build fails. Small enough to catch a
# deleted test, loose enough to absorb rounding when unrelated files move around.
TOLERANCE="${COVERAGE_TOLERANCE:-0.25}"
# How far above the baseline coverage has to climb before we nag about raising it.
RATCHET_SLACK="${COVERAGE_RATCHET_SLACK:-0.5}"

cd "$PROJECT_ROOT"

mode=check
case "${1:-}" in
    --update) mode=update ;;
    --update-if-higher) mode=update-if-higher ;;
    "") ;;
    *)
        print -u2 "Usage: ${0:t} [--update|--update-if-higher]"
        exit 2
        ;;
esac

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"

print "Running the test suite with a fresh coverage profile."
swift test --enable-code-coverage --disable-sandbox

if [[ ! -f "$PROFDATA" ]]; then
    print -u2 "Coverage check failed: $PROFDATA was not produced."
    print -u2 "Run 'swift test --enable-code-coverage --disable-sandbox' first."
    exit 1
fi

typeset -a binaries
binaries=("$BIN_PATH"/*.xctest/Contents/MacOS/*(.N))
if (( ${#binaries} == 0 )); then
    print -u2 "Coverage check failed: no .xctest binary under $BIN_PATH."
    exit 1
fi

report="$(xcrun llvm-cov export \
    -summary-only \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex "$IGNORE_REGEX" \
    "${binaries[@]}")"

# llvm-cov reports per-file summaries; pull the total plus the least-covered files so a failure
# points at something actionable rather than just a number.
measured="$(print -r -- "$report" | /usr/bin/python3 -c '
import json, sys

report = json.load(sys.stdin)
export = report["data"][0]
total = export["totals"]["lines"]
print("%.2f %d %d" % (total["percent"], total["covered"], total["count"]))

files = [f for f in export["files"] if f["summary"]["lines"]["count"] >= 20]
files.sort(key=lambda f: f["summary"]["lines"]["percent"])
for entry in files[:5]:
    lines = entry["summary"]["lines"]
    print("%s\t%.1f\t%d" % (entry["filename"], lines["percent"], lines["count"]))
')"

percent="$(print -r -- "$measured" | head -1 | cut -d" " -f1)"
covered="$(print -r -- "$measured" | head -1 | cut -d" " -f2)"
total_lines="$(print -r -- "$measured" | head -1 | cut -d" " -f3)"

print "Line coverage (app sources outside Views/): ${percent}% (${covered}/${total_lines} lines)"
print "Least-covered files:"
print -r -- "$measured" | tail -n +2 | while IFS=$'\t' read -r file pct count; do
    printf "  %5s%%  %5s lines  %s\n" "$pct" "$count" "${file#$PROJECT_ROOT/}"
done

write_baseline() {
    local written_percent="$1"
    local arm64_baseline intel_baseline
    arm64_baseline="$(sed -n 's/^arm64=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
    intel_baseline="$(sed -n 's/^x86_64=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
    if [[ "$architecture" == "arm64" ]]; then
        arm64_baseline="$written_percent"
    else
        intel_baseline="$written_percent"
    fi
    cat > "$BASELINE_FILE" <<BASELINE
# Architecture-specific line coverage floors for app sources outside Views/.
# Coverage instrumentation differs between Apple silicon and Intel builds. Raised automatically by
# .github/workflows/coverage-ratchet.yml on every push to main; don't bump it from a feature
# branch (see the header of this script). Lower one only deliberately, with a reason in the commit.
arm64=${arm64_baseline:-$written_percent}
x86_64=${intel_baseline:-$written_percent}
BASELINE
}

baseline="$(sed -n "s/^${architecture}=//p" "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

# Accept the original single-number format while older branches transition to per-architecture
# floors. New updates always write the architecture-specific form above.
if [[ -z "$baseline" ]]; then
    baseline="$(grep -v '^[[:space:]]*#' "$BASELINE_FILE" 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
fi

if [[ "$mode" == "update" ]]; then
    write_baseline "$percent"
    print "${architecture} baseline updated to ${percent}%. Commit coverage-baseline.txt."
    exit 0
fi

if [[ -z "$baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$percent"
        print "No ${architecture} baseline recorded yet; seeded it at ${percent}%."
        exit 0
    fi
    print
    print "No coverage baseline recorded yet, so nothing to enforce."
    print "This is normally seeded by the post-merge coverage-ratchet workflow, not by hand."
    exit 0
fi

if [[ ! "$baseline" =~ '^[0-9]+(\.[0-9]+)?$' ]]; then
    print -u2 "Coverage check failed: coverage-baseline.txt does not contain a number ('$baseline')."
    exit 1
fi

floor="$(/usr/bin/python3 -c "print('%.2f' % max(0.0, $baseline - $TOLERANCE))")"
verdict="$(/usr/bin/python3 -c "print('below' if $percent < $floor else ('above' if $percent > $baseline + $RATCHET_SLACK else 'held'))")"

print

if [[ "$mode" == "update-if-higher" ]]; then
    # Runs post-merge on main, never in a PR: only ever raises the floor, and a regression here
    # means something merged despite the PR-time check below failing or being skipped, so it's
    # surfaced loudly rather than silently lowering the bar.
    case "$verdict" in
        below)
            print -u2 "Coverage check failed: ${percent}% is below the ${architecture} ${baseline}% baseline (floor ${floor}%) on main."
            print -u2 "The baseline was left untouched; investigate how a regression reached main."
            exit 1
            ;;
        above)
            write_baseline "$percent"
            print "${architecture} baseline raised from ${baseline}% to ${percent}%. Committing coverage-baseline.txt."
            ;;
        held)
            print "Coverage holds at ${percent}% against the ${architecture} ${baseline}% baseline; nothing to update."
            ;;
    esac
    exit 0
fi

case "$verdict" in
    below)
        print -u2 "Coverage check failed: ${percent}% is below the ${architecture} ${baseline}% baseline (floor ${floor}%)."
        print -u2 "Add tests for the new code, or lower coverage-baseline.txt deliberately and say why in the commit."
        exit 1
        ;;
    above)
        print "Coverage rose to ${percent}% from the ${architecture} ${baseline}% baseline."
        print "No action needed: the post-merge coverage-ratchet workflow will raise the baseline on main automatically."
        ;;
    held)
        print "Coverage holds at ${percent}% against the ${architecture} ${baseline}% baseline."
        ;;
esac

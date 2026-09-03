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
#   ./scripts/check-coverage.sh            measure and enforce the baseline
#   ./scripts/check-coverage.sh --update   measure and rewrite the baseline (commit the result)

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/coverage-baseline.txt"
IGNORE_REGEX='(^|/)(\.build|Tests|AppSources/Kistulentz/Views)/'

# How far coverage may drift below the baseline before the build fails. Small enough to catch a
# deleted test, loose enough to absorb rounding when unrelated files move around.
TOLERANCE="${COVERAGE_TOLERANCE:-0.25}"
# How far above the baseline coverage has to climb before we nag about raising it.
RATCHET_SLACK="${COVERAGE_RATCHET_SLACK:-0.5}"

cd "$PROJECT_ROOT"

update_baseline=0
if [[ "${1:-}" == "--update" ]]; then
    update_baseline=1
elif [[ $# -gt 0 ]]; then
    print -u2 "Usage: ${0:t} [--update]"
    exit 2
fi

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"

if [[ ! -f "$PROFDATA" ]]; then
    print "No coverage profile at $PROFDATA; running the test suite."
    swift test --enable-code-coverage --disable-sandbox
fi

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

if (( update_baseline )); then
    cat > "$BASELINE_FILE" <<BASELINE
# Line coverage floor for the app sources outside Views/, enforced by scripts/check-coverage.sh.
# Raise it when coverage climbs; lower it only deliberately, with a reason in the commit.
$percent
BASELINE
    print "Baseline updated to ${percent}%. Commit coverage-baseline.txt."
    exit 0
fi

baseline="$(grep -v '^[[:space:]]*#' "$BASELINE_FILE" 2>/dev/null | tr -d '[:space:]' || true)"

if [[ -z "$baseline" ]]; then
    print
    print "No coverage baseline recorded yet, so nothing to enforce."
    print "Record this run with './scripts/check-coverage.sh --update' and commit coverage-baseline.txt."
    exit 0
fi

if [[ ! "$baseline" =~ '^[0-9]+(\.[0-9]+)?$' ]]; then
    print -u2 "Coverage check failed: coverage-baseline.txt does not contain a number ('$baseline')."
    exit 1
fi

floor="$(/usr/bin/python3 -c "print('%.2f' % max(0.0, $baseline - $TOLERANCE))")"
verdict="$(/usr/bin/python3 -c "print('below' if $percent < $floor else ('above' if $percent > $baseline + $RATCHET_SLACK else 'held'))")"

print
case "$verdict" in
    below)
        print -u2 "Coverage check failed: ${percent}% is below the ${baseline}% baseline (floor ${floor}%)."
        print -u2 "Add tests for the new code, or lower coverage-baseline.txt deliberately and say why in the commit."
        exit 1
        ;;
    above)
        print "Coverage rose to ${percent}% from a ${baseline}% baseline."
        print "Lock it in: './scripts/check-coverage.sh --update' and commit coverage-baseline.txt."
        ;;
    held)
        print "Coverage holds at ${percent}% against the ${baseline}% baseline."
        ;;
esac

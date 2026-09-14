#!/bin/zsh
set -euo pipefail

# Test count only ratchets one way, the same shape as check-coverage.sh: fails when either suite's
# test-method count drops below the number recorded in test-count-baseline.txt. Coverage mostly
# catches a deleted test too (removing a test usually lowers the percentage), but a raw count is a
# more direct signal and harder to lose in the noise -- a test quietly commented out, `.skip`ped,
# or deleted during a merge conflict shows up here even when the coverage percentage barely moves.
#
# Counting is static: a grep over `func test...()` in each Tests/ directory, not an actual test
# run. That keeps this check fast and dependency-free (no Xcode, no simulator, no built product)
# and the numbers it produces match what swift test / xcodebuild actually report ("Executed N
# tests") exactly, since every test method in this codebase follows the same `func testFoo()`
# naming XCTest requires.
#
# Do NOT bump test-count-baseline.txt from a feature branch. A .github/workflows/test-count-ratchet.yml
# job re-measures on every push to main and commits the raised numbers itself, the same
# single-writer convention check-coverage.sh's baseline already uses.
#
#   ./scripts/check-test-count.sh                 measure and enforce the baseline (what a PR runs)
#   ./scripts/check-test-count.sh --update-if-higher
#       measure and raise the baseline only for a suite whose count climbed; never lowers either.
#       This is what the post-merge workflow runs on main -- not meant for a feature branch.
#   ./scripts/check-test-count.sh --update        measure and unconditionally rewrite the baseline.
#       For deliberately lowering it (with a reason in the commit) or fixing up the file by hand;
#       not the normal way test counts climb.

PROJECT_ROOT="${0:A:h:h}"
BASELINE_FILE="$PROJECT_ROOT/test-count-baseline.txt"

count_tests() {
    local dir="$1"
    grep -rhoE 'func test[A-Za-z0-9_]+\(\)' "$dir"/*.swift 2>/dev/null | wc -l | tr -d '[:space:]'
}

swift_count="$(count_tests "$PROJECT_ROOT/Tests/KistulentzTests")"
ui_count="$(count_tests "$PROJECT_ROOT/Tests/KistulentzUITests")"

print "Swift test count: ${swift_count}"
print "UI test count: ${ui_count}"

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

write_baseline() {
    local written_swift="$1"
    local written_ui="$2"
    cat > "$BASELINE_FILE" <<BASELINE
# Test-method-count floors for the Swift and Xcode UI test suites. Raised automatically by
# .github/workflows/test-count-ratchet.yml on every push to main; don't bump it from a feature
# branch (see the header of scripts/check-test-count.sh). Lower one only deliberately, with a
# reason in the commit.
swift=${written_swift}
ui=${written_ui}
BASELINE
}

swift_baseline="$(sed -n 's/^swift=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
ui_baseline="$(sed -n 's/^ui=//p' "$BASELINE_FILE" 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"

if [[ "$mode" == "update" ]]; then
    write_baseline "$swift_count" "$ui_count"
    print "Baseline updated to swift=${swift_count}, ui=${ui_count}. Commit test-count-baseline.txt."
    exit 0
fi

if [[ -z "$swift_baseline" || -z "$ui_baseline" ]]; then
    if [[ "$mode" == "update-if-higher" ]]; then
        write_baseline "$swift_count" "$ui_count"
        print "No baseline recorded yet; seeded it at swift=${swift_count}, ui=${ui_count}."
        exit 0
    fi
    print
    print "No test-count baseline recorded yet, so nothing to enforce."
    print "This is normally seeded by the post-merge test-count-ratchet workflow, not by hand."
    exit 0
fi

print
failed=0
new_swift_baseline="$swift_baseline"
new_ui_baseline="$ui_baseline"

check_suite() {
    local label="$1" count="$2" baseline="$3"
    if (( count < baseline )); then
        print -u2 "Test count check failed: ${label} count ${count} is below the ${baseline} baseline."
        print -u2 "A test was removed, renamed away from the testFoo() pattern, or commented out."
        print -u2 "Add tests back, or lower test-count-baseline.txt deliberately and say why in the commit."
        failed=1
    elif (( count > baseline )); then
        print "${label} test count rose to ${count} from the ${baseline} baseline."
    else
        print "${label} test count holds at ${count}."
    fi
}

check_suite "Swift" "$swift_count" "$swift_baseline"
check_suite "UI" "$ui_count" "$ui_baseline"

if [[ "$mode" == "update-if-higher" ]]; then
    (( swift_count > swift_baseline )) && new_swift_baseline="$swift_count"
    (( ui_count > ui_baseline )) && new_ui_baseline="$ui_count"
    if [[ "$new_swift_baseline" != "$swift_baseline" || "$new_ui_baseline" != "$ui_baseline" ]]; then
        write_baseline "$new_swift_baseline" "$new_ui_baseline"
        print "Baseline raised to swift=${new_swift_baseline}, ui=${new_ui_baseline}. Committing test-count-baseline.txt."
    else
        print "Nothing to update."
    fi
    # Runs post-merge on main, never in a PR: a drop here means something merged despite the
    # PR-time check below failing or being skipped, so it's surfaced loudly rather than silently
    # lowering either floor.
    exit "$failed"
fi

print "No action needed: the post-merge test-count-ratchet workflow will raise either baseline automatically."
exit "$failed"

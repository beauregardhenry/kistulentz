#!/bin/zsh
set -euo pipefail

# Four patterns that should never appear in production app code, all currently at zero. This
# ratchets structurally rather than numerically: the floor is just 0, forever, with no baseline
# file, tolerance, or architecture split to manage the way coverage needs -- there's no legitimate
# reason for any of these counts to ever rise above zero, so failing the moment one does is the
# whole design.
#
# try! is deliberately NOT included here even though it's the same "force-unwrap" family as as!:
# every current use in this codebase is `try! NSRegularExpression(pattern: <literal>)`, a
# well-established, safe idiom for compiling a known-good pattern once at static-initialization
# time -- it can only ever fail on a malformed literal, caught the moment that file first runs in
# development, never on runtime data. A genuinely risky try! (on data from disk, the network, or
# user input) deserves exactly the same scrutiny as as!/fatalError, but a blanket ban here would
# be pure noise against ~35 legitimate current uses without catching anything code review
# wouldn't already catch.

PROJECT_ROOT="${0:A:h:h}"
SOURCE_DIR="$PROJECT_ROOT/AppSources/Kistulentz"

typeset -a findings
findings=()

check_pattern() {
    local label="$1"
    local grep_pattern="$2"
    local matches
    matches="$(grep -rnE "$grep_pattern" "$SOURCE_DIR" --include='*.swift' || true)"
    if [[ -n "$matches" ]]; then
        findings+=("$label")
        print -u2 ""
        print -u2 "Found ${label}:"
        print -r -- "$matches" | while IFS= read -r line; do
            print -u2 "  ${line#$PROJECT_ROOT/}"
        done
    fi
}

check_pattern "as! (forced downcast)" '\bas!'
check_pattern "fatalError(" 'fatalError\('
check_pattern "print( (debug output left in)" '\bprint\('
check_pattern "TODO/FIXME comment markers" '//\s*(TODO|FIXME)'

if (( ${#findings} > 0 )); then
    print -u2 ""
    print -u2 "Banned-pattern check failed: ${#findings} pattern(s) found in AppSources/Kistulentz."
    print -u2 "Replace a forced downcast or fatalError with a real error path, remove a leftover"
    print -u2 "debug print(), and either finish or file the TODO/FIXME as a tracked issue before"
    print -u2 "merging -- these patterns hold at zero on main."
    exit 1
fi

print "Banned-pattern check passed: no as!, fatalError(, print(, or TODO/FIXME in AppSources/Kistulentz."

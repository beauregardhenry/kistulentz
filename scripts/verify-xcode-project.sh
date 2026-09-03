#!/bin/zsh
set -euo pipefail

# Kistulentz.xcodeproj is generated from project.yml but checked in, so a source file added to a
# target's directory without regenerating leaves the UI-test host unbuildable. Catch that drift
# here instead of in a build failure five minutes into CI.

PROJECT_ROOT="${0:A:h:h}"
PBXPROJ="$PROJECT_ROOT/Kistulentz.xcodeproj/project.pbxproj"

cd "$PROJECT_ROOT"

if [[ ! -f "$PBXPROJ" ]]; then
    print -u2 "Xcode project verification failed: $PBXPROJ is missing."
    exit 1
fi

typeset -a missing
for source in AppSources/Kistulentz/**/*.swift(.N) Tests/KistulentzUITests/**/*.swift(.N); do
    if ! grep -qF "/* ${source:t} */" "$PBXPROJ"; then
        missing+=("$source")
    fi
done

if (( ${#missing} > 0 )); then
    print -u2 "Xcode project verification failed: Kistulentz.xcodeproj is out of date with the sources."
    for source in $missing; do
        print -u2 "  missing: $source"
    done
    print -u2 "Regenerate it with ./scripts/regenerate-xcode-project.sh and commit the result."
    exit 1
fi

print "Kistulentz.xcodeproj references all $(print -l AppSources/Kistulentz/**/*.swift(.N) Tests/KistulentzUITests/**/*.swift(.N) | wc -l | tr -d ' ') target sources."

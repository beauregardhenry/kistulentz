#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "XcodeGen 2.46 or newer is required to regenerate Kistulentz.xcodeproj."
    print -u2 "Install it with Homebrew: brew install xcodegen"
    exit 1
fi

cd "$PROJECT_ROOT"
xcodegen generate --spec project.yml
print "Regenerated Kistulentz.xcodeproj from project.yml."

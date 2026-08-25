#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_ROOT="$DIST_ROOT/Kistuletz.app"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/ModuleCache"

mkdir -p "$CLANG_MODULE_CACHE_PATH"

cd "$PROJECT_ROOT"
swift build \
    --configuration release \
    --arch arm64 \
    --arch x86_64 \
    --disable-sandbox

BIN_PATH="$(swift build \
    --configuration release \
    --arch arm64 \
    --arch x86_64 \
    --disable-sandbox \
    --show-bin-path)/DraftSmith"

if [[ ! -f "$BIN_PATH" ]]; then
    print -u2 "Kistuletz executable was not found at $BIN_PATH"
    exit 1
fi

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp "$BIN_PATH" "$APP_ROOT/Contents/MacOS/Kistuletz"
cp "$PROJECT_ROOT/scripts/Info.plist" "$APP_ROOT/Contents/Info.plist"
print -n "APPL????" > "$APP_ROOT/Contents/PkgInfo"

chmod +x "$APP_ROOT/Contents/MacOS/Kistuletz"
codesign --force --sign - --timestamp=none "$APP_ROOT"

print "$APP_ROOT"

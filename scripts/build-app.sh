#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_ROOT="$DIST_ROOT/Kistulentz.app"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# A full Xcode installation supplies the xcbuild support needed for the
# universal build. Prefer an explicit DEVELOPER_DIR, then Xcode in its usual
# location, then whatever xcode-select points at. When only the Command Line
# Tools are installed the app is still built, for this Mac's architecture only,
# so a new contributor can run Kistulentz without installing Xcode first.
resolve_developer_dir() {
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        if [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
            export DEVELOPER_DIR
            return 0
        fi
        print -u2 "DEVELOPER_DIR is set to '$DEVELOPER_DIR', which does not contain Xcode. Ignoring it."
        unset DEVELOPER_DIR
    fi

    if [[ -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
        export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
        return 0
    fi

    local selected
    selected="$(xcode-select --print-path 2>/dev/null || true)"
    if [[ -n "$selected" && -x "$selected/usr/bin/xcodebuild" ]]; then
        export DEVELOPER_DIR="$selected"
        return 0
    fi

    return 1
}

typeset -a BUILD_FLAGS
BUILD_FLAGS=(--configuration release --disable-sandbox)

if resolve_developer_dir; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
else
    print -u2 "Xcode was not found, so Kistulentz will be built for $(uname -m) only."
    print -u2 "Install Xcode 26 or newer at /Applications/Xcode.app to build the universal application."
fi

export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/ModuleCache"

mkdir -p "$CLANG_MODULE_CACHE_PATH"

cd "$PROJECT_ROOT"
swift build "${BUILD_FLAGS[@]}"

BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/Kistulentz"

if [[ ! -f "$BIN_PATH" ]]; then
    print -u2 "Kistulentz executable was not found at $BIN_PATH"
    exit 1
fi

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
mkdir -p "$APP_ROOT/Contents/Resources/LanguagePacks/Benepar"
cp "$BIN_PATH" "$APP_ROOT/Contents/MacOS/Kistulentz"
cp "$PROJECT_ROOT/scripts/Info.plist" "$APP_ROOT/Contents/Info.plist"
cp "$PROJECT_ROOT/LICENSE" "$APP_ROOT/Contents/Resources/LICENSE"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$APP_ROOT/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_ROOT/LanguagePacks/Benepar/benepar_worker.py" "$APP_ROOT/Contents/Resources/LanguagePacks/Benepar/benepar_worker.py"
cp "$PROJECT_ROOT/LanguagePacks/Benepar/NOTICE.md" "$APP_ROOT/Contents/Resources/LanguagePacks/Benepar/NOTICE.md"
print -n "APPL????" > "$APP_ROOT/Contents/PkgInfo"

chmod +x "$APP_ROOT/Contents/MacOS/Kistulentz"
codesign --force --sign - --timestamp=none "$APP_ROOT"

print "$APP_ROOT"

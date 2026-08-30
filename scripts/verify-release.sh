#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="${1:-$PROJECT_ROOT/dist/Kistulentz.app}"
VERIFY_RELEASE_ASSETS="${2:-}"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Kistulentz"
RESOURCES_PATH="$APP_PATH/Contents/Resources"

fail() {
    print -u2 "Release verification failed: $1"
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "application bundle not found at $APP_PATH"
[[ -f "$PLIST_PATH" ]] || fail "Info.plist is missing"
[[ -x "$EXECUTABLE_PATH" ]] || fail "application executable is missing or not executable"
plutil -lint "$PLIST_PATH" >/dev/null

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST_PATH"
}

[[ "$(read_plist CFBundleDisplayName)" == "Kistulentz" ]] || fail "display name is not Kistulentz"
[[ "$(read_plist CFBundleName)" == "Kistulentz" ]] || fail "bundle name is not Kistulentz"
[[ "$(read_plist CFBundleIdentifier)" == "com.beauhenry.kistulentz" ]] || fail "bundle identifier is incorrect"
[[ "$(read_plist LSMinimumSystemVersion)" == "15.0" ]] || fail "minimum macOS version is not 15.0"
[[ "$(read_plist CFBundleDocumentTypes:0:CFBundleTypeExtensions:0)" == "md" ]] || fail ".md support is missing"
[[ "$(read_plist CFBundleDocumentTypes:0:CFBundleTypeExtensions:1)" == "markdown" ]] || fail ".markdown support is missing"
[[ "$(read_plist CFBundleDocumentTypes:0:CFBundleTypeExtensions:2)" == "mdown" ]] || fail ".mdown support is missing"
[[ "$(read_plist CFBundleDocumentTypes:0:LSItemContentTypes:0)" == "net.daringfireball.markdown" ]] || fail "Markdown UTI is missing"
[[ "$(read_plist CFBundleDocumentTypes:1:CFBundleTypeExtensions:0)" == "txt" ]] || fail ".txt support is missing"
[[ "$(read_plist CFBundleDocumentTypes:1:CFBundleTypeExtensions:1)" == "text" ]] || fail ".text support is missing"
[[ "$(read_plist CFBundleDocumentTypes:1:LSItemContentTypes:0)" == "public.plain-text" ]] || fail "plain-text UTI is missing"

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
[[ " $ARCHITECTURES " == *" arm64 "* ]] || fail "Apple silicon executable slice is missing"
[[ " $ARCHITECTURES " == *" x86_64 "* ]] || fail "Intel executable slice is missing"

[[ -f "$RESOURCES_PATH/LICENSE" ]] || fail "GPL license is missing from the app"
[[ -f "$RESOURCES_PATH/LanguagePacks/Benepar/benepar_worker.py" ]] || fail "Benepar worker is missing"
[[ -f "$RESOURCES_PATH/LanguagePacks/Benepar/NOTICE.md" ]] || fail "Benepar notice is missing"
codesign --verify --deep --strict "$APP_PATH"

if [[ "$VERIFY_RELEASE_ASSETS" == "--release-assets" ]]; then
    VERSION="$(read_plist CFBundleShortVersionString)"
    RELEASE_ROOT="$PROJECT_ROOT/dist/releases"
    RELEASE_NAME="Kistulentz-$VERSION-macOS-universal"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.zip" ]] || fail "release ZIP is missing"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.dmg" ]] || fail "release DMG is missing"
    [[ -f "$RELEASE_ROOT/SHA256SUMS.txt" ]] || fail "release checksums are missing"
    unzip -tqq "$RELEASE_ROOT/$RELEASE_NAME.zip"
    ZIP_LISTING="$(unzip -Z1 "$RELEASE_ROOT/$RELEASE_NAME.zip")"
    [[ "$ZIP_LISTING" == *"FIRST OPEN - Kistulentz.txt"* ]] || fail "first-open instructions are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"SOURCE CODE - Kistulentz.txt"* ]] || fail "source-code notice is missing from the ZIP"
    [[ "$ZIP_LISTING" == *"RELEASE NOTES - Kistulentz $VERSION.md"* ]] || fail "versioned release notes are missing from the ZIP"
    FIRST_OPEN_TEXT="$(unzip -p "$RELEASE_ROOT/$RELEASE_NAME.zip" "*/FIRST OPEN - Kistulentz.txt")"
    SOURCE_CODE_TEXT="$(unzip -p "$RELEASE_ROOT/$RELEASE_NAME.zip" "*/SOURCE CODE - Kistulentz.txt")"
    [[ "$FIRST_OPEN_TEXT" == *"NEW IN $VERSION"* ]] || fail "first-open instructions have a stale version"
    [[ "$SOURCE_CODE_TEXT" == *"tag v$VERSION"* ]] || fail "source-code notice has a stale version tag"
    hdiutil verify -quiet "$RELEASE_ROOT/$RELEASE_NAME.dmg"
    (cd "$RELEASE_ROOT" && shasum -a 256 -c SHA256SUMS.txt)
fi

print "Kistulentz release verification passed for $APP_PATH"

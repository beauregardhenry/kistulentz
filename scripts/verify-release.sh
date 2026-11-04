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
[[ -f "$RESOURCES_PATH/THIRD_PARTY_NOTICES.md" ]] || fail "third-party notices are missing from the app"
[[ -f "$RESOURCES_PATH/LanguagePacks/Benepar/benepar_worker.py" ]] || fail "Benepar worker is missing"
[[ -f "$RESOURCES_PATH/LanguagePacks/Benepar/NOTICE.md" ]] || fail "Benepar notice is missing"
codesign --verify --deep --strict "$APP_PATH"

# A release signed with a Developer ID certificate and notarized must prove it. This is off for
# local and ad-hoc builds and on whenever the release workflow has signing credentials
# (KISTULENTZ_REQUIRE_DEVELOPER_ID=1), so a misconfigured certificate fails the build here instead of
# shipping something Gatekeeper still blocks. KISTULENTZ_EXPECTED_TEAM_ID, when set, also pins
# the signing team so a certificate from the wrong account cannot slip through.
REQUIRE_DEVELOPER_ID="${KISTULENTZ_REQUIRE_DEVELOPER_ID:-0}"

verify_developer_id_app() {
    local app="$1" details
    details="$(codesign -dvv "$app" 2>&1)"
    [[ "$details" == *"Authority=Developer ID Application"* ]] || fail "$app is not signed with a Developer ID Application certificate"
    [[ "$details" == *"(runtime)"* ]] || fail "$app is signed without the hardened runtime, which notarization requires"
    [[ "$details" == *"Timestamp="* ]] || fail "$app has no secure timestamp"
    if [[ -n "${KISTULENTZ_EXPECTED_TEAM_ID:-}" ]]; then
        [[ "$details" == *"TeamIdentifier=$KISTULENTZ_EXPECTED_TEAM_ID"* ]] || fail "$app is not signed by team $KISTULENTZ_EXPECTED_TEAM_ID"
    fi
    xcrun stapler validate "$app" >/dev/null 2>&1 || fail "$app has no valid stapled notarization ticket"
    spctl --assess --type execute --verbose=2 "$app" >/dev/null 2>&1 || fail "Gatekeeper rejects $app"
}

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    verify_developer_id_app "$APP_PATH"
fi

if [[ "$VERIFY_RELEASE_ASSETS" == "--release-assets" ]]; then
    VERSION="$(read_plist CFBundleShortVersionString)"
    RELEASE_ROOT="$PROJECT_ROOT/dist/releases"
    RELEASE_NAME="Kistulentz-$VERSION-macOS-universal"
    SBOM_NAME="Kistulentz-$VERSION.spdx.json"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.zip" ]] || fail "release ZIP is missing"
    [[ -f "$RELEASE_ROOT/$RELEASE_NAME.dmg" ]] || fail "release DMG is missing"
    [[ -f "$RELEASE_ROOT/SHA256SUMS.txt" ]] || fail "release checksums are missing"
    [[ -f "$RELEASE_ROOT/$SBOM_NAME" ]] || fail "release software bill of materials is missing"
    plutil -convert json -o /dev/null "$RELEASE_ROOT/$SBOM_NAME" || fail "release software bill of materials is invalid JSON"
    unzip -tqq "$RELEASE_ROOT/$RELEASE_NAME.zip"
    ZIP_LISTING="$(unzip -Z1 "$RELEASE_ROOT/$RELEASE_NAME.zip")"
    [[ "$ZIP_LISTING" == *"FIRST OPEN - Kistulentz.txt"* ]] || fail "first-open instructions are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"SOURCE CODE - Kistulentz.txt"* ]] || fail "source-code notice is missing from the ZIP"
    [[ "$ZIP_LISTING" == *"THIRD_PARTY_NOTICES.md"* ]] || fail "third-party notices are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"RELEASE NOTES - Kistulentz $VERSION.md"* ]] || fail "versioned release notes are missing from the ZIP"
    [[ "$ZIP_LISTING" == *"$SBOM_NAME"* ]] || fail "software bill of materials is missing from the ZIP"
    FIRST_OPEN_TEXT="$(unzip -p "$RELEASE_ROOT/$RELEASE_NAME.zip" "*/FIRST OPEN - Kistulentz.txt")"
    SOURCE_CODE_TEXT="$(unzip -p "$RELEASE_ROOT/$RELEASE_NAME.zip" "*/SOURCE CODE - Kistulentz.txt")"
    [[ "$FIRST_OPEN_TEXT" == *"NEW IN $VERSION"* ]] || fail "first-open instructions have a stale version"
    [[ "$SOURCE_CODE_TEXT" == *"tag v$VERSION"* ]] || fail "source-code notice has a stale version tag"
    grep -q " $SBOM_NAME$" "$RELEASE_ROOT/SHA256SUMS.txt" || fail "software bill of materials is missing from checksums"
    hdiutil verify -quiet "$RELEASE_ROOT/$RELEASE_NAME.dmg"
    (cd "$RELEASE_ROOT" && shasum -a 256 -c SHA256SUMS.txt)

    if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
        DMG="$RELEASE_ROOT/$RELEASE_NAME.dmg"
        codesign --verify --strict "$DMG" || fail "the DMG's signature is invalid"
        xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "the DMG has no valid stapled notarization ticket"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" >/dev/null 2>&1 \
            || fail "Gatekeeper rejects the DMG"
        # The app a user gets from the ZIP must be the stapled one, not a pre-notarization copy.
        UNZIPPED="$(mktemp -d)"
        trap 'rm -rf "$UNZIPPED"' EXIT
        ditto -x -k "$RELEASE_ROOT/$RELEASE_NAME.zip" "$UNZIPPED"
        verify_developer_id_app "$(find "$UNZIPPED" -maxdepth 2 -name 'Kistulentz.app' -type d | head -1)"
    fi
fi

print "Kistulentz release verification passed for $APP_PATH"

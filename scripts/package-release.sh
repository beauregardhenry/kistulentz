#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
RELEASE_ROOT="$DIST_ROOT/releases"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/scripts/Info.plist")"
APP_NAME="Kistulentz"
RELEASE_NAME="$APP_NAME-$VERSION-macOS-universal"
APP_PATH="$DIST_ROOT/$APP_NAME.app"
ZIP_PATH="$RELEASE_ROOT/$RELEASE_NAME.zip"
DMG_PATH="$RELEASE_ROOT/$RELEASE_NAME.dmg"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
SBOM_NAME="$APP_NAME-$VERSION.spdx.json"
SBOM_PATH="$RELEASE_ROOT/$SBOM_NAME"
RELEASE_NOTES_PATH="$PROJECT_ROOT/DistributionAssets/RELEASE NOTES - $APP_NAME $VERSION.md"
mkdir -p "$BUILD_ROOT"
STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/kistulentz-release.XXXXXX")"
PAYLOAD_ROOT="$STAGING_ROOT/$APP_NAME $VERSION"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

# Developer ID signing and notarization are opt-in: with KISTULENTZ_NOTARIZE unset this script
# produces exactly the ad-hoc-signed release it always has. Set to 1 (the release workflow does,
# when its signing secrets exist) it also needs KISTULENTZ_SIGN_IDENTITY and an App Store Connect
# API key, and it notarizes and staples both the app and the DMG.
NOTARIZE="${KISTULENTZ_NOTARIZE:-0}"
if [[ "$NOTARIZE" == "1" ]]; then
    : "${KISTULENTZ_SIGN_IDENTITY:?KISTULENTZ_NOTARIZE=1 needs KISTULENTZ_SIGN_IDENTITY (a Developer ID Application identity)}"
    : "${APPLE_API_KEY_PATH:?KISTULENTZ_NOTARIZE=1 needs APPLE_API_KEY_PATH (the App Store Connect .p8 key file)}"
    : "${APPLE_API_KEY_ID:?KISTULENTZ_NOTARIZE=1 needs APPLE_API_KEY_ID}"
    : "${APPLE_API_ISSUER_ID:?KISTULENTZ_NOTARIZE=1 needs APPLE_API_ISSUER_ID}"
    [[ "$KISTULENTZ_SIGN_IDENTITY" != "-" ]] || {
        print -u2 "KISTULENTZ_NOTARIZE=1 cannot be used with ad-hoc signing."
        exit 1
    }
fi

# Submits one file to Apple's notary service and waits. Fails unless the verdict is Accepted, and
# prints Apple's log for a rejected submission so the reason is visible in the build output.
notarize() {
    local file="$1" result verdict submission_id
    result="$(xcrun notarytool submit "$file" \
        --key "$APPLE_API_KEY_PATH" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" \
        --wait --output-format json)"
    # Not named "status": that is a read-only special parameter in zsh.
    verdict="$(print -r -- "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
    if [[ "$verdict" != "Accepted" ]]; then
        submission_id="$(print -r -- "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
        print -u2 "Notarization of ${file:t} finished as '${verdict:-unknown}', not Accepted."
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" \
                --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" >&2 || true
        fi
        exit 1
    fi
}

"$PROJECT_ROOT/scripts/build-app.sh"

BUILT_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
if [[ "$BUILT_ARCHS" != *arm64* || "$BUILT_ARCHS" != *x86_64* ]]; then
    print -u2 "$RELEASE_NAME requires a universal build, but only '$BUILT_ARCHS' was produced."
    print -u2 "Install Xcode 26 or newer at /Applications/Xcode.app and run this script again."
    exit 1
fi

if [[ "$NOTARIZE" == "1" ]]; then
    # Notarize and staple the app itself before it is copied into the payload, so the ZIP and the
    # DMG both carry the stapled ticket and the app opens offline without a Gatekeeper warning.
    ditto -c -k --keepParent "$APP_PATH" "$STAGING_ROOT/$APP_NAME-notarize.zip"
    notarize "$STAGING_ROOT/$APP_NAME-notarize.zip"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
fi

mkdir -p "$RELEASE_ROOT" "$PAYLOAD_ROOT"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/$APP_NAME.app"
cp "$PROJECT_ROOT/DistributionAssets/FIRST OPEN - Kistulentz.txt" "$PAYLOAD_ROOT/FIRST OPEN - Kistulentz.txt"
cp "$PROJECT_ROOT/LICENSE" "$PAYLOAD_ROOT/LICENSE"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$PAYLOAD_ROOT/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_ROOT/DistributionAssets/SOURCE CODE - Kistulentz.txt" "$PAYLOAD_ROOT/SOURCE CODE - Kistulentz.txt"
if [[ -f "$RELEASE_NOTES_PATH" ]]; then
    cp "$RELEASE_NOTES_PATH" "$PAYLOAD_ROOT/${RELEASE_NOTES_PATH:t}"
fi
ln -s /Applications "$PAYLOAD_ROOT/Applications"

rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH" "$SBOM_PATH"

"$PROJECT_ROOT/scripts/generate-sbom.sh" "$PAYLOAD_ROOT/$SBOM_NAME" >/dev/null
cp "$PAYLOAD_ROOT/$SBOM_NAME" "$SBOM_PATH"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PAYLOAD_ROOT" "$ZIP_PATH"
hdiutil create \
    -quiet \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$PAYLOAD_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
    # The disk image is its own distribution artifact, so it is signed, notarized, and stapled too.
    codesign --force --timestamp --sign "$KISTULENTZ_SIGN_IDENTITY" "$DMG_PATH"
    notarize "$DMG_PATH"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

cd "$RELEASE_ROOT"
shasum -a 256 "${ZIP_PATH:t}" "${DMG_PATH:t}" "${SBOM_PATH:t}" > "${CHECKSUM_PATH:t}"

print "$ZIP_PATH"
print "$DMG_PATH"
print "$CHECKSUM_PATH"
print "$SBOM_PATH"

#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
DIST_ROOT="$PROJECT_ROOT/dist"
RELEASE_ROOT="$DIST_ROOT/releases"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/scripts/Info.plist")"
APP_NAME="Kistuletz"
RELEASE_NAME="$APP_NAME-$VERSION-macOS-universal"
APP_PATH="$DIST_ROOT/$APP_NAME.app"
ZIP_PATH="$RELEASE_ROOT/$RELEASE_NAME.zip"
DMG_PATH="$RELEASE_ROOT/$RELEASE_NAME.dmg"
CHECKSUM_PATH="$RELEASE_ROOT/SHA256SUMS.txt"
STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/kistuletz-release.XXXXXX")"
PAYLOAD_ROOT="$STAGING_ROOT/$APP_NAME $VERSION"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

"$PROJECT_ROOT/scripts/build-app.sh"

mkdir -p "$RELEASE_ROOT" "$PAYLOAD_ROOT"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/$APP_NAME.app"
cp "$PROJECT_ROOT/DistributionAssets/FIRST OPEN - Kistuletz.txt" "$PAYLOAD_ROOT/FIRST OPEN - Kistuletz.txt"
ln -s /Applications "$PAYLOAD_ROOT/Applications"

rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$PAYLOAD_ROOT" "$ZIP_PATH"
hdiutil create \
    -quiet \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$PAYLOAD_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

cd "$RELEASE_ROOT"
shasum -a 256 "${ZIP_PATH:t}" "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}"

print "$ZIP_PATH"
print "$DMG_PATH"
print "$CHECKSUM_PATH"

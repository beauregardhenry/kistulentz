#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PACK_VERSION="${1:-1.0.0}"
PACK_ROOT="${2:-$PROJECT_ROOT/dist/language-packs}"
RELEASE_TAG="language-pack-en-v1"
CATALOG="$PACK_ROOT/catalog.json"

catalog_entry() {
    local architecture="$1"
    local archive="$PACK_ROOT/Kistulentz-English-Language-Pack-$PACK_VERSION-$architecture.zip"
    if [[ ! -f "$archive" ]]; then
        print -u2 "Missing language pack: $archive"
        exit 1
    fi
    local download_bytes="$(stat -f %z "$archive")"
    local sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
    local manifest="$(mktemp)"
    unzip -p "$archive" 'English/manifest.json' > "$manifest"
    local manifest_architecture="$(/usr/bin/plutil -extract architecture raw -o - "$manifest")"
    local manifest_version="$(/usr/bin/plutil -extract version raw -o - "$manifest")"
    local installed_bytes="$(/usr/bin/plutil -extract installedBytes raw -o - "$manifest")"
    rm -f "$manifest"
    if [[ "$manifest_architecture" != "$architecture" || "$manifest_version" != "$PACK_VERSION" ]]; then
        print -u2 "The manifest inside ${archive:t} does not match its catalog entry."
        exit 1
    fi
    print -r -- "    {\"architecture\":\"$architecture\",\"version\":\"$PACK_VERSION\",\"downloadURL\":\"https://github.com/beauregardhenry/kistulentz/releases/download/$RELEASE_TAG/${archive:t}\",\"sha256\":\"$sha256\",\"downloadBytes\":$download_bytes,\"installedBytes\":$installed_bytes}"
}

mkdir -p "$PACK_ROOT"
ARM_ENTRY="$(catalog_entry arm64)"
INTEL_ENTRY="$(catalog_entry x86_64)"
{
    print '{'
    print '  "schemaVersion": 1,'
    print '  "packs": ['
    print "$ARM_ENTRY,"
    print "$INTEL_ENTRY"
    print '  ]'
    print '}'
} > "$CATALOG"

/usr/bin/plutil -lint "$CATALOG" >/dev/null
print "$CATALOG"

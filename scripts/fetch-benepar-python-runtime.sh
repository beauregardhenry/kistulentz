#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
ARCHITECTURE="${1:-}"
OUTPUT_ROOT="${2:-$PROJECT_ROOT/.build/benepar-runtimes}"
RUNTIME_RELEASE="20260825"
PYTHON_VERSION="3.10.21"

if [[ "$ARCHITECTURE" != "arm64" && "$ARCHITECTURE" != "x86_64" ]]; then
    print -u2 "Usage: $0 arm64|x86_64 [/output/directory]"
    exit 2
fi

case "$ARCHITECTURE" in
    arm64)
        TARGET="aarch64-apple-darwin"
        EXPECTED_SHA256="7fedf2035ce497b0ce01643cc5e8ed2aabfb8cfa730440e97af0330b56ce0608"
        ;;
    x86_64)
        TARGET="x86_64-apple-darwin"
        EXPECTED_SHA256="a5bb20b27657eec91859713b2dd3cac9290706ad5db07c7dd41569e87bb36b78"
        ;;
esac

ASSET="cpython-$PYTHON_VERSION+$RUNTIME_RELEASE-$TARGET-install_only.tar.gz"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/$RUNTIME_RELEASE/${ASSET/+/%2B}"
RUNTIME_ROOT="$OUTPUT_ROOT/$ARCHITECTURE"

mkdir -p "$OUTPUT_ROOT"
STAGING_ROOT="$(mktemp -d "$OUTPUT_ROOT/.runtime.XXXXXX")"
ARCHIVE="$STAGING_ROOT/$ASSET"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    print -u2 "The standalone Python archive did not match its pinned SHA-256 checksum."
    exit 1
fi

tar -xzf "$ARCHIVE" -C "$STAGING_ROOT"
if [[ ! -x "$STAGING_ROOT/python/bin/python3" ]]; then
    print -u2 "The standalone Python archive has an unexpected layout."
    exit 1
fi

RUNTIME_ARCH="$(file "$STAGING_ROOT/python/bin/python3")"
if [[ "$RUNTIME_ARCH" != *"$ARCHITECTURE"* && "$RUNTIME_ARCH" != *"universal binary"* ]]; then
    print -u2 "The downloaded Python runtime does not contain $ARCHITECTURE."
    exit 1
fi

rm -rf "$RUNTIME_ROOT"
mv "$STAGING_ROOT/python" "$RUNTIME_ROOT"
print "$RUNTIME_ROOT"

#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build"
OUTPUT_ROOT="$PROJECT_ROOT/dist/language-packs"
RUNTIME_SOURCE="${1:-}"
ARCHITECTURE="${2:-}"
PACK_VERSION="${3:-1.0.0}"

if [[ -z "$RUNTIME_SOURCE" || -z "$ARCHITECTURE" ]]; then
    print -u2 "Usage: $0 /path/to/relocatable-python-runtime arm64|x86_64 [pack-version]"
    exit 2
fi

if [[ "$ARCHITECTURE" != "arm64" && "$ARCHITECTURE" != "x86_64" ]]; then
    print -u2 "Architecture must be arm64 or x86_64."
    exit 2
fi

if [[ ! -x "$RUNTIME_SOURCE/bin/python3" ]]; then
    print -u2 "The runtime must contain an executable bin/python3."
    exit 2
fi

RUNTIME_ARCH="$(file "$RUNTIME_SOURCE/bin/python3")"
if [[ "$RUNTIME_ARCH" != *"$ARCHITECTURE"* && "$RUNTIME_ARCH" != *"universal binary"* ]]; then
    print -u2 "The supplied Python runtime does not contain $ARCHITECTURE."
    exit 2
fi

mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT"
STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/kistulentz-benepar-pack.XXXXXX")"
PACK_ROOT="$STAGING_ROOT/English"
PYTHON_ROOT="$PACK_ROOT/python"
PYTHON="$PYTHON_ROOT/bin/python3"
ARCHIVE="$OUTPUT_ROOT/Kistulentz-English-Language-Pack-$PACK_VERSION-$ARCHITECTURE.zip"
MODEL_ARCHIVE="$STAGING_ROOT/benepar_en3.zip"
MODEL_URL="https://github.com/nikitakit/self-attentive-parser/releases/download/models/benepar_en3.zip"
MODEL_SHA256="de97297ec17b92f7a40ef2e23fd1b4b8baed02eb8bee3d09b25ac6166ae17996"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

mkdir -p "$PACK_ROOT" "$PACK_ROOT/nltk_data" "$PACK_ROOT/licenses"
ditto --noqtn "$RUNTIME_SOURCE" "$PYTHON_ROOT"

"$PYTHON" -m pip install \
    --disable-pip-version-check \
    --no-cache-dir \
    --no-deps \
    --requirement "$PROJECT_ROOT/LanguagePacks/Benepar/requirements-lock.txt"

curl --fail --location --retry 3 --output "$MODEL_ARCHIVE" "$MODEL_URL"
ACTUAL_MODEL_SHA256="$(shasum -a 256 "$MODEL_ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_MODEL_SHA256" != "$MODEL_SHA256" ]]; then
    print -u2 "The Benepar English model did not match its pinned SHA-256 checksum."
    exit 1
fi
mkdir -p "$PACK_ROOT/nltk_data/models"
unzip -q "$MODEL_ARCHIVE" -d "$PACK_ROOT/nltk_data/models"

cp "$PROJECT_ROOT/LanguagePacks/Benepar/NOTICE.md" "$PACK_ROOT/NOTICE.md"
cp "$PROJECT_ROOT/LanguagePacks/Benepar/requirements-lock.txt" "$PACK_ROOT/requirements-lock.txt"

cat > "$PACK_ROOT/licenses/README.md" <<'EOF'
# Included software licenses

The standalone Python runtime retains its Python and other license files under `python/`. Installed Python packages retain their package metadata and distributed license files under `python/lib/python3.10/site-packages/`. `Benepar-Apache-2.0.txt` is a copy of the Apache License 2.0 under which Benepar is distributed. See `../NOTICE.md` for attribution and upstream links.
EOF
cp "$PYTHON_ROOT/lib/python3.10/site-packages/packaging-26.3.dist-info/licenses/LICENSE.APACHE" \
    "$PACK_ROOT/licenses/Benepar-Apache-2.0.txt"

find "$PYTHON_ROOT" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$PYTHON_ROOT" -type f -name '*.pyc' -delete

INSTALLED_BYTES="$(( $(du -sk "$PACK_ROOT" | awk '{print $1}') * 1024 ))"
cat > "$PACK_ROOT/manifest.json" <<EOF
{
  "schemaVersion": 1,
  "identifier": "english-benepar",
  "version": "$PACK_VERSION",
  "architecture": "$ARCHITECTURE",
  "pythonRelativePath": "python/bin/python3",
  "modelRelativePath": "nltk_data/models/benepar_en3",
  "installedBytes": $INSTALLED_BYTES
}
EOF

TEST_REQUEST='{"id":"pack-test","command":"analyze","text":"The final report was completed by the team.","maximumSentences":4,"includeIssues":true}'
TEST_RESPONSE="$(print -r -- "$TEST_REQUEST" | \
    KISTULENTZ_BENEPAR_MODEL="$PACK_ROOT/nltk_data/models/benepar_en3" \
    NLTK_DATA="$PACK_ROOT/nltk_data" \
    HF_HOME="$PACK_ROOT/cache" \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    PYTHONNOUSERSITE=1 \
    "$PYTHON" "$PROJECT_ROOT/LanguagePacks/Benepar/benepar_worker.py")"
if [[ "$TEST_RESPONSE" != *'"ok":true'* || "$TEST_RESPONSE" != *'"passiveVoice"'* ]]; then
    print -u2 "The packaged Benepar worker failed its offline validation."
    exit 1
fi

rm -f "$ARCHIVE"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$PACK_ROOT" "$ARCHIVE"

ARCHIVE_BYTES="$(stat -f %z "$ARCHIVE")"
ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

print "$ARCHIVE"
print "architecture=$ARCHITECTURE"
print "version=$PACK_VERSION"
print "downloadBytes=$ARCHIVE_BYTES"
print "installedBytes=$INSTALLED_BYTES"
print "sha256=$ARCHIVE_SHA256"

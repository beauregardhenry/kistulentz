#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/scripts/Info.plist")"
OUTPUT_PATH="${1:-$PROJECT_ROOT/dist/releases/Kistulentz-$VERSION.spdx.json}"
COMMIT="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || print unknown)"
CREATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "${OUTPUT_PATH:h}"
cat > "$OUTPUT_PATH" <<EOF
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "Kistulentz-$VERSION",
  "documentNamespace": "https://github.com/beauregardhenry/kistulentz/sbom/Kistulentz-$VERSION-$COMMIT",
  "creationInfo": {
    "created": "$CREATED",
    "creators": [
      "Person: Beau Henry",
      "Tool: Kistulentz-generate-sbom"
    ]
  },
  "packages": [
    {
      "name": "Kistulentz",
      "SPDXID": "SPDXRef-Package-Kistulentz",
      "versionInfo": "$VERSION",
      "supplier": "Person: Beau Henry",
      "downloadLocation": "https://github.com/beauregardhenry/kistulentz/tree/v$VERSION",
      "filesAnalyzed": false,
      "licenseConcluded": "GPL-3.0-or-later",
      "licenseDeclared": "GPL-3.0-or-later",
      "copyrightText": "Copyright 2026 Beau Henry",
      "externalRefs": [
        {
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:github/beauregardhenry/kistulentz@$VERSION"
        }
      ]
    }
  ],
  "relationships": [
    {
      "spdxElementId": "SPDXRef-DOCUMENT",
      "relationshipType": "DESCRIBES",
      "relatedSpdxElement": "SPDXRef-Package-Kistulentz"
    }
  ]
}
EOF

plutil -convert json -o /dev/null "$OUTPUT_PATH"
print "$OUTPUT_PATH"

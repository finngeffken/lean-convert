#!/bin/bash
# Publishes the packaged zip as a GitHub release of this repository.
# Run notarize.sh first; an unnotarized build is refused unless
# ALLOW_UNNOTARIZED=1, because recipients would hit the Gatekeeper wall.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Lean Convert.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
ZIP="dist/Lean-Convert-$VERSION.zip"

[ -f "$ZIP" ] || { echo "  ! $ZIP fehlt — erst ./notarize.sh (oder ./package.sh)." >&2; exit 1; }

if ! xcrun stapler validate "$APP" >/dev/null 2>&1 && [ "${ALLOW_UNNOTARIZED:-0}" != 1 ]; then
    echo "  ! Nicht notarisiert. Erst ./notarize.sh, oder ALLOW_UNNOTARIZED=1 ./release.sh" >&2
    exit 1
fi

gh release create "v$VERSION" "$ZIP" \
    --title "Lean Convert $VERSION" \
    --notes "Herunterladen, \`Lean Convert.app\` nach „Programme“ ziehen, starten. Nur Macs mit Apple-Chip."

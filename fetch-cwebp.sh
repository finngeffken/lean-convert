#!/bin/bash
# Fetches the cwebp binary that ImageDrop bundles for WebP export.
#
# Source is Google's official libwebp release. Only cwebp is kept; the rest of
# the archive (dwebp, gif2webp, img2webp, …) is not needed.
#
# Without this binary the app still converts HEIC, JPEG, PNG and AVIF and
# resizes — only WebP export is unavailable, and the UI says so.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.6.0"
ARCH="arm64"
NAME="libwebp-${VERSION}-mac-${ARCH}"
URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/${NAME}.tar.gz"

if [ -x Resources/cwebp ]; then
    echo "Resources/cwebp ist schon da ($(./Resources/cwebp -version))."
    exit 0
fi

WORK="$(mktemp -d)"
echo "→ Lade libwebp ${VERSION} (${ARCH})…"
curl -fsSL -o "$WORK/libwebp.tar.gz" "$URL"

echo "→ Entpacke cwebp…"
tar -xzf "$WORK/libwebp.tar.gz" -C "$WORK" "${NAME}/bin/cwebp"

mkdir -p Resources
cp -f "$WORK/${NAME}/bin/cwebp" Resources/cwebp
chmod +x Resources/cwebp

echo "Fertig: Resources/cwebp ($(./Resources/cwebp -version))"

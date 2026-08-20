#!/bin/bash
# Fetches the ffmpeg binary that Lean Convert bundles for video encoding.
#
# ffmpeg has no official macOS builds. This pulls an arm64 build from
# osxexperts.net — deliberately a separate, visible step rather than something
# the app ships unnoticed.
#
# Without this binary the image side works exactly as before; only the video
# mode is unavailable, and the app says so.
set -euo pipefail
cd "$(dirname "$0")"

URL="https://www.osxexperts.net/ffmpeg80arm.zip"

if [ -x Resources/ffmpeg ]; then
    echo "Resources/ffmpeg ist schon da ($(./Resources/ffmpeg -version 2>/dev/null | head -1))."
    exit 0
fi

WORK="$(mktemp -d)"
echo "→ Lade ffmpeg (arm64)…"
curl -fsSL -o "$WORK/ffmpeg.zip" "$URL"

echo "→ Entpacke…"
unzip -q -o "$WORK/ffmpeg.zip" -d "$WORK"

BIN="$(find "$WORK" -type f -name ffmpeg -perm +111 | head -1)"
if [ -z "$BIN" ]; then
    BIN="$(find "$WORK" -type f -name ffmpeg | head -1)"
fi
if [ -z "$BIN" ]; then
    echo "  ! Im Archiv war kein ffmpeg zu finden." >&2
    exit 1
fi

mkdir -p Resources
cp -f "$BIN" Resources/ffmpeg
chmod +x Resources/ffmpeg

ARCH="$(file -b Resources/ffmpeg | grep -o 'arm64\|x86_64' | head -1)"
SIZE="$(( $(stat -f%z Resources/ffmpeg) / 1048576 ))"
echo "Fertig: Resources/ffmpeg — ${ARCH:-unbekannte Architektur}, ${SIZE} MB"
if [ "$ARCH" != "arm64" ]; then
    echo "  ! Achtung: kein arm64-Build. Läuft unter Rosetta und damit deutlich langsamer." >&2
fi

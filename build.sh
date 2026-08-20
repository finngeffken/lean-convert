#!/bin/bash
# Builds dist/Lean Convert.app.
#
# There is no Xcode project: SwiftUI lives in the SDK, so swiftc via SwiftPM
# compiles it fine and the .app bundle is assembled here by hand.
#
# Note: this script never deletes anything. Files are copied over in place, so
# a rebuild overwrites the binary and the plist and leaves everything else
# alone.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Lean Convert.app"

echo "→ Kompiliere (release)…"
swift build -c release --product LeanConvert

echo "→ Baue Bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f .build/release/LeanConvert "$APP/Contents/MacOS/LeanConvert"
cp -f Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/cwebp ]; then
    cp -f Resources/cwebp "$APP/Contents/Resources/cwebp"
    chmod +x "$APP/Contents/Resources/cwebp"
else
    echo "  ! Resources/cwebp fehlt — die App läuft, aber ohne WebP-Export."
fi

if [ -f Resources/ffmpeg ]; then
    cp -f Resources/ffmpeg "$APP/Contents/Resources/ffmpeg"
    chmod +x "$APP/Contents/Resources/ffmpeg"
else
    echo "  ! Resources/ffmpeg fehlt — der Video-Modus ist nicht verfügbar."
fi

if [ -f Resources/AppIcon.icns ]; then
    cp -f Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  ! Resources/AppIcon.icns fehlt — die App zeigt das Standard-Icon."
fi

chmod +x "$APP/Contents/MacOS/LeanConvert"

echo "→ Signiere (ad-hoc)…"
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP"

echo ""
echo "Fertig: $APP"
echo "Erster Start: Rechtsklick → Öffnen (einmalig, wegen Ad-hoc-Signatur)."

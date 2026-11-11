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

# Copying into the existing bundle never changes the bundle folder's own
# date, and macOS caches app icons keyed on it — so a new icon stayed
# invisible. Touch it and re-register so Finder and Dock pick up changes.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

# Signing. With a "Developer ID Application" certificate in the keychain the
# bundle is signed for notarization: hardened runtime and a secure timestamp
# on every executable. Without one it falls back to an ad-hoc signature,
# which runs locally but is quarantined on other Macs.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)}"

if [ -n "$IDENTITY" ]; then
    echo "→ Signiere mit: $IDENTITY"
    SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp)
else
    echo "→ Signiere ad-hoc (kein Developer-ID-Zertifikat gefunden)"
    SIGN=(codesign --force --sign - --options runtime)
fi

# Nested executables first, the bundle last: signing the bundle seals what
# is inside it, and notarization rejects any executable without its own
# hardened-runtime signature.
for helper in "$APP/Contents/Resources/cwebp" "$APP/Contents/Resources/ffmpeg"; do
    [ -f "$helper" ] && "${SIGN[@]}" "$helper"
done
"${SIGN[@]}" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo ""
echo "Fertig: $APP"
[ -n "$IDENTITY" ] || echo "Erster Start: Rechtsklick → Öffnen (einmalig, wegen Ad-hoc-Signatur)."

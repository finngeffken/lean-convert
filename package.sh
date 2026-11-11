#!/bin/bash
# Packs dist/Lean Convert.app into a zip that can be shared with the team,
# plus the one-time instructions recipients need.
#
# The app is only ad-hoc signed (no Developer ID), so macOS quarantines it on
# the recipient's machine. The instructions say how to lift that. Apple
# Silicon only: every bundled binary is arm64.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Lean Convert.app"
[ -d "$APP" ] || ./build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/Lean-Convert-$VERSION"
mkdir -p "$OUT"

# ditto keeps the code signature and extended attributes intact; zip does not.
ditto "$APP" "$OUT/Lean Convert.app"
cat > "$OUT/Installation.txt" <<'TXT'
Lean Convert — Installation (einmalig)

Voraussetzung: Mac mit Apple-Chip (M1 oder neuer). Auf Intel-Macs läuft die App nicht.

1. „Lean Convert.app" in den Ordner „Programme" ziehen.
2. Terminal öffnen und diese Zeile einfügen:

   xattr -dr com.apple.quarantine "/Applications/Lean Convert.app"

3. App normal per Doppelklick starten.

Warum Schritt 2? Die App ist nicht bei Apple notarisiert. Ohne diesen Befehl meldet
macOS „…ist beschädigt und kann nicht geöffnet werden" — die Datei ist nicht kaputt,
macOS kennt nur den Absender nicht. Bei jeder neuen Version einmal wiederholen.
TXT

ZIP="dist/Lean-Convert-$VERSION.zip"
ditto -c -k --keepParent "$OUT" "$ZIP"
echo "Fertig: $ZIP ($(du -h "$ZIP" | cut -f1))"

#!/bin/bash
# Packs dist/Lean Convert.app into a zip that can be shared with the team,
# plus the one-time instructions recipients need.
#
# The instructions depend on whether the app carries a stapled notarization
# ticket (see notarize.sh): notarized apps just open, ad-hoc signed ones are
# quarantined and need one terminal command. Apple Silicon only.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Lean Convert.app"
[ -d "$APP" ] || ./build.sh
# A previous run's folder would otherwise keep stale files.
rm -rf "dist/Lean-Convert-"*/

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/Lean-Convert-$VERSION"
mkdir -p "$OUT"

# ditto keeps the code signature and extended attributes intact; zip does not.
ditto "$APP" "$OUT/Lean Convert.app"
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    cat > "$OUT/Installation.txt" <<'TXT'
Lean Convert — Installation

Voraussetzung: Mac mit Apple-Chip (M1 oder neuer).

1. „Lean Convert.app" in den Ordner „Programme" ziehen.
2. Per Doppelklick starten.

Die App ist von Apple notarisiert, es erscheint keine Warnung.
TXT
else
    cat > "$OUT/Installation.txt" <<'TXT'
Lean Convert — Installation (einmalig)

Voraussetzung: Mac mit Apple-Chip (M1 oder neuer). Auf Intel-Macs läuft die App nicht.

1. „Lean Convert.app" in den Ordner „Programme" ziehen.
2. Terminal öffnen und diese Zeile einfügen:

   xattr -dr com.apple.quarantine "/Applications/Lean Convert.app"

3. App normal per Doppelklick starten.

Warum Schritt 2? Diese Version ist nicht bei Apple notarisiert. Ohne den Befehl meldet
macOS „…ist beschädigt und kann nicht geöffnet werden" — die Datei ist nicht kaputt,
macOS kennt nur den Absender nicht. Bei jeder neuen Version einmal wiederholen.
TXT
fi

ZIP="dist/Lean-Convert-$VERSION.zip"
ditto -c -k --keepParent "$OUT" "$ZIP"
echo "Fertig: $ZIP ($(du -h "$ZIP" | cut -f1))"

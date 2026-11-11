#!/bin/bash
# Builds, signs with Developer ID, notarizes with Apple, staples the ticket
# and packages the result. Recipients then just double-click — no terminal,
# no Gatekeeper warning.
#
# One-time setup (only the account holder can do this):
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + ).
#   2. Notarization credentials stored under the profile name below:
#      xcrun notarytool store-credentials LeanConvert \
#          --apple-id <apple-id> --team-id <TEAMID>
#      (asks for an app-specific password from account.apple.com)
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-LeanConvert}"
APP="dist/Lean Convert.app"

./build.sh

if ! codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "  ! Kein Developer-ID-Zertifikat im Schlüsselbund — Notarisierung nicht möglich." >&2
    echo "    Siehe Kopf dieses Skripts für die Einrichtung." >&2
    exit 1
fi

WORK="$(mktemp -d)"
ditto -c -k --keepParent "$APP" "$WORK/submit.zip"

echo "→ Sende an Apple (dauert meist 1–5 Minuten)…"
xcrun notarytool submit "$WORK/submit.zip" --keychain-profile "$PROFILE" \
    --wait --output-format json > "$WORK/result.json"

STATUS="$(plutil -extract status raw "$WORK/result.json" 2>/dev/null || echo unbekannt)"
ID="$(plutil -extract id raw "$WORK/result.json" 2>/dev/null || echo "")"
if [ "$STATUS" != "Accepted" ]; then
    echo "  ! Apple hat abgelehnt: $STATUS" >&2
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
    exit 1
fi

echo "→ Ticket anheften…"
xcrun stapler staple "$APP"

echo "→ Gatekeeper-Prüfung…"
spctl --assess --type execute --verbose=2 "$APP"

./package.sh

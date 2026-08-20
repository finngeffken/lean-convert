#!/bin/bash
# Builds Resources/AppIcon.icns for Lean Convert from a source image (SVG or PNG).
#
#   ./make-icon.sh ~/Downloads/Lean-Convert.svg
#
# The artwork is inset to 82% of the canvas with transparent margin. macOS —
# unlike iOS — does not mask or pad app icons, so a full-bleed square would sit
# noticeably larger in the Dock than every icon beside it.
set -euo pipefail
cd "$(dirname "$0")"

SOURCE="${1:-}"
if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
    echo "Aufruf: ./make-icon.sh <Bilddatei>" >&2
    exit 1
fi

INSET="${ICON_INSET:-0.82}"
WORK="$(mktemp -d)"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"

cat > "$WORK/rasterize.swift" <<'SWIFT'
import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let side = Int(CommandLine.arguments[2])!
let inset = Double(CommandLine.arguments[3])!
let output = URL(fileURLWithPath: CommandLine.arguments[4])

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("Bild nicht lesbar: \(source.path)\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let drawn = Double(side) * inset
let offset = (Double(side) - drawn) / 2
image.draw(
    in: NSRect(x: offset, y: offset, width: drawn, height: drawn),
    from: .zero, operation: .sourceOver, fraction: 1
)

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
SWIFT

echo "→ Rastere ${SOURCE##*/} …"
render() {  # render <pixels> <filename>
    swift "$WORK/rasterize.swift" "$SOURCE" "$1" "$INSET" "$SET/$2"
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

echo "→ Baue .icns …"
mkdir -p Resources
iconutil --convert icns "$SET" --output Resources/AppIcon.icns

echo "Fertig: Resources/AppIcon.icns ($(( $(stat -f%z Resources/AppIcon.icns) / 1024 )) KB)"

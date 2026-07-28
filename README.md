# ImageDrop

Lokale macOS-App zum Konvertieren und Verkleinern von Bildern. Fenster mit Drop-Zone, kein Upload, keine Limits, keine Wartezeit.

- **HEIC → JPEG/PNG** (iPhone-Fotos)
- **PNG ↔ JPEG**
- **→ WebP / AVIF** mit Qualitätsregler
- **Verkleinern** auf eine maximale Kantenlänge, mit allem oben kombinierbar

## Bauen

```bash
./fetch-cwebp.sh   # einmalig: 2,6-MB-Binary für WebP-Export
./build.sh         # erzeugt dist/ImageDrop.app
```

Beim allerersten Start einmal **Rechtsklick → Öffnen** — die App ist nur ad-hoc signiert, eine Notarisierung würde einen Apple-Developer-Account brauchen. Danach startet sie normal.

`fetch-cwebp.sh` ist optional. Ohne das Binary läuft alles außer WebP-Export, und die App sagt das im Fenster.

## Tests

```bash
./test.sh
```

40 Tests gegen echte `sips`- und `cwebp`-Aufrufe, mit zur Laufzeit erzeugten Fixture-Bildern.

## Verhalten

| Regel | |
|---|---|
| Ausgabe | Neben dem Original, gleicher Name, neue Endung |
| Kollision | **Nie überschreiben** — `bild.webp` belegt → `bild-1.webp` |
| Metadaten | Bleiben immer erhalten (EXIF überlebt auch WebP) |
| Verkleinern | Nur abwärts; ein 800px-Bild wird von „Max. Kante 2000" nicht angefasst |
| Fehler | Immer auf eine Datei begrenzt — 1 kaputtes Bild von 50 kostet dieses eine |
| Nicht-Bilder | Werden schon in der Drop-Zone abgewiesen |

Die App löscht und überschreibt grundsätzlich keine Datei. Im gesamten Projekt gibt es keinen einzigen Löschaufruf.

## Wie es funktioniert

Zwei Schichten, strikt getrennt:

- **`Sources/ConversionKit/`** — die Engine. Kennt kein SwiftUI, komplett ohne UI testbar.
- **`Sources/ImageDrop/`** — die SwiftUI-App. Kennt kein `sips` und kein `cwebp`.

Die Werkzeugwahl sitzt an genau einer Stelle ([`ConversionEngine`](Sources/ConversionKit/ConversionEngine.swift)): WebP → `cwebp`, alles andere → das in macOS eingebaute `sips`. **ffmpeg und ImageMagick werden nicht gebraucht** — `sips` schreibt JPEG, PNG, HEIC und AVIF nativ, und die einzige Lücke (WebP) füllt ein 2,6-MB-Binary, das die App selbst mitbringt. Es wird nichts am System installiert.

Details und Begründungen: [docs/superpowers/specs/2026-07-28-imagedrop-design.md](docs/superpowers/specs/2026-07-28-imagedrop-design.md)

## Nicht enthalten

Animierte GIF/WebP-Konvertierung, PDF- und SVG-Input, Wasserzeichen, Retina-Mehrfachgrößen. Alles nachrüstbar, ohne die Architektur anzufassen.

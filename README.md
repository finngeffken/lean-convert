# ImageDrop

Lokale macOS-App zum Konvertieren und Verkleinern von Bildern. Fenster mit Drop-Zone, kein Upload, keine Limits, keine Wartezeit.

- **HEIC → JPEG/PNG** (iPhone-Fotos)
- **PNG ↔ JPEG**
- **→ WebP / AVIF** mit Qualitätsregler
- **Verkleinern** auf eine maximale Kantenlänge, mit allem oben kombinierbar
- **Umbenennen** per Muster, mit Live-Vorschau
- **Zielordner** frei wählbar, Standard ist neben dem Original

## Ablauf

Bilder reinziehen → sie landen in einer Warteschlange → Einstellungen setzen → **Konvertieren**. Nichts passiert, bevor du den Knopf drückst (oder Enter). Die Warteschlange bleibt danach stehen, du kannst dieselben Dateien also direkt nochmal in ein anderes Format konvertieren.

## Umbenennen

Feld leer lassen = Originalnamen behalten. Ansonsten Platzhalter:

| Platzhalter | Bedeutung |
|---|---|
| `{name}` | Originalname ohne Endung |
| `{n}` | Nummer: 1, 2, 3 … |
| `{nn}` | Nummer mit Nullen: 01, 02 … |
| `{nnn}` | 001, 002 … |

Beispiele bei einem Ordner voller UUID-Dateinamen:

| Muster | Ergebnis |
|---|---|
| `AM-Kalender-{nn}` | `AM-Kalender-01.webp`, `AM-Kalender-02.webp` … |
| `{name}-web` | `a3e32b79-01b1-web.webp` |
| `2027_{nnn}` | `2027_001.webp` … |

Die Nummerierung folgt der Reihenfolge in der Warteschlange, nicht der Reihenfolge, in der die Konvertierungen fertig werden. Ein Tippfehler im Platzhalter (`{nmae}`) bleibt sichtbar stehen, statt stillschweigend zu verschwinden.

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

64 Tests gegen echte `sips`- und `cwebp`-Aufrufe, mit zur Laufzeit erzeugten Fixture-Bildern.

## Verhalten

| Regel | |
|---|---|
| Ausgabe | Standard: neben dem Original, gleicher Name, neue Endung |
| Kollision | **Nie überschreiben** — `bild.webp` belegt → `bild-1.webp` |
| Namenskollision im Batch | Auch zwei Dateien, die auf denselben Namen laufen, bekommen getrennte Pfade — die Reservierung ist gesperrt, nicht bloß ein Existenz-Check |
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

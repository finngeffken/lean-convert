# Lean Convert

Lokale macOS-App zum Konvertieren und Verkleinern von Bildern und Videos. Fenster mit Drop-Zone, kein Upload, keine Limits, keine Wartezeit.

- **HEIC → JPEG/PNG** (iPhone-Fotos)
- **PNG ↔ JPEG**
- **→ WebP / AVIF** mit Qualitätsregler
- **Verkleinern** auf eine maximale Kantenlänge, mit allem oben kombinierbar
- **Umbenennen** per Muster, mit Live-Vorschau
- **Zielordner** frei wählbar, Standard ist neben dem Original
- **Video komprimieren** — H.264, HEVC, VP9 (WebM) und AV1, mit CRF-Regler

## Zwei Modi

Oben umschaltbar: **Bilder | Video**. Getrennte Warteschlangen, getrennte Einstellungen — ein Wechsel verwirft nichts. Dateien, die aufs Dock-Icon fallen, werden nach Typ einsortiert und der Modus springt mit.

Umbenennen, Zielordner und „nie überschreiben" gelten in beiden Modi gleich.

## Video

| Codec | Container | Wofür |
|---|---|---|
| H.264 | mp4 | Läuft überall, größte Dateien |
| HEVC | mp4 | Deutlich kleiner, Safari und moderne Browser |
| VP9 | webm | Für Browser ohne HEVC |
| AV1 | mp4 | Kleinste Dateien, langsamstes Kodieren |

Der Qualitätsregler ist hier **CRF: kleiner = besser** — genau umgekehrt zum Bildregler. Die App schreibt das unter den Regler, weil die Verwechslung sonst garantiert ist.

Gemessen an einem 140-MB-Clip (3416×2146, 20 s), Ziel 1080p: HEVC 1 MB in 10 s, H.264 4 MB in 6 s, AV1 3 MB in 15 s, VP9 4 MB in 29 s.

Video läuft **eine Datei zu einer Zeit** — ein ffmpeg-Encode lastet schon alle Kerne aus. Während eines Laufs gibt es einen **Abbrechen**-Knopf, und ein abgebrochener Encode hinterlässt keine halbe Datei: kodiert wird in eine temporäre Datei, die erst bei Erfolg umbenannt wird.

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
./fetch-ffmpeg.sh  # einmalig: 49-MB-Binary für den Video-Modus
./build.sh         # erzeugt dist/Lean Convert.app
```

Beim allerersten Start einmal **Rechtsklick → Öffnen** — die App ist nur ad-hoc signiert, eine Notarisierung würde einen Apple-Developer-Account brauchen. Danach startet sie normal.

Beide Fetch-Skripte sind optional und laden Binaries von Dritten — cwebp direkt von Google, ffmpeg von einer Community-Quelle, weil es für macOS keine offiziellen Builds gibt. Deshalb sind es bewusst separate Schritte und nicht Teil des Bundles im Repository. Ohne cwebp fehlt der WebP-Export, ohne ffmpeg der ganze Video-Modus; die App sagt in beiden Fällen, was fehlt.

Mit ffmpeg wächst das Bundle auf ~53 MB.

## Tests

```bash
./test.sh
```

87 Tests gegen echte `sips`-, `cwebp`- und `ffmpeg`-Aufrufe, mit zur Laufzeit erzeugten Fixtures. Video-Tests überspringen sich ohne ffmpeg, WebP-Tests ohne cwebp.

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

Die App überschreibt grundsätzlich keine Datei. Gelöscht wird genau eine Sorte Datei: die temporäre Datei, in die ein Video-Encode schreibt, wenn dieser abbricht oder fehlschlägt — angelegt Sekunden vorher von der App selbst und nie als Ergebnis gezeigt. Originale und fertige Ausgaben bleiben unangetastet.

## Wie es funktioniert

Zwei Schichten, strikt getrennt:

- **`Sources/ConversionKit/`** — die Engines. Kennen kein SwiftUI, komplett ohne UI testbar.
- **`Sources/LeanConvert/`** — die SwiftUI-App. Kennt keins der Kommandozeilen-Werkzeuge.

`BatchRunner` ist generisch über ein `MediaConverter`-Protokoll: Reihenfolge, Parallelitätsfenster und „ein Fehler kostet nur diese eine Datei" existieren einmal und gelten für Bild und Video.

Die Werkzeugwahl sitzt pro Medienart an genau einer Stelle. [`ConversionEngine`](Sources/ConversionKit/ConversionEngine.swift): WebP → `cwebp`, alles andere → das in macOS eingebaute `sips`. [`VideoEngine`](Sources/ConversionKit/VideoEngine.swift): alles → `ffmpeg`, während Länge und Auflösung von AVFoundation kommen (spart ein zweites 20-MB-Binary für `ffprobe`).

**Für Bilder braucht es kein ffmpeg** — `sips` schreibt JPEG, PNG, HEIC und AVIF nativ, und die einzige Lücke (WebP) füllt ein 2,6-MB-Binary. ffmpeg kommt ausschließlich für Video dazu, weil nur es VP9 und AV1 schreibt. Installiert wird nichts am System; die App bringt ihre Binaries im Bundle mit.

Details und Begründungen: [Bild-Design](docs/superpowers/specs/2026-07-28-leanconvert-design.md) und [Video-Design](docs/superpowers/specs/2026-07-28-video-support-design.md)

## Nicht enthalten

Bild: animierte GIF/WebP-Konvertierung, PDF- und SVG-Input, Wasserzeichen, Retina-Mehrfachgrößen.

Video: Video→GIF, Trimmen, Zwei-Pass, Bitraten-Zielvorgabe („mach das unter 10 MB"), und der Hardware-Encoder-Umschalter — der M5 kodiert H.264/HEVC per VideoToolbox um ein Vielfaches schneller, bei gleicher Dateigröße aber schlechter als x264/x265. Das ist eine eigene Abwägung und bewusst nicht eingebaut.

Alles nachrüstbar, ohne die Architektur anzufassen.

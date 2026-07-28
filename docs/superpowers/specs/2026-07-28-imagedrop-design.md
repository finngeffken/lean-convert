# ImageDrop – Design

**Datum:** 2026-07-28
**Status:** Freigegeben (Design), Implementierung offen

## Ziel

Eine lokale macOS-App mit Fenster und Drop-Zone, die Bilder konvertiert und verkleinert – als Ersatz für Online-Konverter. Kein Upload, keine Wartezeit, keine Werbung, keine Dateigrößen-Limits.

Abgedeckte Konvertierungen:

- HEIC → JPEG oder PNG (iPhone-Fotos brauchbar machen)
- PNG ↔ JPEG
- beliebiges Eingabeformat → WebP oder AVIF (Web-Optimierung mit Qualitätsregler)
- Verkleinern auf eine maximale Kantenlänge, in allen genannten Fällen kombinierbar

## Nicht-Ziele

Bewusst ausgeschlossen, weil nicht gebraucht (YAGNI). Alle drei sind später nachrüstbar, ohne die Architektur zu brechen:

- **Animierte GIF/WebP-Konvertierung.** `cwebp` kann keine Animationen; das bräuchte zusätzlich `gif2webp`/`img2webp`.
- **PDF- und SVG-Input.** Rastern von Vektor-/Dokumentformaten.
- **Wasserzeichen, Mehrfach-Größen (Retina-Sets), Umbenennen beim Export.**

Ebenfalls kein Ziel: eine CLI. Die Architektur hält den Weg dorthin offen (die Engine ist UI-frei), aber gebaut wird sie jetzt nicht.

## Voraussetzungen (auf der Zielmaschine verifiziert am 2026-07-28)

| Werkzeug | Status | Konsequenz |
|---|---|---|
| `sips` | vorhanden (`/usr/bin/sips`) | Trägt JPEG, PNG, HEIC, AVIF, Resize – ohne Installation |
| Swift | 6.3.1, `/usr/bin/swiftc` | SwiftUI baubar |
| Xcode (voll) | **nicht** vorhanden, nur CommandLineTools | Kein Xcode-Projekt, keine Previews; `.app`-Bundle wird per Skript gebaut |
| Homebrew | **nicht** vorhanden | Keine Abhängigkeit darauf; App bringt Binaries selbst mit |
| `ffmpeg` / ImageMagick | nicht vorhanden | **Nicht nötig** – siehe Engine-Entscheidung |

**Engine-Entscheidung:** `sips` schreibt nativ JPEG, PNG, HEIC, AVIF, TIFF, GIF, ICO, PDF. Die einzige Lücke ist **WebP** – `sips` liest es, schreibt es aber nicht. Diese Lücke schließt Googles `cwebp` (~1 MB, offizielles libwebp-Release, der qualitativ beste WebP-Encoder). ffmpeg wäre für genau eine Funktion ein Vielfaches an Abhängigkeiten und ist für Einzelbilder ohnehin das schwächere Werkzeug.

## Architektur

Zwei Schichten, strikt getrennt, als SwiftPM-Paket:

```
ImageDrop/
├── Package.swift
├── Sources/
│   ├── ConversionKit/      ← Engine, UI-frei, testbar
│   └── ImageDropApp/       ← SwiftUI, kennt kein sips/cwebp
├── Tests/ConversionKitTests/
├── Resources/cwebp         ← mitgeliefertes Binary
├── fetch-cwebp.sh          ← holt es einmalig
├── test.sh                 ← führt die Suite aus
└── build.sh                ← baut das .app-Bundle
```

Die UI kennt keine Kommandozeilen-Werkzeuge, die Engine kennt kein SwiftUI. Das Interface dazwischen ist schmal:

```swift
struct ConversionSettings {
    var target: TargetFormat        // .jpeg, .png, .webp, .avif
    var quality: Int                // 1...100
    var maxEdge: Int?               // längere Kante; nil = keine Größenänderung
}

enum ConversionOutcome {
    case success(output: URL, bytesBefore: Int, bytesAfter: Int)
    case failure(input: URL, reason: FailureReason)
}
```

Der Grund für den Schnitt: die Engine ist ohne UI unter Test nehmbar, und eine spätere CLI setzt auf genau dieselbe Engine – ohne Duplikat der Konvertierungslogik.

**SwiftPM als Struktur, nicht als Selbstzweck:** Ein reines `swiftc`-Kommando würde die App auch bauen, aber die Paketstruktur trennt Engine und UI in echte Module — und erzwingt damit, dass die UI die Engine nur über deren öffentliche Schnittstelle benutzt. `build.sh` kompiliert per SwiftPM und legt das `.app`-Bundle drumherum.

## Komponenten

### `ConversionEngine`

Die einzige Stelle, die entscheidet, welches Werkzeug ein Zielformat bedient: WebP → `cwebp`, alles andere → `sips`. Diese Entscheidung ist absichtlich nicht über die UI verteilt – kommt später ein Format oder ein Binary hinzu, ändert sich genau diese Datei.

Konkrete Aufrufe:

- `sips`: ein einziger Aufruf erledigt Format, Qualität und Resize zusammen —
  `sips -s format jpeg -s formatOptions 85 -Z 2000 --out <out> <in>`
- `cwebp`: `cwebp -q 85 -metadata all -resize <W> 0 <in> -o <out>`
  (`0` für die zweite Dimension rechnet seitenverhältnistreu; `-metadata all` ist nötig, weil `cwebp` EXIF sonst **verwirft**)

### `ImageProbe`

Liest vor der Konvertierung Dimensionen und Alpha-Kanal:
`sips -g pixelWidth -g pixelHeight -g hasAlpha <in>`

Notwendig aus zwei Gründen:

1. **`sips -Z` skaliert kleine Bilder hoch.** Ein 800px-Bild mit Max-Kante 2000 würde auf 2000px interpoliert – unerwünscht und verlustbehaftet. Ist die längere Kante bereits ≤ Max-Kante, wird der Resize-Parameter weggelassen.
2. Alpha-Erkennung steuert die HEIC-Vorauswahl (siehe Verhalten).

### `BatchRunner`

Fährt Konvertierungen parallel mit `ProcessInfo.processInfo.activeProcessorCount` gleichzeitigen Prozessen, sammelt `ConversionOutcome`s und meldet Fortschritt an die UI. Begründung für das Limit: die Arbeit ist CPU-gebunden in externen Prozessen; mehr Parallelität als Kerne bringt nichts und macht die Maschine während eines 200-Datei-Batches unbenutzbar.

### `ContentView`

Drop-Zone, Format-Picker, Qualitäts-Slider, Feld für Max-Kante, Ergebnisliste mit eingesparter Größe in Prozent. Annahme von Dateien über zwei Wege:

- **im Fenster** via `.dropDestination(for: URL.self)`
- **auf das Dock-Icon** via `CFBundleDocumentTypes` (`LSItemContentTypes: public.image`) plus `NSApplicationDelegateAdaptor` und `application(_:open:)`

### Mitgeliefertes Binary

`cwebp` liegt im Bundle unter `Contents/Resources/` und wird über `Bundle.main.url(forResource:)` gefunden – nicht über `PATH`. Die App bringt ihre Abhängigkeit selbst mit; es wird nichts am System installiert und nichts kann kaputtgehen.

Herkunft: offizielles libwebp-Release von `downloads.webmproject.org` (arm64-macOS). **Der Download ist ein einmaliger Einrichtungsschritt und wird vor Ausführung mit dem Nutzer abgestimmt.**

## Verhalten

| Regel | Entscheidung |
|---|---|
| Output-Ort | Neben dem Original, gleicher Name, neue Endung |
| Kollision | **Nie überschreiben.** Existiert `bild.webp`, wird `bild-1.webp` geschrieben, dann `-2` usw. |
| Metadaten | Bleiben **immer** erhalten – feste Regel, kein Schalter in der UI (bei `cwebp` explizit via `-metadata all`) |
| Resize | Nur verkleinernd, Seitenverhältnis bleibt, leeres Feld = keine Änderung |
| Einstellungen | Werden in `UserDefaults` gemerkt und beim Start vorbelegt |
| HEIC-Vorauswahl | Mit Alpha → PNG, ohne Alpha → JPEG. Überschreibbar. |
| Nicht unterstützte Eingaben | Ordner, Videos, Archive werden **in der Drop-Zone abgewiesen**, nicht erst als Fehler nach dem Start |

## Fehlerbehandlung

Ein Fehler ist immer auf eine Datei begrenzt: ein kaputtes Bild in einem Batch von 50 lässt die anderen 49 durchlaufen und erscheint als Fehlerzeile mit Grund. Kein Abbruch, kein stiller Verlust.

`FailureReason` deckt ab: nicht lesbar/korrupt, nicht unterstütztes Eingabeformat, Zielordner nicht schreibbar, Binary nicht gefunden, Werkzeug mit Fehlercode beendet (mit `stderr` im Detail).

Grundsatz: **Fehler werden gemeldet, nicht geraten.** Es gibt keinen stillen Fallback auf ein anderes Format oder eine andere Qualität.

## Build & Verteilung

`build.sh` erledigt:

1. `swift build -c release`
2. `.app`-Bundle zusammensetzen: `Contents/MacOS/ImageDrop`, `Contents/Resources/cwebp`, `Info.plist`
3. Ad-hoc-Signatur: `codesign --force --sign - ImageDrop.app`

Kompiliert wird der SwiftUI-`@main`-Typ mit `-parse-as-library` (nötig, sonst erwartet der Compiler ein Top-Level-Skript).

**Kein App Sandbox.** Ohne Entitlements darf die App neben beliebige Originale schreiben – genau das ist gewollt. Eine sandboxed App bräuchte für jeden Zielordner eine Nutzerfreigabe und würde den Zweck des Tools untergraben.

**Gatekeeper:** Ad-hoc-Signatur bedeutet beim allerersten Start einmal Rechtsklick → Öffnen. Danach nie wieder. Für ein privates Werkzeug akzeptabel; eine Notarisierung würde einen Apple-Developer-Account erfordern.

## Tests

`ConversionKit` bekommt Unit-Tests gegen Fixture-Bilder, die zur Laufzeit erzeugt werden (`./test.sh` — siehe Verifikationspunkt 4 zur Framework-Wahl):

- Zielformat stimmt: Ausgabe ist tatsächlich JPEG/PNG/WebP/AVIF (per `sips -g format` geprüft, nicht per Dateiendung)
- Downscale rechnet richtig und hält das Seitenverhältnis
- **Upscale wird verweigert**: Bild kleiner als Max-Kante behält seine Größe
- Kollisions-Benennung erzeugt `-1`, `-2` statt zu überschreiben
- EXIF überlebt den WebP-Weg
- Ein korruptes Bild im Batch liefert `failure` und stoppt die übrigen nicht

Die UI wird manuell geprüft. Bei einem Werkzeug dieser Größe rechtfertigt UI-Automatisierung den Aufwand nicht.

## Verifikation (abgeschlossen 2026-07-28)

Verhalten fremder Werkzeuge, das am echten System zu bestätigen war:

1. **Qualitätsparameter für AVIF** — ✅ bestätigt. Numerisches `sips -s formatOptions` greift auch für AVIF (Qualität 30 → 6.734 B, Qualität 90 → 14.650 B). Die Keyword-Form (`formatOptions best`) erzeugt dagegen **keine Datei** und wird deshalb nirgends benutzt. Kein Slider-Mapping nötig.
2. **`sips -Z` skaliert hoch** — ✅ bestätigt (400 px Quelle mit Grenze 2000 → 2.000 px Ausgabe). Der `ImageProbe`-Guard ist damit belegt notwendig, nicht vorsorglich.
3. **`cwebp`-Binary** — ✅ libwebp 1.6.0, Mach-O arm64, ad-hoc/linker-signed, kein Quarantäne-Flag. Tatsächliche Größe **2,6 MB** (nicht ~1 MB wie im Entwurf geschätzt).
4. **Testframework** — ❌ **Annahme war falsch.** Weder XCTest noch swift-testing ist ohne volles Xcode benutzbar:
   - XCTest liegt gar nicht in den CommandLineTools.
   - `Testing.framework` ist vorhanden, linkt aber gegen `lib_TestingInterop.dylib`, das auf dem System nirgends existiert — der Testlauf stirbt beim `dlopen`.

   **Konsequenz:** Das Testziel ist ein `executableTarget` mit einem eigenen Mini-Harness (`Tests/ConversionKitTests/TestRunner.swift`, ~150 Zeilen) statt eines `testTarget`. Ausführung über `./test.sh` statt `swift test`. Der Inhalt der Tests ist davon unberührt; die Alternative wäre gewesen, einen 25-MB-Bildkonverter von einem mehrere Gigabyte großen Xcode-Download abhängig zu machen.

   Nebeneffekt: `ImageProbe.parseFields` musste `public` werden, weil ein Executable-Target kein `@testable import` nutzen kann.

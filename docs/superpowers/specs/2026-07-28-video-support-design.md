# ImageDrop – Videokompression

**Datum:** 2026-07-28
**Status:** Freigegeben, Implementierung folgt
**Baut auf:** [2026-07-28-imagedrop-design.md](2026-07-28-imagedrop-design.md)

## Ziel

Videos komprimieren, mit voller Kontrolle über Codec und Qualität — inklusive der Formate, die macOS von sich aus nicht schreibt (WebM/VP9, AV1). Bilder bleiben unverändert.

Zwei Modi im gleichen Fenster, umschaltbar oben: **Bilder | Video**. Getrennte Warteschlangen, getrennte Einstellungen. Ein gemischter Drop landet nur mit den zum Modus passenden Dateien in der Warteschlange; der Rest wird als übersprungen gemeldet — dieselbe Mechanik, mit der heute Nicht-Bilder abgewiesen werden.

## Nicht-Ziele

Bewusst draußen, alle später nachrüstbar:

- Video→GIF, Zuschneiden/Trimmen, Zwei-Pass-Encoding, Bitraten-Zielvorgabe („mach das unter 10 MB")
- **Hardware-Encoder-Umschalter.** Der M5 kodiert H.264/HEVC per VideoToolbox um ein Vielfaches schneller, liefert bei gleicher Dateigröße aber schlechtere Qualität als x264/x265. Das ist eine eigene Abwägung und wird nicht ungefragt eingebaut.
- ffmpeg als Bildwerkzeug. Für Einzelbilder ist es schwächer als `sips`/`cwebp`; es kommt nur additiv für Video dazu.

## Werkzeugwahl

| Aufgabe | Werkzeug | Begründung |
|---|---|---|
| Video kodieren | **ffmpeg** (mitgeliefert) | Nur ffmpeg kann VP9/AV1/WebM |
| Video ausmessen | **AVFoundation** (eingebaut) | Länge, Auflösung, Tonspur — spart ein zweites ~20-MB-Binary (ffprobe) |
| Bilder | `sips` / `cwebp` | unverändert |

`avconvert` (eingebaut) wurde geprüft und verworfen: es komprimiert gut und schnell (140 MB → 23 MB HEVC in 5,1 s auf dem M5), kennt aber nur Presets und keine WebM/VP9/AV1-Ausgabe. Die Anforderung war ausdrücklich volle Kontrolle.

**Herkunft des Binaries:** ffmpeg hat keine offiziellen macOS-Builds. Bezug über `fetch-ffmpeg.sh` von einer arm64-Community-Quelle, bewusst als separater Schritt statt unbemerkt im Bundle. Ohne das Binary läuft die App weiter und der Video-Modus sagt, dass er nicht verfügbar ist — dieselbe Behandlung wie beim fehlenden `cwebp`.

## Architektur

Der bestehende Schnitt trägt fast alles. Unverändert weiterverwendet: `NameTemplate`, `NameReserver`, `OutputNaming`, `ProcessRunner`, `ConversionOutcome`, `FailureReason`.

Zwei Stellen müssen sich öffnen:

### 1. `BatchRunner` wird generisch

Heute fest auf `ConversionEngine` und `ConversionSettings` verdrahtet. Künftig generisch über ein schmales Protokoll:

```swift
public protocol MediaConverter: Sendable {
    associatedtype Settings: Sendable
    var maxConcurrency: Int { get }
    func convert(_ input: URL, settings: Settings, number: Int,
                 reserver: NameReserver?,
                 progress: @Sendable (Double) -> Void) async -> ConversionOutcome
}
```

Die Batch-Logik — Eingabereihenfolge, Parallelitätsfenster, „ein Fehler kostet nur diese eine Datei" — bleibt **eine** Implementierung für Bild und Video. Genau das war der Zweck des ursprünglichen Schnitts.

`maxConcurrency` gehört zum Konverter, nicht zu den Einstellungen: **Video läuft mit 1.** Ein ffmpeg-Encode lastet bereits alle Kerne aus, zehn parallel wären langsamer statt schneller. Bilder bleiben bei der Kernzahl.

### 2. Fortschritt bekommt eine Innensicht

„7 von 49" genügt nicht mehr, wenn ein AV1-Encode Minuten läuft. Statt `(Int, Int)`:

```swift
public struct BatchProgress: Sendable {
    public let completed: Int
    public let total: Int
    /// Fortschritt innerhalb der gerade laufenden Datei, 0...1, falls bekannt.
    public let currentFile: URL?
    public let currentFraction: Double?
}
```

Für Bilder bleibt `currentFraction` `nil` — bei 0,2 s pro Datei wäre es Zierde. ffmpeg liefert die Zahl über `-progress pipe:1`, verrechnet mit der von AVFoundation gelesenen Gesamtlänge.

### 3. Neue Bausteine

- `VideoCodec` — H.264, HEVC, VP9, AV1. Bestimmt Container (mp4 bzw. webm), Dateiendung, CRF-Bereich und -Standard sowie den ffmpeg-Encoder-Namen. Analog zu `TargetFormat` die einzige Stelle, an der ein Codec definiert ist.
- `VideoSettings` — Codec, CRF, Max. Kante, Tonspur (behalten/entfernen), Zielordner, Umbenennungsmuster. Die letzten zwei Felder sind dieselben Typen wie bei Bildern.
- `VideoProbe` — Länge, Auflösung, Tonspur-Vorhandensein über AVFoundation.
- `VideoEngine` — baut die ffmpeg-Argumente, erfüllt `MediaConverter`.

## Verhalten

Alles aus dem Bild-Design gilt weiter: Ausgabe neben dem Original (oder im gewählten Ordner), **nie überschreiben**, Umbenennungsmuster mit `{name}`/`{n}`, nur verkleinernd, ein Fehler bleibt auf eine Datei begrenzt.

Ergänzend für Video:

| Regel | Entscheidung |
|---|---|
| Metadaten | Bleiben erhalten (`-map_metadata 0`) — gleiche Regel wie bei Bildern |
| Tonspur | Standard: behalten (`-c:a copy`). Optional entfernen (`-an`) |
| Nur verkleinernd | Ist die längere Kante ≤ Grenze, entfällt der Skalierungsfilter — wie bei `sips -Z` |
| Container | Ergibt sich aus dem Codec, ist keine eigene Einstellung |

### Abbrechen

Bei 3-Sekunden-Bildbatches war das Komfort, bei einem AV1-Encode ist es Grundausstattung. Der Batch reagiert auf Task-Abbruch; `ProcessRunner` beendet über `withTaskCancellationHandler` den laufenden Kindprozess, statt ihn weiterlaufen zu lassen.

### Eine bewusste Ausnahme von „nie löschen"

Ein abgebrochener Encode hinterlässt sonst eine halbe Videodatei, die aussieht wie ein Ergebnis. Video schreibt deshalb in eine temporäre Datei neben dem Ziel und benennt sie erst bei Erfolg um. Bei Abbruch oder Fehler wird **genau diese temporäre Datei** entfernt.

Das ist eine Datei, die die App Sekunden vorher selbst angelegt und nie als Ergebnis präsentiert hat. Originale und fertige Ausgaben bleiben unangetastet. Der Bildpfad braucht das nicht: `sips` schreibt selbst über eine temporäre Datei, und `cwebp` ist bei Einzelbildern zu kurz für einen sinnvollen Abbruch.

## Oberfläche

Oben ein Umschalter **Bilder | Video**. Darunter dieselbe Struktur wie heute: Drop-Zone, Warteschlange, Einstellungen, Aktionsleiste. Die Warteschlangen sind getrennt — ein Wechsel des Modus verwirft nichts.

Video-Einstellungen: Codec (vier Knöpfe), CRF-Regler mit codec-abhängigem Bereich und einer Zeile, die erklärt, dass **kleiner = besser** ist (umgekehrt zum Qualitätsregler bei Bildern — die Verwechslungsgefahr ist real und wird benannt statt kaschiert), Max. Kante, Tonspur-Schalter, Zielordner und Umbenennen wie gehabt.

In der Aktionsleiste kommt neben „Konvertieren" ein **Abbrechen** hinzu, das nur während eines Laufs sichtbar ist. Der Fortschrittsbalken zeigt bei Video zusätzlich den Stand innerhalb der laufenden Datei.

Fehlt ffmpeg, ist der Video-Modus erreichbar, aber der Konvertieren-Knopf ist deaktiviert mit einem Hinweis auf `fetch-ffmpeg.sh`.

## Tests

Fixture-Videos werden zur Laufzeit erzeugt (`ffmpeg -f lavfi -i testsrc`), kurz und klein. Alle Video-Tests überspringen sich ohne ffmpeg — dieselbe Mechanik wie heute bei den WebP-Tests ohne `cwebp`.

Abgedeckt:

- Ergebnis ist wirklich der verlangte Container **und** Codec, per AVFoundation ausgelesen statt an der Dateiendung geraten
- Nur verkleinernd: ein 480p-Video mit Grenze 1080 behält seine Größe
- Tonspur entfernt / behalten
- Abbruch hinterlässt **keine** Datei — der zentrale Test für die temporäre Datei
- Ein kaputtes Video stoppt den Batch nicht
- Video-Konverter meldet `maxConcurrency == 1`
- Fehlendes ffmpeg ergibt einen klaren Grund, keinen stillen Fehlschlag
- Umbenennungsmuster und Zielordner wirken auch bei Video

Die bestehenden 67 Bildtests müssen unverändert grün bleiben — sie sind die Absicherung dafür, dass der generische `BatchRunner` nichts kaputt macht.

## Verifikation (abgeschlossen 2026-07-28)

1. **ffmpeg-Binary:** ✅ ffmpeg 8.0, **arm64**, ad-hoc signiert, kein Quarantäne-Flag. **49 MB entpackt** (21 MB komprimiert). Das App-Bundle wächst damit von ~5 MB auf **53 MB**.
2. **Encoder im Build:** ✅ alle vier vorhanden — `libx264`, `libx265`, `libvpx-vp9`, `libsvtav1`, dazu `aac` und `libopus`. Die Erkennung zur Laufzeit bleibt trotzdem drin: ein anderer Build kann weniger haben.
3. **`-progress pipe:1`:** ✅ liefert `out_time_us`-Zeilen, die gegen die AVFoundation-Länge eine brauchbare Prozentzahl ergeben.
4. **`avconvert` als Alternative geprüft:** 140 MB → 23 MB HEVC in 5,1 s, aber nur Presets und kein WebM/VP9/AV1. Verworfen, weil volle Kontrolle gefordert war.

### Gemessen am echten Material

Quelle: 3416×2146, 20,5 s, 56 Mbit/s, 140 MB. Ziel jeweils 1920×1080 mit dem Standard-CRF des Codecs:

| Codec | CRF | Ergebnis | vs. Quelle | Dauer |
|---|---|---|---|---|
| HEVC | 28 | 1 MB | 0,7 % | 10 s |
| AV1 | 35 | 3 MB | 2 % | 15 s |
| H.264 | 23 | 4 MB | 2 % | 6 s |
| VP9 | 32 | 4 MB | 3 % | 29 s |

Zwei Dinge, die daraus zu lernen sind: die Standard-CRF-Werte sind **nicht** aufeinander kalibriert — HEVC bei 28 ist aggressiver als AV1 bei 35, obwohl AV1 der stärkere Codec ist. Und VP9 ist mit Abstand der langsamste, was die Notwendigkeit von Abbrechen und Datei-internem Fortschritt bestätigt.

### Ein Fund beim Umbau

Der erste Lauf der Bildtests nach dem generischen `BatchRunner` schlug fehl: der Fortschritt meldete pro Datei **zweimal**. Ursache war, dass der Runner den Schnappschuss auch dann weitergab, wenn der Tracker den Wert verworfen hatte (Bilder haben keinen Fortschritt innerhalb einer Datei). Behoben, indem `report` mitteilt, ob es den Wert übernommen hat — und indem der Bild-Engine gar nicht erst so tut, als hätte er einen zu melden.

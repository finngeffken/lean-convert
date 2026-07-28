import Foundation

let runner = TestRunner()

runner.suite("Zielformat")
runner.test("JPEG ist ein echter JPEG-Container, nicht nur eine Endung", FormatTests.producesActualJPEGContainer)
runner.test("PNG ist ein echter PNG-Container", FormatTests.producesActualPNGContainer)
runner.test("AVIF ist ein echter AVIF-Container", FormatTests.producesActualAVIFContainer)
runner.test("Niedrigere Qualität erzeugt eine kleinere Datei", FormatTests.qualityAffectsFileSize)

runner.suite("Skalierung")
runner.test("Verkleinern trifft die Grenze und hält das Seitenverhältnis", ResizeTests.downscaleKeepsAspectRatio)
runner.test("Hochskalieren wird verweigert", ResizeTests.upscaleIsRefused)
runner.test("Bei Hochformat begrenzt die Max-Kante die Höhe", ResizeTests.maxEdgeBoundsLongerEdgeOnPortrait)
runner.test("Ohne Max-Kante bleibt die Größe unangetastet", ResizeTests.noMaxEdgeKeepsOriginalSize)
runner.test("Genau auf der Grenze wird nicht skaliert", ResizeTests.exactlyAtBoundIsNotResized)

runner.suite("Nie überschreiben")
runner.test("Kollision hängt einen Zähler an", OverwriteTests.collisionAppendsCounter)
runner.test("PNG → PNG lässt das Original unberührt", OverwriteTests.convertingIntoOwnFormatKeepsOriginal)

runner.suite("Fehlerfälle")
runner.test("Kaputte Datei liefert einen Grund statt eines Absturzes", FailureTests.corruptFileFailsWithReason)
runner.test("WebP ohne Binary meldet das fehlende Werkzeug", FailureTests.webPWithoutBinaryReportsToolMissing)
runner.test("Fehlende Datei schlägt fehl", FailureTests.missingFileFails)

runner.suite("ImageProbe")
runner.test("Liest Maße und Alpha", ProbeTests.readsDimensionsAndAlpha)
runner.test("Kaputte Datei wirft", ProbeTests.corruptFileThrows)
runner.test("Feld-Parsing ignoriert die Pfadzeile", ProbeTests.fieldParsingIgnoresPathLine)

runner.suite("Dateibenennung")
runner.test("Ohne Kollision der einfache Name", NamingTests.usesPlainNameWhenFree)
runner.test("Überspringt bestehende Dateien", NamingTests.skipsPastExistingFiles)
runner.test("Ausgabe landet neben dem Original", NamingTests.outputSitsNextToInput)

runner.suite("Eingabeprüfung")
runner.test("Trennt Bilder von allem anderen", ValidatorTests.separatesImagesFromEverythingElse)

runner.suite("Formatvorschlag")
runner.test("Kein Vorschlag bei Nicht-HEIC", SuggestionTests.noSuggestionForNonHEIC)
runner.test("Kein Vorschlag bei gemischtem Drop", SuggestionTests.noSuggestionForMixedDrop)
runner.test("Leerer Drop ergibt keinen Vorschlag", SuggestionTests.emptyDropHasNoSuggestion)
runner.test("Deckendes HEIC schlägt JPEG vor", SuggestionTests.opaqueHEICSuggestsJPEG)
runner.test("Transparentes HEIC schlägt PNG vor", SuggestionTests.transparentHEICSuggestsPNG)

runner.suite("Einstellungen")
runner.test("Qualität wird auf 1...100 begrenzt", SettingsTests.qualityIsClamped)
runner.test("PNG bietet keine Qualität an", SettingsTests.pngHasNoQuality)
runner.test("Alpha-Fähigkeit passt zum Format", SettingsTests.alphaMatchesFormat)
runner.test("Dateiendungen sind eindeutig", SettingsTests.fileExtensionsAreDistinct)

runner.suite("Batch")
await runner.test("Eine kaputte Datei stoppt die anderen nicht", BatchTests.corruptFileDoesNotStopTheRest)
await runner.test("Ergebnisse kommen in Eingabereihenfolge zurück", BatchTests.resultsComeBackInInputOrder)
await runner.test("Fortschritt meldet jede Datei genau einmal", BatchTests.progressReportsEveryFileOnce)
await runner.test("Alle Dateien laufen durch, auch über dem Parallelitätslimit", BatchTests.everyFileIsProcessedBeyondTheConcurrencyLimit)
await runner.test("Leere Eingabe liefert leeres Ergebnis", BatchTests.emptyInputReturnsEmpty)
await runner.test("Parallelitätslimit 0 wird auf 1 angehoben", BatchTests.concurrencyLimitIsClampedToAtLeastOne)

runner.suite("WebP")
if TestSupport.hasCwebp {
    runner.test("Erzeugt einen echten WebP-Container", WebPTests.producesWebPContainer)
    runner.test("Skalierung hält das Seitenverhältnis", WebPTests.resizeKeepsAspectRatio)
    runner.test("Hochformat: Skalierung begrenzt die Höhe", WebPTests.portraitResizeBoundsHeight)
    runner.test("EXIF überlebt die WebP-Konvertierung", WebPTests.exifSurvives)
} else {
    let reason = "cwebp liegt nicht in Resources/"
    runner.skip("Erzeugt einen echten WebP-Container", reason)
    runner.skip("Skalierung hält das Seitenverhältnis", reason)
    runner.skip("Hochformat: Skalierung begrenzt die Höhe", reason)
    runner.skip("EXIF überlebt die WebP-Konvertierung", reason)
}

runner.finish()

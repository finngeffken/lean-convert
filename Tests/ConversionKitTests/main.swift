import Foundation

let runner = TestRunner()

runner.suite("Zielformat")
await runner.test("JPEG ist ein echter JPEG-Container, nicht nur eine Endung", FormatTests.producesActualJPEGContainer)
await runner.test("PNG ist ein echter PNG-Container", FormatTests.producesActualPNGContainer)
await runner.test("AVIF ist ein echter AVIF-Container", FormatTests.producesActualAVIFContainer)
await runner.test("Niedrigere Qualität erzeugt eine kleinere Datei", FormatTests.qualityAffectsFileSize)

runner.suite("Skalierung")
await runner.test("Verkleinern trifft die Grenze und hält das Seitenverhältnis", ResizeTests.downscaleKeepsAspectRatio)
await runner.test("Hochskalieren wird verweigert", ResizeTests.upscaleIsRefused)
await runner.test("Bei Hochformat begrenzt die Max-Kante die Höhe", ResizeTests.maxEdgeBoundsLongerEdgeOnPortrait)
await runner.test("Ohne Max-Kante bleibt die Größe unangetastet", ResizeTests.noMaxEdgeKeepsOriginalSize)
await runner.test("Genau auf der Grenze wird nicht skaliert", ResizeTests.exactlyAtBoundIsNotResized)

runner.suite("Nie überschreiben")
await runner.test("Kollision hängt einen Zähler an", OverwriteTests.collisionAppendsCounter)
await runner.test("PNG → PNG lässt das Original unberührt", OverwriteTests.convertingIntoOwnFormatKeepsOriginal)

runner.suite("Fehlerfälle")
await runner.test("Kaputte Datei liefert einen Grund statt eines Absturzes", FailureTests.corruptFileFailsWithReason)
await runner.test("WebP ohne Binary meldet das fehlende Werkzeug", FailureTests.webPWithoutBinaryReportsToolMissing)
await runner.test("Fehlende Datei schlägt fehl", FailureTests.missingFileFails)

runner.suite("ImageProbe")
await runner.test("Liest Maße und Alpha", ProbeTests.readsDimensionsAndAlpha)
await runner.test("Kaputte Datei wirft", ProbeTests.corruptFileThrows)
await runner.test("Feld-Parsing ignoriert die Pfadzeile", ProbeTests.fieldParsingIgnoresPathLine)

runner.suite("Dateibenennung")
await runner.test("Ohne Kollision der einfache Name", NamingTests.usesPlainNameWhenFree)
await runner.test("Überspringt bestehende Dateien", NamingTests.skipsPastExistingFiles)
await runner.test("Ausgabe landet neben dem Original", NamingTests.outputSitsNextToInput)

runner.suite("Eingabeprüfung")
await runner.test("Trennt Bilder von allem anderen", ValidatorTests.separatesImagesFromEverythingElse)

runner.suite("Formatvorschlag")
await runner.test("Kein Vorschlag bei Nicht-HEIC", SuggestionTests.noSuggestionForNonHEIC)
await runner.test("Kein Vorschlag bei gemischtem Drop", SuggestionTests.noSuggestionForMixedDrop)
await runner.test("Leerer Drop ergibt keinen Vorschlag", SuggestionTests.emptyDropHasNoSuggestion)
await runner.test("Deckendes HEIC schlägt JPEG vor", SuggestionTests.opaqueHEICSuggestsJPEG)
await runner.test("Transparentes HEIC schlägt PNG vor", SuggestionTests.transparentHEICSuggestsPNG)

runner.suite("Einstellungen")
await runner.test("Qualität wird auf 1...100 begrenzt", SettingsTests.qualityIsClamped)
await runner.test("PNG bietet keine Qualität an", SettingsTests.pngHasNoQuality)
await runner.test("Alpha-Fähigkeit passt zum Format", SettingsTests.alphaMatchesFormat)
await runner.test("Dateiendungen sind eindeutig", SettingsTests.fileExtensionsAreDistinct)

runner.suite("Umbenennen")
await runner.test("Leeres Muster behält den Originalnamen", TemplateTests.emptyPatternKeepsOriginalName)
await runner.test("{n}/{nn}/{nnn} füllt mit Nullen auf", TemplateTests.counterTokenPadsToTokenLength)
await runner.test("{name} setzt den Originalnamen ein", TemplateTests.nameTokenInsertsOriginal)
await runner.test("Kombinierte Platzhalter", TemplateTests.combinedTokens)
await runner.test("Unbekannter Platzhalter bleibt sichtbar stehen", TemplateTests.unknownTokenStaysLiteral)
await runner.test("Offene Klammer wird wörtlich genommen", TemplateTests.unclosedBraceIsTakenLiterally)
await runner.test("Verbotene Zeichen werden entfernt", TemplateTests.illegalCharactersAreStripped)
await runner.test("Muster nur aus Trennzeichen bleibt wörtlich", TemplateTests.separatorOnlyPatternStaysLiteral)
await runner.test("Muster ohne Rest fällt auf den Originalnamen zurück", TemplateTests.patternThatResolvesToNothingFallsBackToOriginal)
await runner.test("Vorschau enthält die Zielendung", TemplateTests.previewIncludesTargetExtension)

runner.suite("Zielordner")
await runner.test("Ausgabe landet im gewählten Ordner", DestinationTests.outputLandsInChosenDirectory)
await runner.test("Ohne Ziel weiterhin neben dem Original", DestinationTests.nilDestinationStillMeansNextToOriginal)
await runner.test("Nicht beschreibbares Ziel schlägt fehl", DestinationTests.unwritableDestinationFails)
await runner.test("Umbenennen und Zielordner zusammen", DestinationTests.renamingIntoChosenDirectory)

runner.suite("Namensreservierung")
await runner.test("Gleiche Anfrage zweimal ergibt zwei Namen", ReserverTests.reservesDistinctNamesForIdenticalRequests)
await runner.test("Berücksichtigt Dateien auf der Platte", ReserverTests.respectsFilesAlreadyOnDisk)

runner.suite("Batch")
await runner.test("Eine kaputte Datei stoppt die anderen nicht", BatchTests.corruptFileDoesNotStopTheRest)
await runner.test("Ergebnisse kommen in Eingabereihenfolge zurück", BatchTests.resultsComeBackInInputOrder)
await runner.test("Fortschritt meldet jede Datei genau einmal", BatchTests.progressReportsEveryFileOnce)
await runner.test("Alle Dateien laufen durch, auch über dem Parallelitätslimit", BatchTests.everyFileIsProcessedBeyondTheConcurrencyLimit)
await runner.test("Leere Eingabe liefert leeres Ergebnis", BatchTests.emptyInputReturnsEmpty)
await runner.test("Parallelitätslimit 0 wird auf 1 angehoben", BatchTests.concurrencyLimitIsClampedToAtLeastOne)
await runner.test("Fixer Name parallel: 20 Dateien, 20 verschiedene Pfade", BatchNamingTests.parallelBatchWithFixedNameProducesDistinctFiles)
await runner.test("Nummerierung folgt der Eingabereihenfolge", BatchNamingTests.counterFollowsInputOrder)
await runner.test("Gleicher Dateiname aus zwei Ordnern kollidiert nicht", BatchNamingTests.sameFilenameFromDifferentFoldersDoesNotCollide)

runner.suite("WebP")
if TestSupport.hasCwebp {
    await runner.test("Erzeugt einen echten WebP-Container", WebPTests.producesWebPContainer)
    await runner.test("Skalierung hält das Seitenverhältnis", WebPTests.resizeKeepsAspectRatio)
    await runner.test("Hochformat: Skalierung begrenzt die Höhe", WebPTests.portraitResizeBoundsHeight)
    await runner.test("EXIF überlebt die WebP-Konvertierung", WebPTests.exifSurvives)
} else {
    let reason = "cwebp liegt nicht in Resources/"
    runner.skip("Erzeugt einen echten WebP-Container", reason)
    runner.skip("Skalierung hält das Seitenverhältnis", reason)
    runner.skip("Hochformat: Skalierung begrenzt die Höhe", reason)
    runner.skip("EXIF überlebt die WebP-Konvertierung", reason)
}

runner.suite("Großer Batch (49 Dateien, 4000×3000)")
await runner.test("Parallelität unter Kernzahl (4)", ScaleTests.belowCoreCount)
await runner.test("Parallelität = Kernzahl", ScaleTests.fullConcurrency)
await runner.test("Parallelität über Kernzahl verklemmt nicht", timeout: 90, ScaleTests.oversubscribedConcurrency)
await runner.test("Batch aus @MainActor gestartet läuft durch", MainActorReproTests.batchStartedFromMainActorFinishes)
if RealFilesRepro.isAvailable {
    await runner.test("Echte 49 Fotos (6000×4000) → AVIF", RealFilesRepro.realBatchFinishes)
} else {
    runner.skip("Echte 49 Fotos (6000×4000) → AVIF", "Quellordner nicht vorhanden")
}

runner.finish()

import Foundation
import ConversionKit

enum ProbeTests {

    static func readsDimensionsAndAlpha() async throws {
        let directory = try TestImage.scratchDirectory("probe")

        let opaque = directory.appendingPathComponent("opaque.png")
        try TestImage.writePNG(width: 640, height: 480, alpha: false, to: opaque)
        let opaqueInfo = try await ImageProbe.probe(opaque)
        try expectEqual(opaqueInfo.width, 640, "Breite")
        try expectEqual(opaqueInfo.height, 480, "Höhe")
        try expectEqual(opaqueInfo.longerEdge, 640, "längere Kante")

        let transparent = directory.appendingPathComponent("alpha.png")
        try TestImage.writePNG(width: 100, height: 200, alpha: true, to: transparent)
        let alphaInfo = try await ImageProbe.probe(transparent)
        try expect(alphaInfo.hasAlpha, "Alpha muss erkannt werden")
        try expectEqual(alphaInfo.longerEdge, 200, "bei Hochformat ist die Höhe die längere Kante")
    }

    static func corruptFileThrows() async throws {
        let directory = try TestImage.scratchDirectory("probe-corrupt")
        let broken = directory.appendingPathComponent("broken.png")
        try TestImage.writeCorrupt(to: broken)

        try await expectThrows("Probe auf kaputter Datei") {
            _ = try await ImageProbe.probe(broken)
        }
    }

    static func fieldParsingIgnoresPathLine() async throws {
        let output = """
        /some/path/to/image.png
          pixelWidth: 1920
          pixelHeight: 1080
          hasAlpha: no
        """
        let fields = ImageProbe.parseFields(output)
        try expectEqual(fields["pixelWidth"], "1920")
        try expectEqual(fields["pixelHeight"], "1080")
        try expectEqual(fields["hasAlpha"], "no")
    }
}

enum NamingTests {

    static func usesPlainNameWhenFree() async throws {
        let directory = try TestImage.scratchDirectory("naming-free")
        let input = directory.appendingPathComponent("holiday.heic")

        let destination = OutputNaming.destination(for: input, format: .jpeg)
        try expectEqual(destination.lastPathComponent, "holiday.jpg")
        try expectEqual(destination.deletingLastPathComponent().path, directory.path)
    }

    static func skipsPastExistingFiles() async throws {
        let directory = try TestImage.scratchDirectory("naming-taken")
        let input = directory.appendingPathComponent("shot.png")
        try TestImage.writePNG(width: 50, height: 50, to: input)
        try Data().write(to: directory.appendingPathComponent("shot.jpg"))
        try Data().write(to: directory.appendingPathComponent("shot-1.jpg"))

        let destination = OutputNaming.destination(for: input, format: .jpeg)
        try expectEqual(destination.lastPathComponent, "shot-2.jpg")
    }

    static func outputSitsNextToInput() async throws {
        let directory = try TestImage.scratchDirectory("naming-location")
        let nested = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let input = nested.appendingPathComponent("deep.png")

        let destination = OutputNaming.destination(for: input, format: .webp)
        try expectEqual(destination.deletingLastPathComponent().path, nested.path)
        try expectEqual(destination.lastPathComponent, "deep.webp")
    }
}

enum ValidatorTests {

    static func separatesImagesFromEverythingElse() async throws {
        let directory = try TestImage.scratchDirectory("validator")

        let image = directory.appendingPathComponent("real.png")
        try TestImage.writePNG(width: 80, height: 80, to: image)

        let textFile = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: textFile)

        let subdirectory = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)

        let missing = directory.appendingPathComponent("ghost.png")

        let (accepted, rejected) = InputValidator.partition([image, textFile, subdirectory, missing])

        try expectEqual(accepted, [image], "nur das echte Bild wird akzeptiert")
        try expectEqual(rejected.count, 3, "Textdatei, Ordner und fehlende Datei fallen raus")
    }
}

enum SuggestionTests {

    static func noSuggestionForNonHEIC() async throws {
        let directory = try TestImage.scratchDirectory("suggest-png")
        let input = directory.appendingPathComponent("plain.png")
        try TestImage.writePNG(width: 100, height: 100, to: input)

        try expectNil(await FormatSuggestion.suggestedTarget(for: [input]))
    }

    static func noSuggestionForMixedDrop() async throws {
        let directory = try TestImage.scratchDirectory("suggest-mixed")
        let png = directory.appendingPathComponent("a.png")
        try TestImage.writePNG(width: 100, height: 100, to: png)
        let heic = directory.appendingPathComponent("b.heic")
        try TestImage.writePNG(width: 100, height: 100, to: heic)

        try expectNil(
            await FormatSuggestion.suggestedTarget(for: [png, heic]),
            "ein gemischter Drop darf das Format nicht still ändern"
        )
    }

    static func emptyDropHasNoSuggestion() async throws {
        try expectNil(await FormatSuggestion.suggestedTarget(for: []))
    }

    /// Opaque HEIC is the iPhone-photo case: JPEG is what the user wants.
    static func opaqueHEICSuggestsJPEG() async throws {
        let directory = try TestImage.scratchDirectory("suggest-heic-opaque")
        let heic = directory.appendingPathComponent("photo.heic")
        try TestImage.writeHEIC(width: 400, height: 300, alpha: false, to: heic)

        try expectEqual(await FormatSuggestion.suggestedTarget(for: [heic]), .jpeg)
    }

    static func transparentHEICSuggestsPNG() async throws {
        let directory = try TestImage.scratchDirectory("suggest-heic-alpha")
        let heic = directory.appendingPathComponent("cutout.heic")
        try TestImage.writeHEIC(width: 400, height: 300, alpha: true, to: heic)

        try expectEqual(await FormatSuggestion.suggestedTarget(for: [heic]), .png)
    }
}

enum SettingsTests {

    static func qualityIsClamped() async throws {
        try expectEqual(ConversionSettings(target: .jpeg, quality: 0).quality, 1)
        try expectEqual(ConversionSettings(target: .jpeg, quality: 500).quality, 100)
        try expectEqual(ConversionSettings(target: .jpeg, quality: 72).quality, 72)
    }

    /// AVIF is the one format whose tool rejects 100.
    static func avifQualityIsCappedAt99() async throws {
        try expectEqual(TargetFormat.avif.maxQuality, 99)
        try expectEqual(ConversionSettings(target: .avif, quality: 100).quality, 99)
        try expectEqual(ConversionSettings(target: .avif, quality: 99).quality, 99)
        try expectEqual(ConversionSettings(target: .avif, quality: 60).quality, 60)

        for format in [TargetFormat.jpeg, .png, .webp] {
            try expectEqual(format.maxQuality, 100, "\(format.displayName) verträgt 100")
        }
    }

    static func pngHasNoQuality() async throws {
        try expect(!TargetFormat.png.supportsQuality, "PNG ist verlustfrei")
        for format in [TargetFormat.jpeg, .webp, .avif] {
            try expect(format.supportsQuality, "\(format) sollte Qualität anbieten")
        }
    }

    static func alphaMatchesFormat() async throws {
        try expect(!TargetFormat.jpeg.preservesAlpha, "JPEG kann kein Alpha")
        for format in [TargetFormat.png, .webp, .avif] {
            try expect(format.preservesAlpha, "\(format) sollte Alpha halten")
        }
    }

    static func fileExtensionsAreDistinct() async throws {
        let extensions = TargetFormat.allCases.map(\.fileExtension)
        try expectEqual(Set(extensions).count, extensions.count, "Endungen müssen eindeutig sein")
    }
}

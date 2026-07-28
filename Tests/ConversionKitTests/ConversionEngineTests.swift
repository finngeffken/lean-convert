import Foundation
import ConversionKit

enum FormatTests {

    static func producesActualJPEGContainer() throws {
        let directory = try TestImage.scratchDirectory("format-jpeg")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 600, height: 400, to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .jpeg, quality: 80))

        let output = try require(outcome.successOutput, "Erfolg")
        try expectEqual(try TestImage.containerType(of: output), ContainerType.jpeg)
    }

    static func producesActualPNGContainer() throws {
        let directory = try TestImage.scratchDirectory("format-png")
        let input = directory.appendingPathComponent("source.jpg")
        try TestImage.writeJPEG(width: 500, height: 500, to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .png))

        let output = try require(outcome.successOutput, "Erfolg")
        try expectEqual(try TestImage.containerType(of: output), ContainerType.png)
    }

    static func producesActualAVIFContainer() throws {
        let directory = try TestImage.scratchDirectory("format-avif")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 600, height: 400, to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .avif, quality: 60))

        let output = try require(outcome.successOutput, "Erfolg")
        try expectEqual(try TestImage.containerType(of: output), ContainerType.avif)
    }

    static func qualityAffectsFileSize() throws {
        let directory = try TestImage.scratchDirectory("quality")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 1200, height: 900, to: input)

        let engine = TestSupport.engine()
        let low = try require(engine.convert(input, settings: .init(target: .jpeg, quality: 20)).byteSizes)
        let high = try require(engine.convert(input, settings: .init(target: .jpeg, quality: 95)).byteSizes)

        try expect(
            low.after < high.after,
            "Qualität 20 (\(low.after) B) sollte kleiner sein als 95 (\(high.after) B)"
        )
    }
}

enum ResizeTests {

    static func downscaleKeepsAspectRatio() throws {
        let directory = try TestImage.scratchDirectory("downscale")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 2000, height: 1000, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, quality: 85, maxEdge: 800)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 800, "Breite")
        try expectEqual(size.height, 400, "2:1 muss die Skalierung überleben")
    }

    /// The reason `ImageProbe` exists: `sips -Z` interpolates small images *up*
    /// to the bound, which is both unwanted and lossy.
    static func upscaleIsRefused() throws {
        let directory = try TestImage.scratchDirectory("no-upscale")
        let input = directory.appendingPathComponent("small.png")
        try TestImage.writePNG(width: 400, height: 300, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, quality: 85, maxEdge: 2000)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 400, "400px darf nicht auf 2000px aufgeblasen werden")
        try expectEqual(size.height, 300, "Höhe")
    }

    static func maxEdgeBoundsLongerEdgeOnPortrait() throws {
        let directory = try TestImage.scratchDirectory("portrait")
        let input = directory.appendingPathComponent("tall.png")
        try TestImage.writePNG(width: 500, height: 1500, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, quality: 85, maxEdge: 900)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.height, 900, "die längere Kante wird begrenzt")
        try expectEqual(size.width, 300, "Breite")
    }

    static func noMaxEdgeKeepsOriginalSize() throws {
        let directory = try TestImage.scratchDirectory("no-resize")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 1234, height: 567, to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .jpeg))

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 1234, "Breite")
        try expectEqual(size.height, 567, "Höhe")
    }

    /// Exactly at the bound nothing should happen — an off-by-one here would
    /// re-encode every already-correct image for nothing.
    static func exactlyAtBoundIsNotResized() throws {
        let directory = try TestImage.scratchDirectory("at-bound")
        let input = directory.appendingPathComponent("exact.png")
        try TestImage.writePNG(width: 800, height: 400, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, quality: 85, maxEdge: 800)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 800, "Breite")
        try expectEqual(size.height, 400, "Höhe")
    }
}

enum OverwriteTests {

    static func collisionAppendsCounter() throws {
        let directory = try TestImage.scratchDirectory("collision")
        let input = directory.appendingPathComponent("photo.png")
        try TestImage.writePNG(width: 300, height: 200, to: input)

        let engine = TestSupport.engine()
        let settings = ConversionSettings(target: .jpeg, quality: 80)

        let first = try require(engine.convert(input, settings: settings).successOutput)
        let second = try require(engine.convert(input, settings: settings).successOutput)
        let third = try require(engine.convert(input, settings: settings).successOutput)

        try expectEqual(first.lastPathComponent, "photo.jpg")
        try expectEqual(second.lastPathComponent, "photo-1.jpg")
        try expectEqual(third.lastPathComponent, "photo-2.jpg")
    }

    /// Converting a PNG to PNG must not clobber the source.
    static func convertingIntoOwnFormatKeepsOriginal() throws {
        let directory = try TestImage.scratchDirectory("self-format")
        let input = directory.appendingPathComponent("keep.png")
        try TestImage.writePNG(width: 300, height: 200, to: input)
        let originalBytes = try Data(contentsOf: input).count

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .png))

        let output = try require(outcome.successOutput)
        try expectEqual(output.lastPathComponent, "keep-1.png")
        try expectEqual(
            try Data(contentsOf: input).count,
            originalBytes,
            "Quelle muss unverändert sein"
        )
    }
}

enum FailureTests {

    static func corruptFileFailsWithReason() throws {
        let directory = try TestImage.scratchDirectory("corrupt")
        let input = directory.appendingPathComponent("broken.png")
        try TestImage.writeCorrupt(to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .jpeg))

        let reason = try require(outcome.failureReason, "Fehlschlag")
        guard case .unreadable = reason else {
            throw TestFailure(
                message: "erwartet .unreadable, bekommen \(reason)",
                file: #fileID,
                line: #line
            )
        }
    }

    static func webPWithoutBinaryReportsToolMissing() throws {
        let directory = try TestImage.scratchDirectory("no-cwebp")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 300, height: 200, to: input)

        let engine = TestSupport.engineWithoutWebP()
        try expect(!engine.supportsWebP, "Engine ohne Binary darf WebP nicht melden")
        try expect(!engine.availableFormats.contains(.webp), "WebP darf nicht angeboten werden")

        let outcome = engine.convert(input, settings: .init(target: .webp))
        try expectEqual(outcome.failureReason, .toolMissing("cwebp"))
    }

    static func missingFileFails() throws {
        let directory = try TestImage.scratchDirectory("missing")
        let input = directory.appendingPathComponent("ghost.png")

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .jpeg))
        try expect(!outcome.isSuccess, "eine nicht existierende Datei darf nicht erfolgreich sein")
    }
}

enum WebPTests {

    static func producesWebPContainer() throws {
        let directory = try TestImage.scratchDirectory("webp")
        let input = directory.appendingPathComponent("source.png")
        try TestImage.writePNG(width: 800, height: 600, to: input)

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .webp, quality: 80))

        let output = try require(outcome.successOutput)
        try expectEqual(try TestImage.containerType(of: output), ContainerType.webp)
    }

    static func resizeKeepsAspectRatio() throws {
        let directory = try TestImage.scratchDirectory("webp-resize")
        let input = directory.appendingPathComponent("wide.png")
        try TestImage.writePNG(width: 1600, height: 800, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .webp, quality: 80, maxEdge: 400)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 400, "Breite")
        try expectEqual(size.height, 200, "Höhe")
    }

    static func portraitResizeBoundsHeight() throws {
        let directory = try TestImage.scratchDirectory("webp-portrait")
        let input = directory.appendingPathComponent("tall.png")
        try TestImage.writePNG(width: 600, height: 1200, to: input)

        let outcome = TestSupport.engine().convert(
            input,
            settings: .init(target: .webp, quality: 80, maxEdge: 600)
        )

        let output = try require(outcome.successOutput)
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.height, 600, "Höhe")
        try expectEqual(size.width, 300, "Breite")
    }

    /// `cwebp` discards EXIF unless told otherwise. This test is the guard
    /// against `-metadata all` quietly disappearing.
    static func exifSurvives() throws {
        let directory = try TestImage.scratchDirectory("webp-exif")
        let input = directory.appendingPathComponent("tagged.jpg")
        let stamp = "2026:07:28 11:22:33"
        try TestImage.writeJPEG(width: 600, height: 400, exifDateTimeOriginal: stamp, to: input)
        try expectEqual(
            TestImage.exifDateTimeOriginal(of: input),
            stamp,
            "Fixture muss EXIF tragen"
        )

        let outcome = TestSupport.engine().convert(input, settings: .init(target: .webp, quality: 85))

        let output = try require(outcome.successOutput)
        try expectEqual(TestImage.exifDateTimeOriginal(of: output), stamp)
    }
}

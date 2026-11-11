import Foundation
import ConversionKit

/// Pure logic — runs with or without ffmpeg present.
enum VideoLogicTests {

    static func containerFollowsCodec() async throws {
        try expectEqual(VideoCodec.h264.fileExtension, "mp4")
        try expectEqual(VideoCodec.hevc.fileExtension, "mp4")
        try expectEqual(VideoCodec.av1.fileExtension, "mp4")
        try expectEqual(VideoCodec.vp9.fileExtension, "webm", "VP9 gehört in WebM")
    }

    static func crfIsClampedToTheCodecRange() async throws {
        // x264/x265 stop at 51, the VP9 and AV1 encoders at 63.
        try expectEqual(VideoSettings(codec: .h264, crf: 99).crf, 51)
        try expectEqual(VideoSettings(codec: .vp9, crf: 99).crf, 63)
        try expectEqual(VideoSettings(codec: .h264, crf: -5).crf, 0)
        try expectEqual(VideoSettings(codec: .hevc, crf: 30).crf, 30)
    }

    static func defaultCRFUsedWhenNoneGiven() async throws {
        for codec in VideoCodec.allCases {
            try expectEqual(
                VideoSettings(codec: codec).crf,
                codec.defaultCRF,
                "\(codec.displayName) ohne Angabe"
            )
        }
    }

    /// yuv420p needs even dimensions; an odd number makes ffmpeg refuse.
    static func scaledSizeIsAlwaysEven() async throws {
        let info = VideoInfo(width: 1920, height: 1080, durationSeconds: 10,
                             hasAudio: true, audioIsAAC: true)
        let size = try require(VideoEngine.scaledSize(info: info, bound: 1280))
        try expectEqual(size.width, 1280, "Breite")
        try expectEqual(size.height, 720, "Höhe")
        try expect(size.width % 2 == 0 && size.height % 2 == 0, "beide Kanten müssen gerade sein")

        // 1001x777 scaled to 500 would land on odd values without rounding.
        let odd = VideoInfo(width: 1001, height: 777, durationSeconds: 5,
                            hasAudio: false, audioIsAAC: false)
        let oddSize = try require(VideoEngine.scaledSize(info: odd, bound: 500))
        try expect(oddSize.width % 2 == 0 && oddSize.height % 2 == 0,
                   "auch bei schiefen Ausgangsmaßen gerade: \(oddSize)")
    }

    static func portraitScalesByHeight() async throws {
        let info = VideoInfo(width: 1080, height: 1920, durationSeconds: 10,
                             hasAudio: false, audioIsAAC: false)
        let size = try require(VideoEngine.scaledSize(info: info, bound: 960))
        try expectEqual(size.height, 960, "die längere Kante wird begrenzt")
        try expectEqual(size.width, 540, "Breite")
    }

    static func noScaleFilterWhenAlreadySmallEnough() async throws {
        let info = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                             hasAudio: false, audioIsAAC: false)
        let arguments = VideoEngine.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.mp4"),
            settings: .init(codec: .h264, maxEdge: 1080),
            info: info
        )
        try expect(!arguments.contains("-vf"), "kein Skalierungsfilter beim Hochskalieren")
    }

    /// WebM cannot hold AAC, and MP4 cannot hold the PCM audio that camera and
    /// screen-recording .mov files often carry — so copying is only safe for
    /// AAC into MP4.
    static func audioArgumentsFollowTheContainer() async throws {
        let aacSource = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                                  hasAudio: true, audioIsAAC: true)
        let pcmSource = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                                  hasAudio: true, audioIsAAC: false)
        let input = URL(fileURLWithPath: "/tmp/in.mov")
        let output = URL(fileURLWithPath: "/tmp/out.mp4")

        func arguments(_ codec: VideoCodec, _ info: VideoInfo, keepAudio: Bool = true) -> [String] {
            VideoEngine.arguments(
                input: input, output: output,
                settings: .init(codec: codec, keepAudio: keepAudio),
                info: info
            )
        }

        try expect(arguments(.h264, aacSource).contains("copy"), "AAC nach MP4 darf kopiert werden")
        try expect(arguments(.h264, pcmSource).contains("aac"), "PCM nach MP4 muss neu kodiert werden")
        try expect(arguments(.vp9, aacSource).contains("libopus"), "WebM braucht Opus")
        try expect(arguments(.h264, aacSource, keepAudio: false).contains("-an"), "Tonspur entfernen")
    }

    static func metadataIsKept() async throws {
        let info = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                             hasAudio: false, audioIsAAC: false)
        let arguments = VideoEngine.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.mp4"),
            settings: .init(codec: .h264),
            info: info
        )
        try expect(arguments.contains("-map_metadata"), "Metadaten bleiben erhalten")
    }

    /// Without the hvc1 tag Safari and QuickTime refuse to play HEVC output.
    static func hevcCarriesTheAppleCompatibilityTag() async throws {
        let info = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                             hasAudio: false, audioIsAAC: false)
        let arguments = VideoEngine.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.mp4"),
            settings: .init(codec: .hevc),
            info: info
        )
        try expect(arguments.contains("hvc1"), "HEVC braucht -tag:v hvc1")
    }

    /// libvpx-vp9 ignores -crf unless the bitrate is pinned to zero.
    static func vp9PinsBitrateToZero() async throws {
        let info = VideoInfo(width: 640, height: 480, durationSeconds: 3,
                             hasAudio: false, audioIsAAC: false)
        let arguments = VideoEngine.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mp4"),
            output: URL(fileURLWithPath: "/tmp/out.webm"),
            settings: .init(codec: .vp9),
            info: info
        )
        let index = try require(arguments.firstIndex(of: "-b:v"))
        try expectEqual(arguments[index + 1], "0")
    }

    static func progressLineParsing() async throws {
        try expectEqual(VideoEngine.outTimeMicroseconds(from: "out_time_us=2500000"), 2_500_000)
        try expectNil(VideoEngine.outTimeMicroseconds(from: "frame=42"))
        try expectNil(VideoEngine.outTimeMicroseconds(from: "out_time_us=nonsense"))
    }

    static func oneEncodeAtATime() async throws {
        try expectEqual(VideoEngine(ffmpegURL: nil).maxConcurrency, 1,
                        "ein ffmpeg-Encode lastet schon alle Kerne aus")
    }

    static func missingFFmpegReportsToolMissing() async throws {
        let directory = try TestImage.scratchDirectory("video-no-ffmpeg")
        let input = directory.appendingPathComponent("clip.mp4")
        try Data("egal".utf8).write(to: input)

        let engine = VideoEngine(ffmpegURL: nil)
        try expect(!engine.isAvailable, "ohne Binary nicht verfügbar")

        let outcome = await engine.convert(input, settings: .init(codec: .h264))
        try expectEqual(outcome.failureReason, .toolMissing("ffmpeg"))
    }

    static func videosAndImagesArePartitionedSeparately() async throws {
        let directory = try TestImage.scratchDirectory("video-partition")
        let image = directory.appendingPathComponent("pic.png")
        try TestImage.writePNG(width: 60, height: 60, to: image)
        let notes = directory.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: notes)

        let (images, _) = InputValidator.partition([image, notes])
        try expectEqual(images, [image], "Bildmodus nimmt nur das Bild")

        let (videos, rejected) = InputValidator.partitionVideos([image, notes])
        try expect(videos.isEmpty, "ein PNG ist kein Video")
        try expectEqual(rejected.count, 2, "beide fallen im Videomodus raus")
    }
}

/// Real encodes. Skipped without ffmpeg, the same way the WebP tests skip
/// without cwebp.
enum VideoEncodeTests {

    static func producesRequestedCodecAndContainer() async throws {
        let directory = try TestImage.scratchDirectory("video-codec")
        let input = directory.appendingPathComponent("source.mp4")
        try await TestVideo.write(width: 320, height: 240, seconds: 1, to: input)

        let engine = TestVideo.engine()
        let available = await engine.availableCodecs()

        // Codec name as ffmpeg reports it back for each of ours.
        let expected: [VideoCodec: String] = [
            .h264: "h264", .hevc: "hevc", .vp9: "vp9", .av1: "av1",
        ]

        for codec in available {
            let outcome = await engine.convert(
                input,
                settings: .init(codec: codec, crf: codec.defaultCRF, keepAudio: false)
            )
            let output = try require(outcome.successOutput, "\(codec.displayName) muss klappen")
            try expectEqual(
                output.pathExtension,
                codec.fileExtension,
                "\(codec.displayName) Container"
            )
            let reported = try await TestVideo.videoCodecName(of: output)
            try expectEqual(reported, expected[codec], "\(codec.displayName) laut ffmpeg")
        }
    }

    static func downscalesButNeverUpscales() async throws {
        let directory = try TestImage.scratchDirectory("video-scale")
        let input = directory.appendingPathComponent("source.mp4")
        try await TestVideo.write(width: 640, height: 480, seconds: 1, to: input)

        let engine = TestVideo.engine()

        let shrunk = await engine.convert(
            input,
            settings: .init(codec: .h264, maxEdge: 320, keepAudio: false)
        )
        let smallOutput = try require(shrunk.successOutput)
        let smallInfo = try await VideoProbe.probe(smallOutput)
        try expectEqual(smallInfo.width, 320, "Breite nach dem Verkleinern")
        try expectEqual(smallInfo.height, 240, "Höhe nach dem Verkleinern")

        let untouched = await engine.convert(
            input,
            settings: .init(codec: .h264, maxEdge: 4000, keepAudio: false)
        )
        let bigOutput = try require(untouched.successOutput)
        let bigInfo = try await VideoProbe.probe(bigOutput)
        try expectEqual(bigInfo.width, 640, "640px darf nicht auf 4000px aufgeblasen werden")
    }

    static func audioIsKeptOrRemovedAsAsked() async throws {
        let directory = try TestImage.scratchDirectory("video-audio")
        let input = directory.appendingPathComponent("source.mp4")
        try await TestVideo.write(width: 320, height: 240, seconds: 1, withAudio: true, to: input)

        let engine = TestVideo.engine()

        let kept = await engine.convert(input, settings: .init(codec: .h264, keepAudio: true))
        let keptOutput = try require(kept.successOutput)
        try expect(try await TestVideo.hasAudioStream(of: keptOutput), "Tonspur muss überleben")

        let stripped = await engine.convert(input, settings: .init(codec: .h264, keepAudio: false))
        let strippedOutput = try require(stripped.successOutput)
        try expect(!(try await TestVideo.hasAudioStream(of: strippedOutput)), "Tonspur muss weg sein")
    }

    static func renamingAndDestinationApplyToVideoToo() async throws {
        let source = try TestImage.scratchDirectory("video-rename-src")
        let target = try TestImage.scratchDirectory("video-rename-dst")
        let input = source.appendingPathComponent("DSC_0001.mp4")
        try await TestVideo.write(width: 320, height: 240, seconds: 1, withAudio: false, to: input)

        let outcome = await TestVideo.engine().convert(
            input,
            settings: .init(
                codec: .h264,
                keepAudio: false,
                destinationDirectory: target,
                nameTemplate: NameTemplate("Web-{nn}")
            ),
            number: 3
        )

        let output = try require(outcome.successOutput)
        try expectEqual(output.lastPathComponent, "Web-03.mp4")
        try expectEqual(output.deletingLastPathComponent().path, target.path)
    }

    static func corruptVideoDoesNotStopTheBatch() async throws {
        let directory = try TestImage.scratchDirectory("video-batch")
        var inputs: [URL] = []
        for index in 0..<4 {
            let url = directory.appendingPathComponent("clip-\(index).mp4")
            if index == 2 {
                try TestVideo.writeCorrupt(to: url)
            } else {
                try await TestVideo.write(width: 240, height: 180, seconds: 1,
                                          withAudio: false, to: url)
            }
            inputs.append(url)
        }

        let target = try TestImage.scratchDirectory("video-batch-out")
        let runner = BatchRunner(engine: TestVideo.engine())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(codec: .h264, keepAudio: false, destinationDirectory: target)
        )

        try expectEqual(outcomes.count, 4, "Anzahl Ergebnisse")
        try expectEqual(outcomes.filter(\.isSuccess).count, 3, "drei müssen durchlaufen")
        try expect(!outcomes[2].isSuccess, "die kaputte Datei ist die, die fehlschlägt")
    }

    /// The whole reason encoding goes through a temporary file: an interrupted
    /// run must not leave a half video behind that looks like a result.
    static func cancellingLeavesNoFile() async throws {
        let directory = try TestImage.scratchDirectory("video-cancel")
        let target = try TestImage.scratchDirectory("video-cancel-out")
        let input = directory.appendingPathComponent("long.mp4")
        // Long and large enough that the encode is definitely still running
        // when the cancel arrives.
        try await TestVideo.write(width: 1280, height: 720, seconds: 60,
                                  withAudio: false, to: input)

        // Cancel once the encode has demonstrably started, not after a fixed
        // delay: a sleep races the encoder, and on a fast machine the encode
        // can finish first — which made this test flaky.
        let runner = BatchRunner(engine: TestVideo.engine())
        let trigger = CancelTrigger()
        let task = Task {
            await runner.run(
                inputs: [input],
                settings: .init(codec: .hevc, crf: 18, keepAudio: false,
                                destinationDirectory: target)
            ) { update in
                if let fraction = update.currentFraction, fraction > 0.02, fraction < 0.9 {
                    trigger.fire()
                }
            }
        }
        trigger.onFire = { task.cancel() }
        let outcomes = await task.value

        try expect(!(outcomes.first?.isSuccess ?? false), "abgebrochen ist kein Erfolg")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: target.path)
        try expectEqual(leftovers, [], "im Zielordner darf nichts liegen, auch kein Temporärrest: \(leftovers)")
    }
}

/// Fires its handler once, from whichever thread reports progress first.
final class CancelTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var pending = false
    var onFire: (() -> Void)? {
        didSet {
            lock.lock(); let run = pending && !fired; if run { fired = true }; lock.unlock()
            if run { onFire?() }
        }
    }

    func fire() {
        lock.lock()
        if fired { lock.unlock(); return }
        guard let handler = onFire else { pending = true; lock.unlock(); return }
        fired = true
        lock.unlock()
        handler()
    }
}

/// The Webflow bug: sips writes AVIF from 1024 px upwards as a tile grid that
/// many decoders cannot assemble, so Webflow showed blank previews.
enum AVIFCompatibilityTests {

    static func largeAVIFIsSingleStream() async throws {
        let directory = try TestImage.scratchDirectory("avif-grid")
        let input = directory.appendingPathComponent("wide.jpg")
        try TestImage.writeJPEG(width: 2400, height: 1600, to: input)

        let outcome = await TestSupport.engine().convert(
            input, settings: .init(target: .avif, quality: 70, maxEdge: 2000)
        )
        let output = try require(outcome.successOutput)
        let streams = try await TestVideo.streams(of: output)
        try expect(!streams.contains("Tile Grid"), "AVIF darf kein Kachelgitter sein: \(streams)")
        let size = try TestImage.pixelSize(of: output)
        try expectEqual(size.width, 2000, "Breite")
    }

    /// ffmpeg drops alpha, so transparent images must keep going through sips.
    static func transparentAVIFKeepsAlpha() async throws {
        let directory = try TestImage.scratchDirectory("avif-alpha")
        let input = directory.appendingPathComponent("cutout.png")
        try TestImage.writePNG(width: 600, height: 400, alpha: true, to: input)

        let outcome = await TestSupport.engine().convert(input, settings: .init(target: .avif, quality: 70))
        let output = try require(outcome.successOutput)
        try expect(try await ImageProbe.probe(output).hasAlpha, "Transparenz muss erhalten bleiben")
    }

    /// Documented trade-off, pinned so a change is noticed: ffmpeg cannot write
    /// EXIF into AVIF, and ImageIO refuses lossless metadata edits on AVIF
    /// ("not supported for lossless metadata modification"). Compatibility
    /// wins over metadata for a web format.
    static func avifDropsExifByDesign() async throws {
        let directory = try TestImage.scratchDirectory("avif-exif")
        let input = directory.appendingPathComponent("tagged.jpg")
        let stamp = "2026:07:28 11:22:33"
        try TestImage.writeJPEG(width: 1600, height: 1000, exifDateTimeOriginal: stamp, to: input)

        let outcome = await TestSupport.engine().convert(input, settings: .init(target: .avif, quality: 70))
        let output = try require(outcome.successOutput)
        try expectNil(TestImage.exifDateTimeOriginal(of: output),
                      "ffmpeg-AVIF trägt kein EXIF — wenn doch, Hinweis in der App anpassen")
    }

    static func crfMapping() async throws {
        try expectEqual(ConversionEngine.avifCRF(quality: 85), 13)
        try expectEqual(ConversionEngine.avifCRF(quality: 50), 30)
        try expect(ConversionEngine.avifCRF(quality: 20) > ConversionEngine.avifCRF(quality: 90),
                   "höhere Qualität heißt kleinere CRF")
    }
}

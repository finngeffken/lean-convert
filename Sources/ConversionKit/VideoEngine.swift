import Foundation

/// Encodes one video with ffmpeg.
///
/// The video counterpart to `ConversionEngine`, and like it the only place that
/// knows which tool does the work. ffmpeg is here because it is the only thing
/// that writes VP9 and AV1; measuring the file is left to AVFoundation.
public struct VideoEngine: MediaConverter, Sendable {
    public typealias Settings = VideoSettings

    /// Location of the bundled ffmpeg, `nil` when it was never fetched.
    let ffmpegURL: URL?

    public init(ffmpegURL: URL?) {
        self.ffmpegURL = ffmpegURL
    }

    public var isAvailable: Bool { ffmpegURL != nil }

    /// One encode already saturates every core, so a second in parallel makes
    /// the whole batch slower rather than faster.
    public var maxConcurrency: Int { 1 }

    /// Which of the four codecs this particular ffmpeg build can actually
    /// encode. VP9 and AV1 are build options and absent from some builds; a
    /// codec that is missing is not offered, the same way WebP is hidden
    /// without cwebp.
    public func availableCodecs() async -> [VideoCodec] {
        guard let ffmpegURL else { return [] }
        guard let result = try? await ProcessRunner.run(ffmpegURL, ["-hide_banner", "-encoders"]),
              result.exitCode == 0
        else { return [] }

        return VideoCodec.allCases.filter { result.stdout.contains($0.encoderName) }
    }

    public func convert(
        _ input: URL,
        settings: VideoSettings,
        number: Int = 1,
        reserver: NameReserver? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> ConversionOutcome {
        let fileManager = FileManager.default

        guard let ffmpegURL else {
            return .failure(input: input, reason: .toolMissing("ffmpeg"))
        }
        guard let bytesBefore = try? fileManager
            .attributesOfItem(atPath: input.path)[.size] as? Int
        else {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let info: VideoInfo
        do {
            info = try await VideoProbe.probe(input)
        } catch {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let directory = settings.destinationDirectory ?? input.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            return .failure(input: input, reason: .destinationNotWritable(directory.path))
        }

        let destination = OutputNaming.destination(
            for: input,
            format: settings.codec,
            in: settings.destinationDirectory,
            nameTemplate: settings.nameTemplate,
            number: number,
            reserver: reserver
        )

        // Encode beside the target under a temporary name and only rename on
        // success. An interrupted encode would otherwise leave a truncated
        // video sitting there looking like a result.
        let temporary = directory.appendingPathComponent(
            ".leanconvert-\(UUID().uuidString).\(settings.codec.fileExtension)"
        )

        let arguments = Self.arguments(
            input: input,
            output: temporary,
            settings: settings,
            info: info
        )

        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(ffmpegURL, arguments) { line in
                guard info.durationSeconds > 0,
                      let microseconds = Self.outTimeMicroseconds(from: line)
                else { return }
                progress(microseconds / 1_000_000 / info.durationSeconds)
            }
        } catch is CancellationError {
            Self.discard(temporary)
            return .failure(input: input, reason: .cancelled)
        } catch {
            Self.discard(temporary)
            return .failure(input: input, reason: .unreadable(error.localizedDescription))
        }

        if result.wasCancelled || Task.isCancelled {
            Self.discard(temporary)
            return .failure(input: input, reason: .cancelled)
        }

        guard result.exitCode == 0 else {
            Self.discard(temporary)
            return .failure(input: input, reason: .toolFailed(
                tool: "ffmpeg",
                exitCode: result.exitCode,
                stderr: Self.lastMeaningfulLine(of: result.stderr)
            ))
        }

        do {
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            Self.discard(temporary)
            return .failure(input: input, reason: .noOutputProduced(destination.lastPathComponent))
        }

        guard let bytesAfter = try? fileManager
            .attributesOfItem(atPath: destination.path)[.size] as? Int
        else {
            return .failure(input: input, reason: .noOutputProduced(destination.lastPathComponent))
        }

        progress(1)
        return .success(
            input: input,
            output: destination,
            bytesBefore: bytesBefore,
            bytesAfter: bytesAfter
        )
    }

    // MARK: - Arguments

    /// Public so the test suite can assert on the argument list without
    /// running an encode.
    public static func arguments(
        input: URL,
        output: URL,
        settings: VideoSettings,
        info: VideoInfo
    ) -> [String] {
        var arguments = [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.path,
        ]

        // Only ever downscale, same rule as the image side.
        if let bound = settings.maxEdge, info.longerEdge > bound,
           let size = Self.scaledSize(info: info, bound: bound) {
            arguments += ["-vf", "scale=\(size.width):\(size.height)"]
        }

        arguments += ["-c:v", settings.codec.encoderName, "-crf", String(settings.crf)]
        arguments += Self.codecArguments(settings.codec)
        arguments += Self.audioArguments(settings: settings, info: info)

        // Keep metadata, the same promise the image side makes.
        arguments += ["-map_metadata", "0"]

        if !settings.codec.isWebM {
            // Lets a browser start playing before the whole file arrived.
            arguments += ["-movflags", "+faststart"]
        }

        arguments += ["-progress", "pipe:1", "-nostats", output.path]
        return arguments
    }

    private static func codecArguments(_ codec: VideoCodec) -> [String] {
        switch codec {
        case .h264:
            ["-preset", "medium", "-pix_fmt", "yuv420p"]
        case .hevc:
            // hvc1 instead of the default hev1: without it Safari and QuickTime
            // refuse to play the result.
            ["-preset", "medium", "-pix_fmt", "yuv420p", "-tag:v", "hvc1"]
        case .vp9:
            // libvpx-vp9 only honours -crf when the bitrate is set to zero.
            ["-b:v", "0", "-row-mt", "1"]
        case .av1:
            ["-preset", "8", "-pix_fmt", "yuv420p"]
        }
    }

    /// Audio has to follow the container, not the user's wishes alone: WebM
    /// cannot hold AAC, and MP4 cannot hold the PCM audio that .mov files from
    /// cameras and screen recordings often carry. Copying is only safe when the
    /// source is already AAC in an MP4 target.
    private static func audioArguments(settings: VideoSettings, info: VideoInfo) -> [String] {
        guard settings.keepAudio, info.hasAudio else { return ["-an"] }

        if settings.codec.isWebM {
            return ["-c:a", "libopus", "-b:a", "128k"]
        }
        return info.audioIsAAC ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "160k"]
    }

    /// Scales the longer edge to `bound` and rounds both sides to even numbers,
    /// which yuv420p requires.
    public static func scaledSize(info: VideoInfo, bound: Int) -> (width: Int, height: Int)? {
        guard info.width > 0, info.height > 0, bound > 0 else { return nil }

        let scale = Double(bound) / Double(info.longerEdge)
        func even(_ value: Double) -> Int {
            let rounded = Int(value.rounded())
            return max(2, rounded - (rounded % 2))
        }
        return (even(Double(info.width) * scale), even(Double(info.height) * scale))
    }

    // MARK: - Progress and errors

    /// ffmpeg's `-progress` output is plain `key=value` lines; `out_time_us` is
    /// the one that says how far into the source it is.
    public static func outTimeMicroseconds(from line: String) -> Double? {
        guard line.hasPrefix("out_time_us=") else { return nil }
        let value = line.dropFirst("out_time_us=".count).trimmingCharacters(in: .whitespaces)
        guard let microseconds = Double(value), microseconds >= 0 else { return nil }
        return microseconds
    }

    /// ffmpeg writes pages of banner-ish detail before the actual complaint, so
    /// the last non-empty line is the useful one.
    public static func lastMeaningfulLine(of stderr: String) -> String {
        let lines = stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? ""
    }

    /// Removes the app's own temporary encode file.
    ///
    /// This is the one deliberate exception to "never delete": the file was
    /// created seconds earlier by this very call and was never shown as a
    /// result. Originals and finished outputs are never touched.
    private static func discard(_ temporary: URL) {
        try? FileManager.default.removeItem(at: temporary)
    }
}

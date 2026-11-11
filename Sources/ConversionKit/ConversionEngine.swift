import Foundation

/// Converts one file. The *only* place that decides which tool serves which
/// target format: WebP goes to `cwebp`, everything else to `sips`.
///
/// Add a format or a binary later and this file is the one that changes.
public struct ConversionEngine: MediaConverter, Sendable {
    public typealias Settings = ConversionSettings

    static let sipsURL = URL(fileURLWithPath: "/usr/bin/sips")

    /// Location of the bundled `cwebp`. `nil` when it is not available — WebP
    /// then fails with a clear reason instead of silently falling back to
    /// another format.
    let cwebpURL: URL?

    /// The bundled ffmpeg, used for AVIF. `sips` writes AVIF from 1024 px
    /// upwards as a tile grid, which Webflow and other pipelines cannot
    /// decode — they show a blank preview. ffmpeg writes a single stream.
    let ffmpegURL: URL?

    public init(cwebpURL: URL?, ffmpegURL: URL? = nil) {
        self.cwebpURL = cwebpURL
        self.ffmpegURL = ffmpegURL
    }

    /// Whether AVIF output is the widely compatible single-stream kind.
    public var writesCompatibleAVIF: Bool { ffmpegURL != nil }

    public var supportsWebP: Bool { cwebpURL != nil }

    /// Image tools are single-threaded, so the core count is the ceiling.
    public var maxConcurrency: Int { ProcessInfo.processInfo.activeProcessorCount }

    public var availableFormats: [TargetFormat] {
        TargetFormat.allCases.filter { $0 != .webp || supportsWebP }
    }

    /// `number` is this file's position in the batch, starting at 1. It feeds
    /// the `{n}` token of the rename pattern and is irrelevant otherwise.
    ///
    /// `reserver` is shared across a batch so parallel files cannot claim the
    /// same output name. Omitting it is correct for a single conversion.
    public func convert(
        _ input: URL,
        settings: ConversionSettings,
        number: Int = 1,
        reserver: NameReserver? = nil,
        // Images finish in fractions of a second — there is no meaningful
        // progress inside one, so this is accepted and ignored.
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> ConversionOutcome {
        let fileManager = FileManager.default

        guard let bytesBefore = try? fileManager
            .attributesOfItem(atPath: input.path)[.size] as? Int
        else {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let info: ImageInfo
        do {
            info = try await ImageProbe.probe(input)
        } catch {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let directory = settings.destinationDirectory ?? input.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            return .failure(input: input, reason: .destinationNotWritable(directory.path))
        }

        // Only ever downscale. `sips -Z` would happily interpolate a small
        // image up to the bound, which nobody wants.
        let resizeTo: Int? = settings.maxEdge.flatMap { bound in
            info.longerEdge > bound ? bound : nil
        }

        let destination = OutputNaming.destination(
            for: input,
            format: settings.target,
            in: settings.destinationDirectory,
            nameTemplate: settings.nameTemplate,
            number: number,
            reserver: reserver
        )

        // Transparent images stay with sips: ffmpeg's AV1 encoder silently
        // drops the alpha channel, which would turn a cut-out into a box.
        let useFFmpegAVIF = settings.target == .avif && ffmpegURL != nil && !info.hasAlpha

        let result: ProcessResult
        do {
            if settings.target == .webp {
                result = try await runCwebp(input, destination, settings, info, resizeTo)
            } else if useFFmpegAVIF {
                result = try await runFFmpegAVIF(input, destination, settings, info, resizeTo)
            } else {
                result = try await runSips(input, destination, settings, resizeTo)
            }
        } catch let reason as FailureReason {
            return .failure(input: input, reason: reason)
        } catch {
            return .failure(input: input, reason: .unreadable(error.localizedDescription))
        }

        let toolName = settings.target == .webp ? "cwebp" : (useFFmpegAVIF ? "ffmpeg" : "sips")
        guard result.exitCode == 0 else {
            return .failure(input: input, reason: .toolFailed(
                tool: toolName,
                exitCode: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        guard let bytesAfter = try? fileManager
            .attributesOfItem(atPath: destination.path)[.size] as? Int
        else {
            return .failure(input: input, reason: .noOutputProduced(destination.lastPathComponent))
        }

        return .success(
            input: input,
            output: destination,
            bytesBefore: bytesBefore,
            bytesAfter: bytesAfter
        )
    }

    // MARK: - Tools

    /// One sips invocation handles format, quality and resize together.
    /// Numeric `formatOptions` is verified to work for JPEG and AVIF alike;
    /// the keyword form (`best`) does not, so it is not used.
    private func runSips(
        _ input: URL,
        _ destination: URL,
        _ settings: ConversionSettings,
        _ resizeTo: Int?
    ) async throws -> ProcessResult {
        var arguments = ["-s", "format", settings.target.sipsFormat]

        if settings.target.supportsQuality {
            arguments += ["-s", "formatOptions", String(settings.quality)]
        }
        if let resizeTo {
            arguments += ["-Z", String(resizeTo)]
        }
        arguments += [input.path, "--out", destination.path]

        return try await ProcessRunner.run(Self.sipsURL, arguments)
    }

    /// Single-stream AVIF via libaom. Drops EXIF: ffmpeg cannot write it into
    /// AVIF and ImageIO refuses lossless metadata edits on AVIF — a deliberate
    /// trade of metadata for compatibility in a web format.
    /// The 1...99 quality scale maps onto CRF
    /// (lower is better): 85 → 13, 65 → 23, 50 → 30.
    private func runFFmpegAVIF(
        _ input: URL,
        _ destination: URL,
        _ settings: ConversionSettings,
        _ info: ImageInfo,
        _ resizeTo: Int?
    ) async throws -> ProcessResult {
        guard let ffmpegURL else { throw FailureReason.toolMissing("ffmpeg") }

        let scale: String
        if let resizeTo {
            scale = info.width >= info.height ? "scale=\(resizeTo):-2" : "scale=-2:\(resizeTo)"
        } else {
            // yuv420p needs even dimensions.
            scale = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        }

        let arguments = [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.path,
            "-vf", scale,
            "-c:v", "libaom-av1", "-still-picture", "1",
            "-crf", String(Self.avifCRF(quality: settings.quality)),
            "-cpu-used", "6",
            "-pix_fmt", "yuv420p",
            "-map_metadata", "0",
            destination.path,
        ]
        return try await ProcessRunner.run(ffmpegURL, arguments)
    }

    public static func avifCRF(quality: Int) -> Int {
        min(63, max(0, Int((55 - Double(quality) * 0.5).rounded())))
    }

    /// `-metadata all` is not optional: cwebp strips EXIF by default, and this
    /// app promises to keep it.
    private func runCwebp(
        _ input: URL,
        _ destination: URL,
        _ settings: ConversionSettings,
        _ info: ImageInfo,
        _ resizeTo: Int?
    ) async throws -> ProcessResult {
        guard let cwebpURL else {
            throw FailureReason.toolMissing("cwebp")
        }

        var arguments = ["-q", String(settings.quality), "-metadata", "all"]

        if let resizeTo {
            // A zero on one axis tells cwebp to derive it from the aspect ratio.
            arguments += info.width >= info.height
                ? ["-resize", String(resizeTo), "0"]
                : ["-resize", "0", String(resizeTo)]
        }
        arguments += [input.path, "-o", destination.path]

        return try await ProcessRunner.run(cwebpURL, arguments)
    }
}

extension FailureReason: Error {}

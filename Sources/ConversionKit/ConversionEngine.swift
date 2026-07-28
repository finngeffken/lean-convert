import Foundation

/// Converts one file. The *only* place that decides which tool serves which
/// target format: WebP goes to `cwebp`, everything else to `sips`.
///
/// Add a format or a binary later and this file is the one that changes.
public struct ConversionEngine: Sendable {
    static let sipsURL = URL(fileURLWithPath: "/usr/bin/sips")

    /// Location of the bundled `cwebp`. `nil` when it is not available — WebP
    /// then fails with a clear reason instead of silently falling back to
    /// another format.
    let cwebpURL: URL?

    public init(cwebpURL: URL?) {
        self.cwebpURL = cwebpURL
    }

    public var supportsWebP: Bool { cwebpURL != nil }

    public var availableFormats: [TargetFormat] {
        TargetFormat.allCases.filter { $0 != .webp || supportsWebP }
    }

    public func convert(_ input: URL, settings: ConversionSettings) -> ConversionOutcome {
        let fileManager = FileManager.default

        guard let bytesBefore = try? fileManager
            .attributesOfItem(atPath: input.path)[.size] as? Int
        else {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let info: ImageInfo
        do {
            info = try ImageProbe.probe(input)
        } catch {
            return .failure(input: input, reason: .unreadable(input.lastPathComponent))
        }

        let directory = input.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: directory.path) else {
            return .failure(input: input, reason: .destinationNotWritable(directory.path))
        }

        // Only ever downscale. `sips -Z` would happily interpolate a small
        // image up to the bound, which nobody wants.
        let resizeTo: Int? = settings.maxEdge.flatMap { bound in
            info.longerEdge > bound ? bound : nil
        }

        let destination = OutputNaming.destination(for: input, format: settings.target)

        let result: ProcessResult
        do {
            result = settings.target == .webp
                ? try runCwebp(input, destination, settings, info, resizeTo)
                : try runSips(input, destination, settings, resizeTo)
        } catch let reason as FailureReason {
            return .failure(input: input, reason: reason)
        } catch {
            return .failure(input: input, reason: .unreadable(error.localizedDescription))
        }

        let toolName = settings.target == .webp ? "cwebp" : "sips"
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
    ) throws -> ProcessResult {
        var arguments = ["-s", "format", settings.target.sipsFormat]

        if settings.target.supportsQuality {
            arguments += ["-s", "formatOptions", String(settings.quality)]
        }
        if let resizeTo {
            arguments += ["-Z", String(resizeTo)]
        }
        arguments += [input.path, "--out", destination.path]

        return try ProcessRunner.run(Self.sipsURL, arguments)
    }

    /// `-metadata all` is not optional: cwebp strips EXIF by default, and this
    /// app promises to keep it.
    private func runCwebp(
        _ input: URL,
        _ destination: URL,
        _ settings: ConversionSettings,
        _ info: ImageInfo,
        _ resizeTo: Int?
    ) throws -> ProcessResult {
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

        return try ProcessRunner.run(cwebpURL, arguments)
    }
}

extension FailureReason: Error {}

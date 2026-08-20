import Foundation
import ConversionKit

/// Video fixtures are generated at test time with ffmpeg's own synthetic
/// sources — no binaries in the repository, and the fixture always matches what
/// the test claims about it.
enum TestVideo {
    /// The bundled binary does not exist in a test context, so tests look for
    /// it in the repository. All video tests skip when it is absent.
    static let ffmpegURL: URL? = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidate = repoRoot.appendingPathComponent("Resources/ffmpeg")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }()

    static var isAvailable: Bool { ffmpegURL != nil }

    static func engine() -> VideoEngine {
        VideoEngine(ffmpegURL: ffmpegURL)
    }

    /// Writes a synthetic clip. `withAudio` adds a sine tone so the audio
    /// options have something to act on.
    static func write(
        width: Int,
        height: Int,
        seconds: Double,
        withAudio: Bool = true,
        to url: URL
    ) async throws {
        guard let ffmpegURL else { throw TestVideoError.ffmpegMissing }

        var arguments = [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "testsrc=size=\(width)x\(height):rate=25",
        ]
        if withAudio {
            arguments += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100"]
        }
        arguments += [
            "-t", String(seconds),
            "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
        ]
        arguments += withAudio ? ["-c:a", "aac", "-shortest"] : ["-an"]
        arguments += [url.path]

        let result = try await ProcessRunnerProbe.run(ffmpegURL, arguments)
        guard result.exitCode == 0 else {
            throw TestVideoError.generationFailed(result.stderr)
        }
    }

    static func writeCorrupt(to url: URL) throws {
        try Data("this is not a video".utf8).write(to: url)
    }

    // MARK: - Reading results back

    /// Asks ffmpeg what is actually in the file. AVFoundation cannot open WebM
    /// at all, so it is unusable for verifying the VP9 path.
    static func streams(of url: URL) async throws -> String {
        guard let ffmpegURL else { throw TestVideoError.ffmpegMissing }
        let result = try await ProcessRunnerProbe.run(
            ffmpegURL, ["-hide_banner", "-i", url.path]
        )
        // `ffmpeg -i` without an output exits non-zero by design; the stream
        // description is on stderr either way.
        return result.stderr
    }

    static func videoCodecName(of url: URL) async throws -> String? {
        let text = try await streams(of: url)
        for line in text.split(separator: "\n") where line.contains("Stream") && line.contains("Video:") {
            guard let range = line.range(of: "Video: ") else { continue }
            let rest = line[range.upperBound...]
            return String(rest.prefix { $0.isLetter || $0.isNumber }).lowercased()
        }
        return nil
    }

    static func hasAudioStream(of url: URL) async throws -> Bool {
        let text = try await streams(of: url)
        return text.contains("Audio:")
    }

    enum TestVideoError: Error {
        case ffmpegMissing
        case generationFailed(String)
    }
}

/// The suite lives outside ConversionKit, so it cannot use the internal
/// ProcessRunner. This is the same idea, kept deliberately dumb.
enum ProcessRunnerProbe {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ executable: URL, _ arguments: [String]) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let box = DataBox()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { box.appendOut(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { box.appendErr(chunk) }
        }

        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        box.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
        box.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

        return Result(exitCode: code, stdout: box.outText, stderr: box.errText)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
        func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
        var outText: String { lock.lock(); defer { lock.unlock() }; return String(data: out, encoding: .utf8) ?? "" }
        var errText: String { lock.lock(); defer { lock.unlock() }; return String(data: err, encoding: .utf8) ?? "" }
    }
}

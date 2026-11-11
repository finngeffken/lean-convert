import Foundation
import ConversionKit

struct ToolOutcome {
    let text: String
    let isError: Bool

    static func json(_ object: Any) -> ToolOutcome {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return ToolOutcome(text: String(data: data, encoding: .utf8) ?? "{}", isError: false)
    }

    static func failure(_ message: String) -> ToolOutcome {
        ToolOutcome(text: message, isError: true)
    }
}

/// The three tools Claude sees. Everything here goes through the same
/// engines as the app, so the rules are identical: never overwrite, only
/// downscale, one failing file never stops the rest.
struct Tools {
    let images: ConversionEngine
    let videos: VideoEngine

    static let serverInstructions = """
    Lean Convert converts and compresses images and videos locally on this Mac. \
    Files are never uploaded and never overwritten: outputs go next to the original \
    (or into output_dir) and get a numeric suffix if the name is taken. \
    Call inspect_media first when you need dimensions, alpha or duration to choose settings.
    """

    static var definitions: [[String: Any]] {
        [
            [
                "name": "convert_images",
                "description": """
                Convert and/or downscale images (HEIC, JPEG, PNG, WebP, TIFF, …) to JPEG, PNG, WebP or AVIF. \
                Accepts files and folders. Returns per-file sizes before/after. \
                quality: 1–100, higher is better (ignored for PNG; AVIF tops out at 99). \
                max_edge only ever downscales — smaller images keep their size. \
                AVIF is written single-stream (Webflow-compatible) and drops EXIF; transparent images keep alpha. \
                For the web, AVIF/WebP at quality 60–75 with max_edge ~2000 is a good default.
                """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paths": ["type": "array", "items": ["type": "string"], "description": "Absolute paths to image files or folders. ~ is expanded."],
                        "format": ["type": "string", "enum": ["jpeg", "png", "webp", "avif"]],
                        "quality": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Default 85."],
                        "max_edge": ["type": "integer", "minimum": 1, "description": "Longest side in px; omit to keep size."],
                        "output_dir": ["type": "string", "description": "Folder for outputs; created if missing. Default: next to each original."],
                        "rename_pattern": ["type": "string", "description": "Optional. Tokens: {name} original name, {n}/{nn}/{nnn} running number with zero padding. Example: \"website-{nn}\"."],
                        "recursive": ["type": "boolean", "description": "Descend into subfolders. Default false."],
                    ],
                    "required": ["paths", "format"],
                ] as [String: Any],
            ],
            [
                "name": "convert_videos",
                "description": """
                Compress/transcode videos with ffmpeg to H.264, HEVC, AV1 (all .mp4) or VP9 (.webm). \
                Runs one file at a time; long or AV1/VP9 encodes can take minutes. \
                crf: lower is better quality and bigger files (h264/hevc 0–51, vp9/av1 0–63); omit for the codec default. \
                max_edge only ever downscales. Metadata is kept; audio is kept unless keep_audio is false.
                """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paths": ["type": "array", "items": ["type": "string"], "description": "Absolute paths to video files or folders."],
                        "codec": ["type": "string", "enum": ["h264", "hevc", "vp9", "av1"]],
                        "crf": ["type": "integer", "minimum": 0, "maximum": 63],
                        "max_edge": ["type": "integer", "minimum": 2],
                        "keep_audio": ["type": "boolean", "description": "Default true."],
                        "output_dir": ["type": "string"],
                        "rename_pattern": ["type": "string"],
                        "recursive": ["type": "boolean"],
                    ],
                    "required": ["paths", "codec"],
                ] as [String: Any],
            ],
            [
                "name": "inspect_media",
                "description": "Report size, dimensions and alpha (images) or duration and audio (videos) without changing anything.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "paths": ["type": "array", "items": ["type": "string"]],
                        "recursive": ["type": "boolean"],
                    ],
                    "required": ["paths"],
                ] as [String: Any],
            ],
        ]
    }

    func call(_ name: String, arguments: [String: Any]) async -> ToolOutcome {
        switch name {
        case "convert_images": return await convertImages(arguments)
        case "convert_videos": return await convertVideos(arguments)
        case "inspect_media": return await inspect(arguments)
        default: return .failure("Unknown tool: \(name)")
        }
    }

    // MARK: - convert_images

    private func convertImages(_ args: [String: Any]) async -> ToolOutcome {
        guard let format = (args["format"] as? String).flatMap(TargetFormat.init(rawValue:)) else {
            return .failure("format must be one of: jpeg, png, webp, avif")
        }
        if format == .webp && !images.supportsWebP {
            return .failure("WebP is unavailable: cwebp is missing from the app bundle.")
        }
        let collected = Self.collect(args, accepts: InputValidator.isSupportedImage)
        guard !collected.files.isEmpty else {
            return .failure("No supported images found in the given paths. Skipped: \(collected.skipped)")
        }
        let destination: URL?
        switch Self.prepareOutputDirectory(args) {
        case .failure(let message): return .failure(message)
        case .success(let url): destination = url
        }

        let settings = ConversionSettings(
            target: format,
            quality: Self.int(args["quality"]) ?? 85,
            maxEdge: Self.int(args["max_edge"]),
            destinationDirectory: destination,
            nameTemplate: NameTemplate(args["rename_pattern"] as? String ?? "")
        )
        let outcomes = await BatchRunner(engine: images).run(inputs: collected.files, settings: settings)
        return .json(Self.report(outcomes, skipped: collected.skipped))
    }

    // MARK: - convert_videos

    private func convertVideos(_ args: [String: Any]) async -> ToolOutcome {
        guard videos.isAvailable else {
            return .failure("Video is unavailable: ffmpeg is missing from the app bundle.")
        }
        guard let codec = (args["codec"] as? String).flatMap(VideoCodec.init(rawValue:)) else {
            return .failure("codec must be one of: h264, hevc, vp9, av1")
        }
        let collected = Self.collect(args, accepts: InputValidator.isSupportedVideo)
        guard !collected.files.isEmpty else {
            return .failure("No supported videos found in the given paths. Skipped: \(collected.skipped)")
        }
        let destination: URL?
        switch Self.prepareOutputDirectory(args) {
        case .failure(let message): return .failure(message)
        case .success(let url): destination = url
        }

        let settings = VideoSettings(
            codec: codec,
            crf: Self.int(args["crf"]),
            maxEdge: Self.int(args["max_edge"]),
            keepAudio: args["keep_audio"] as? Bool ?? true,
            destinationDirectory: destination,
            nameTemplate: NameTemplate(args["rename_pattern"] as? String ?? "")
        )
        let outcomes = await BatchRunner(engine: videos).run(inputs: collected.files, settings: settings)
        return .json(Self.report(outcomes, skipped: collected.skipped))
    }

    // MARK: - inspect_media

    private func inspect(_ args: [String: Any]) async -> ToolOutcome {
        let collected = Self.collect(args) { InputValidator.isSupportedImage($0) || InputValidator.isSupportedVideo($0) }
        var entries: [[String: Any]] = []
        for url in collected.files {
            var entry: [String: Any] = ["path": url.path, "bytes": Self.size(url)]
            if InputValidator.isSupportedVideo(url) {
                entry["kind"] = "video"
                if let info = try? await VideoProbe.probe(url) {
                    entry["width"] = info.width
                    entry["height"] = info.height
                    entry["duration_seconds"] = (info.durationSeconds * 10).rounded() / 10
                    entry["has_audio"] = info.hasAudio
                } else {
                    entry["error"] = "unreadable"
                }
            } else {
                entry["kind"] = "image"
                entry["type"] = url.pathExtension.lowercased()
                if let info = try? await ImageProbe.probe(url) {
                    entry["width"] = info.width
                    entry["height"] = info.height
                    entry["has_alpha"] = info.hasAlpha
                } else {
                    entry["error"] = "unreadable"
                }
            }
            entries.append(entry)
        }
        return .json(["files": entries, "skipped": collected.skipped])
    }

    // MARK: - Helpers

    static func report(_ outcomes: [ConversionOutcome], skipped: [String]) -> [String: Any] {
        var files: [[String: Any]] = []
        var before = 0, after = 0, converted = 0, failed = 0
        for outcome in outcomes {
            switch outcome {
            case .success(let input, let output, let b, let a):
                converted += 1; before += b; after += a
                files.append([
                    "input": input.path, "output": output.path,
                    "bytes_before": b, "bytes_after": a,
                    "saved_percent": b > 0 ? Int((Double(b - a) / Double(b) * 100).rounded()) : 0,
                ])
            case .failure(let input, let reason):
                failed += 1
                files.append(["input": input.path, "error": reason.message])
            }
        }
        return [
            "summary": [
                "converted": converted, "failed": failed,
                "bytes_before": before, "bytes_after": after,
                "saved_percent": before > 0 ? Int((Double(before - after) / Double(before) * 100).rounded()) : 0,
            ],
            "files": files,
            "skipped": skipped,
        ]
    }

    /// Expands files and folders into the files a tool accepts; everything
    /// else is reported back rather than silently ignored.
    static func collect(_ args: [String: Any], accepts: (URL) -> Bool) -> (files: [URL], skipped: [String]) {
        let raw = args["paths"] as? [String] ?? (args["paths"] as? String).map { [$0] } ?? []
        let recursive = args["recursive"] as? Bool ?? false
        let fileManager = FileManager.default
        var files: [URL] = [], skipped: [String] = [], seen = Set<String>()

        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            if accepts(url) { files.append(url) } else { skipped.append(url.path) }
        }

        for path in raw {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                skipped.append("\(url.path) (not found)")
                continue
            }
            guard isDirectory.boolValue else { add(url); continue }

            let options: FileManager.DirectoryEnumerationOptions = recursive
                ? [.skipsHiddenFiles]
                : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            let children = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
            let sorted = (children?.allObjects as? [URL] ?? []).sorted { $0.path < $1.path }
            for child in sorted where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                add(child)
            }
        }
        return (files, skipped)
    }

    enum Prepared { case success(URL?), failure(String) }

    static func prepareOutputDirectory(_ args: [String: Any]) -> Prepared {
        guard let raw = args["output_dir"] as? String, !raw.isEmpty else { return .success(nil) }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return .success(url)
        } catch {
            return .failure("Cannot create output_dir \(url.path): \(error.localizedDescription)")
        }
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    static func size(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

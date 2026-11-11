import Foundation
import ConversionKit
import LeanConvertMCPCore

// stdio transport for the Lean Convert MCP server: one JSON-RPC message per
// line on stdin, one per line on stdout. Anything else must go to stderr —
// a stray print on stdout corrupts the protocol.

/// Finds a bundled tool: next to this executable inside the app bundle
/// (Contents/MacOS → Contents/Resources), or via an environment override for
/// development builds.
func bundledTool(_ name: String, env: String) -> URL? {
    if let override = ProcessInfo.processInfo.environment[env] {
        return URL(fileURLWithPath: override)
    }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidate = executable.deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/\(name)")
    return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
}

let ffmpeg = bundledTool("ffmpeg", env: "LEANCONVERT_FFMPEG")
let server = MCPServer(
    images: ConversionEngine(cwebpURL: bundledTool("cwebp", env: "LEANCONVERT_CWEBP"), ffmpegURL: ffmpeg),
    videos: VideoEngine(ffmpegURL: ffmpeg)
)

final class Output: @unchecked Sendable {
    private let lock = NSLock()
    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        lock.lock()
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        lock.unlock()
    }
}

let output = Output()
let inFlight = DispatchGroup()

// Requests are handled concurrently so a long video encode does not block a
// ping; the reader runs on its own thread and the main thread stays free.
Thread {
    while let line = readLine(strippingNewline: true) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output.send(MCPServer.error(id: nil, code: -32700, "Parse error"))
            continue
        }
        inFlight.enter()
        Task.detached {
            if let response = await server.handle(message) { output.send(response) }
            inFlight.leave()
        }
    }
    // Client closed stdin: finish what is running, then exit.
    inFlight.notify(queue: .main) { exit(0) }
}.start()

dispatchMain()

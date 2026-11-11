import Foundation
import ConversionKit

/// A Model Context Protocol server over JSON-RPC 2.0.
///
/// Transport-agnostic: `handle` takes one decoded message and returns the
/// response, or `nil` for notifications. The stdio loop lives in the
/// `leanconvert-mcp` executable; keeping it out of here makes the protocol and
/// the tools testable without spawning a process.
public final class MCPServer: @unchecked Sendable {
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let tools: Tools

    public init(images: ConversionEngine, videos: VideoEngine) {
        self.tools = Tools(images: images, videos: videos)
    }

    public func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return id == nil ? nil : Self.error(id: id, code: -32600, "Invalid request")
        }
        // Notifications carry no id and get no response.
        guard let id else { return nil }

        switch method {
        case "initialize":
            let requested = (message["params"] as? [String: Any])?["protocolVersion"] as? String
            let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
                ?? Self.supportedProtocolVersions[0]
            return Self.result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "lean-convert", "version": "1.1"],
                "instructions": Tools.serverInstructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Tools.definitions])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else {
                return Self.error(id: id, code: -32602, "tools/call needs a tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = await tools.call(name, arguments: arguments)
            return Self.result(id: id, [
                "content": [["type": "text", "text": outcome.text]],
                "isError": outcome.isError,
            ])
        default:
            return Self.error(id: id, code: -32601, "Method not found: \(method)")
        }
    }

    static func result(id: Any?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    public static func error(id: Any?, code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

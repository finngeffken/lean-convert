import Foundation
import ConversionKit
import LeanConvertMCPCore

enum MCPTests {
    static func server() -> MCPServer {
        MCPServer(
            images: ConversionEngine(cwebpURL: TestSupport.cwebpURL, ffmpegURL: TestVideo.ffmpegURL),
            videos: TestVideo.engine()
        )
    }

    static func call(_ name: String, _ arguments: [String: Any]) async throws -> (text: String, isError: Bool, json: [String: Any]?) {
        let response = await server().handle([
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ])
        let result = try require(response?["result"] as? [String: Any], "result")
        let content = try require(result["content"] as? [[String: Any]], "content")
        let text = try require(content.first?["text"] as? String, "text")
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        return (text, result["isError"] as? Bool ?? false, json)
    }

    static func initializeNegotiatesVersion() async throws {
        let response = await server().handle([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]],
        ])
        let result = try require(response?["result"] as? [String: Any])
        try expectEqual(result["protocolVersion"] as? String, "2025-03-26", "bekannte Version wird gespiegelt")
        try expect((result["capabilities"] as? [String: Any])?["tools"] != nil, "tools-Fähigkeit gemeldet")
    }

    static func notificationsGetNoResponse() async throws {
        let response = await server().handle(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try expect(response == nil, "Benachrichtigungen bekommen keine Antwort")
    }

    static func unknownMethodIsAnError() async throws {
        let response = await server().handle(["jsonrpc": "2.0", "id": 2, "method": "resources/list"])
        let error = try require(response?["error"] as? [String: Any])
        try expectEqual(error["code"] as? Int, -32601)
    }

    static func listsThreeTools() async throws {
        let response = await server().handle(["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        let tools = try require((response?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }.sorted()
        try expectEqual(names, ["convert_images", "convert_videos", "inspect_media"])
        // The whole response must survive JSON encoding, or the client never sees it.
        try expect(JSONSerialization.isValidJSONObject(response!), "tools/list ist gültiges JSON")
    }

    static func convertsAFolderIntoOutputDir() async throws {
        let source = try TestImage.scratchDirectory("mcp-src")
        for i in 0..<3 { try TestImage.writePNG(width: 1600, height: 1000, to: source.appendingPathComponent("p\(i).png")) }
        try Data("notes".utf8).write(to: source.appendingPathComponent("readme.txt"))
        let target = source.appendingPathComponent("out/nested")  // does not exist yet

        let (_, isError, json) = try await call("convert_images", [
            "paths": [source.path], "format": "webp", "quality": 70, "max_edge": 800,
            "output_dir": target.path, "rename_pattern": "web-{nn}",
        ])
        try expect(!isError, "kein Fehler")
        let summary = try require(json?["summary"] as? [String: Any])
        try expectEqual(summary["converted"] as? Int, 3, "drei Bilder")
        try expectEqual((json?["skipped"] as? [String])?.count, 1, "die Textdatei wird gemeldet, nicht verschluckt")
        let outputs = (json?["files"] as? [[String: Any]] ?? []).compactMap { $0["output"] as? String }
        try expectEqual(outputs.map { URL(fileURLWithPath: $0).lastPathComponent }, ["web-01.webp", "web-02.webp", "web-03.webp"])
        try expectEqual(try TestImage.pixelSize(of: URL(fileURLWithPath: outputs[0])).width, 800, "max_edge wirkt")
    }

    static func badFormatIsAToolError() async throws {
        let dir = try TestImage.scratchDirectory("mcp-bad")
        try TestImage.writePNG(width: 10, height: 10, to: dir.appendingPathComponent("a.png"))
        let (text, isError, _) = try await call("convert_images", ["paths": [dir.path], "format": "gif"])
        try expect(isError, "ungültiges Format ist ein Werkzeugfehler")
        try expect(text.contains("jpeg"), "Fehlermeldung nennt die gültigen Formate")
    }

    static func missingPathsAreReported() async throws {
        let (_, isError, _) = try await call("convert_images", ["paths": ["/nicht/vorhanden.png"], "format": "jpeg"])
        try expect(isError, "nichts gefunden ist ein Fehler, kein stiller Erfolg")
    }

    static func inspectReportsImageFacts() async throws {
        let dir = try TestImage.scratchDirectory("mcp-inspect")
        let file = dir.appendingPathComponent("cut.png")
        try TestImage.writePNG(width: 640, height: 480, alpha: true, to: file)
        let (_, isError, json) = try await call("inspect_media", ["paths": [file.path]])
        try expect(!isError, "kein Fehler")
        let entry = try require((json?["files"] as? [[String: Any]])?.first)
        try expectEqual(entry["width"] as? Int, 640)
        try expectEqual(entry["has_alpha"] as? Bool, true)
    }
}

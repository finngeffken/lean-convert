import Foundation

public struct ImageInfo: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool

    public var longerEdge: Int { max(width, height) }
}

/// Reads dimensions and alpha before converting.
///
/// This step is not optional decoration: `sips -Z` *upscales* images smaller
/// than the given bound, which is both unwanted and lossy. Knowing the real
/// size lets the engine drop the resize argument instead.
public enum ImageProbe {
    static let sipsURL = URL(fileURLWithPath: "/usr/bin/sips")

    public static func probe(_ url: URL) async throws -> ImageInfo {
        let result = try await ProcessRunner.run(
            sipsURL,
            ["-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", url.path]
        )

        guard result.exitCode == 0 else {
            throw ProbeError.failed(result.stderr)
        }

        let fields = parseFields(result.stdout)

        guard let width = fields["pixelWidth"].flatMap(Int.init),
              let height = fields["pixelHeight"].flatMap(Int.init)
        else {
            throw ProbeError.failed("Keine Bildmaße in der sips-Ausgabe")
        }

        return ImageInfo(
            width: width,
            height: height,
            hasAlpha: fields["hasAlpha"] == "yes"
        )
    }

    /// sips prints the path on the first line, then `  key: value` per property.
    ///
    /// Public so the test suite can exercise the parsing on fixed input rather
    /// than only through a real `sips` call.
    public static func parseFields(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }

    enum ProbeError: Error {
        case failed(String)
    }
}

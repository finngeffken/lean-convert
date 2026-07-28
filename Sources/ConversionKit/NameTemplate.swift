import Foundation

/// A renaming pattern for output files.
///
/// Tokens:
/// - `{name}` — the original base name, without extension
/// - `{n}`, `{nn}`, `{nnn}`, … — position in the batch, zero-padded to the
///   number of `n`s, so `{nnn}` yields `001`
///
/// An empty pattern keeps the original name. Everything outside a token is
/// taken literally, which is what makes `AM-Kalender-{nn}` work.
public struct NameTemplate: Sendable, Equatable {
    public static let keepOriginal = NameTemplate("")

    private let pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern.trimmingCharacters(in: .whitespaces)
    }

    public var isEmpty: Bool { pattern.isEmpty }

    /// Resolves the pattern into a base name (no extension).
    ///
    /// Falls back to the original name if the pattern resolves to nothing
    /// usable — an empty or slash-only pattern must not produce a nameless file.
    public func baseName(for input: URL, number: Int) -> String {
        let original = input.deletingPathExtension().lastPathComponent
        guard !pattern.isEmpty else { return original }

        let substituted = Self.substitute(pattern, original: original, number: number)
        let sanitized = Self.sanitize(substituted)
        return sanitized.isEmpty ? original : sanitized
    }

    /// Full output filename including extension — used for the live preview.
    public func previewFilename(
        for input: URL,
        number: Int,
        format: TargetFormat
    ) -> String {
        "\(baseName(for: input, number: number)).\(format.fileExtension)"
    }

    // MARK: - Substitution

    /// Hand-rolled scan rather than a regex: the grammar is two tokens wide,
    /// and this keeps the padding rule (`{nnn}` → three digits) obvious.
    private static func substitute(_ pattern: String, original: String, number: Int) -> String {
        var result = ""
        var remainder = Substring(pattern)

        while let open = remainder.firstIndex(of: "{") {
            result += remainder[remainder.startIndex..<open]

            let afterOpen = remainder.index(after: open)
            guard let close = remainder[afterOpen...].firstIndex(of: "}") else {
                // Unclosed brace: take the rest literally.
                result += remainder[open...]
                return result
            }

            let token = remainder[afterOpen..<close]
            if token == "name" {
                result += original
            } else if !token.isEmpty && token.allSatisfy({ $0 == "n" }) {
                result += String(format: "%0\(token.count)d", number)
            } else {
                // Unknown token stays as typed, so a typo is visible in the
                // preview instead of silently vanishing.
                result += remainder[open...close]
            }

            remainder = remainder[remainder.index(after: close)...]
        }

        result += remainder
        return result
    }

    /// Strips what cannot appear in a filename. `/` and `:` are the two
    /// characters macOS refuses; a leading dot would hide the file.
    private static func sanitize(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)

        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned
    }
}

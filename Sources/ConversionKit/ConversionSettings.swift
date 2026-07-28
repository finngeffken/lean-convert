import Foundation

/// Everything the engine needs to know about *how* to convert.
///
/// Metadata preservation is deliberately absent: it is a fixed rule, not a
/// setting. `cwebp` discards EXIF unless told otherwise, so the engine always
/// tells it otherwise.
public struct ConversionSettings: Sendable, Equatable {
    public var target: TargetFormat
    /// 1...100. Ignored for formats where `supportsQuality` is false.
    public var quality: Int
    /// Longer edge in pixels. `nil` means no resizing.
    public var maxEdge: Int?
    /// Where outputs go. `nil` means next to each original — the default.
    public var destinationDirectory: URL?
    /// How outputs are named. Empty keeps the original name.
    public var nameTemplate: NameTemplate

    public init(
        target: TargetFormat,
        quality: Int = 85,
        maxEdge: Int? = nil,
        destinationDirectory: URL? = nil,
        nameTemplate: NameTemplate = .keepOriginal
    ) {
        self.target = target
        self.quality = min(100, max(1, quality))
        self.maxEdge = maxEdge
        self.destinationDirectory = destinationDirectory
        self.nameTemplate = nameTemplate
    }
}

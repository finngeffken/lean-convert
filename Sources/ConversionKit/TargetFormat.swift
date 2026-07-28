import Foundation

/// A format ImageDrop can write.
///
/// Which tool serves which format is decided in `ConversionEngine` — not here,
/// and not in the UI.
public enum TargetFormat: String, CaseIterable, Sendable, Identifiable {
    case jpeg
    case png
    case webp
    case avif

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        case .avif: "AVIF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        case .avif: "avif"
        }
    }

    /// PNG is lossless — a quality slider would be meaningless.
    public var supportsQuality: Bool {
        self != .png
    }

    /// Format token understood by `sips -s format`. Unused for `.webp`,
    /// which `cwebp` handles instead.
    var sipsFormat: String {
        switch self {
        case .jpeg: "jpeg"
        case .png: "png"
        case .avif: "avif"
        case .webp: "webp"
        }
    }

    /// Formats that keep an alpha channel. Steers the HEIC preselection.
    public var preservesAlpha: Bool {
        switch self {
        case .png, .webp, .avif: true
        case .jpeg: false
        }
    }
}

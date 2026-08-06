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

    /// Highest quality the underlying tool actually accepts.
    ///
    /// `sips` refuses to write AVIF at `formatOptions 100` — verified to fail
    /// with "Error 13: an unknown error occurred" at any image size, while 99
    /// and below work. JPEG, PNG and HEIC take 100 fine, and so does `cwebp`.
    public var maxQuality: Int {
        self == .avif ? 99 : 100
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

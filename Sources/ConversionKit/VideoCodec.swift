import Foundation

/// A codec Lean Convert can encode to.
///
/// Like `TargetFormat` for images, this is the single place a codec is defined:
/// container, extension, ffmpeg encoder name and the CRF range all live here.
public enum VideoCodec: String, CaseIterable, Sendable, Identifiable {
    case h264
    case hevc
    case vp9
    case av1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .vp9: "VP9"
        case .av1: "AV1"
        }
    }

    /// The container follows from the codec and is not a separate setting.
    public var fileExtension: String {
        self == .vp9 ? "webm" : "mp4"
    }

    var isWebM: Bool { fileExtension == "webm" }

    var encoderName: String {
        switch self {
        case .h264: "libx264"
        case .hevc: "libx265"
        case .vp9: "libvpx-vp9"
        case .av1: "libsvtav1"
        }
    }

    /// CRF scales differ per encoder: x264/x265 go to 51, the VP9 and AV1
    /// encoders to 63. Lower is better quality in all of them.
    public var crfRange: ClosedRange<Int> {
        switch self {
        case .h264, .hevc: 0...51
        case .vp9, .av1: 0...63
        }
    }

    /// Roughly comparable visual quality across the four, from the encoders'
    /// own documented defaults.
    public var defaultCRF: Int {
        switch self {
        case .h264: 23
        case .hevc: 28
        case .vp9: 32
        case .av1: 35
        }
    }

    public var hint: String {
        switch self {
        case .h264: "Läuft überall. Größte Dateien."
        case .hevc: "Deutlich kleiner, spielt in Safari und modernen Browsern."
        case .vp9: "WebM — für Browser, die kein HEVC mögen."
        case .av1: "Kleinste Dateien, aber langsam beim Kodieren."
        }
    }
}

import Foundation

/// Everything the video engine needs to know about *how* to encode.
///
/// Destination and renaming are the same types the image side uses — that part
/// of the behaviour is deliberately identical for both.
public struct VideoSettings: Sendable, Equatable {
    public var codec: VideoCodec
    /// Lower is better quality. Clamped to the codec's own range.
    public var crf: Int
    /// Longer edge in pixels. `nil` means no scaling.
    public var maxEdge: Int?
    public var keepAudio: Bool
    public var destinationDirectory: URL?
    public var nameTemplate: NameTemplate

    public init(
        codec: VideoCodec,
        crf: Int? = nil,
        maxEdge: Int? = nil,
        keepAudio: Bool = true,
        destinationDirectory: URL? = nil,
        nameTemplate: NameTemplate = .keepOriginal
    ) {
        self.codec = codec
        let requested = crf ?? codec.defaultCRF
        self.crf = min(codec.crfRange.upperBound, max(codec.crfRange.lowerBound, requested))
        self.maxEdge = maxEdge
        self.keepAudio = keepAudio
        self.destinationDirectory = destinationDirectory
        self.nameTemplate = nameTemplate
    }
}

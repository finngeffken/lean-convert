import Foundation
import AVFoundation
import CoreMedia

public struct VideoInfo: Sendable, Equatable {
    /// Display dimensions with rotation already applied — a portrait phone clip
    /// reports a landscape `naturalSize` plus a 90° transform, and scaling on
    /// the raw value would produce a squashed video.
    public let width: Int
    public let height: Int
    public let durationSeconds: Double
    public let hasAudio: Bool
    /// AAC audio can be copied into an MP4 untouched; anything else has to be
    /// re-encoded, so it is worth knowing.
    public let audioIsAAC: Bool

    public var longerEdge: Int { max(width, height) }

    public init(
        width: Int,
        height: Int,
        durationSeconds: Double,
        hasAudio: Bool,
        audioIsAAC: Bool
    ) {
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.hasAudio = hasAudio
        self.audioIsAAC = audioIsAAC
    }
}

/// Measures a video with AVFoundation rather than ffprobe — it is built into
/// macOS and saves bundling a second 20 MB binary for numbers the system
/// already knows.
public enum VideoProbe {
    public static func probe(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
            throw ProbeError.noVideoTrack
        }

        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let displayed = naturalSize.applying(transform)
        let width = Int(abs(displayed.width).rounded())
        let height = Int(abs(displayed.height).rounded())
        guard width > 0, height > 0 else {
            throw ProbeError.noVideoTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioIsAAC = false
        if let audio = audioTracks.first {
            let descriptions = try await audio.load(.formatDescriptions)
            audioIsAAC = descriptions.contains {
                CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC
            }
        }

        return VideoInfo(
            width: width,
            height: height,
            durationSeconds: max(0, duration.seconds),
            hasAudio: !audioTracks.isEmpty,
            audioIsAAC: audioIsAAC
        )
    }

    public enum ProbeError: Error {
        case noVideoTrack
    }
}

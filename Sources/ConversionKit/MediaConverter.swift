import Foundation

/// What a batch reports back while it runs.
///
/// Images finish in fractions of a second, so a count is enough for them. A
/// software AV1 encode runs for minutes, and a bar that sits at "0 of 3" for
/// four minutes looks broken — hence the inside view of the current file.
public struct BatchProgress: Sendable {
    public let completed: Int
    public let total: Int
    /// The file currently being worked on, if exactly one is.
    public let currentFile: URL?
    /// Progress within `currentFile`, 0...1, when the tool reports it.
    public let currentFraction: Double?

    public init(
        completed: Int,
        total: Int,
        currentFile: URL? = nil,
        currentFraction: Double? = nil
    ) {
        self.completed = completed
        self.total = total
        self.currentFile = currentFile
        self.currentFraction = currentFraction
    }
}

/// Everything `BatchRunner` needs from a converter, so that the batch logic —
/// input order, the concurrency window, "one failure costs only that file" —
/// exists exactly once for both images and video.
public protocol MediaConverter: Sendable {
    associatedtype Settings: Sendable

    /// How many of these may sensibly run at once.
    ///
    /// Belongs to the converter, not to the settings: image tools are
    /// single-threaded and scale with cores, while one ffmpeg encode already
    /// saturates the machine, so running ten would be slower, not faster.
    var maxConcurrency: Int { get }

    func convert(
        _ input: URL,
        settings: Settings,
        number: Int,
        reserver: NameReserver?,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> ConversionOutcome
}

import Foundation
import SwiftUI
import ConversionKit

/// The video mode's own state. Deliberately separate from the image side: the
/// two modes keep their own queues, so switching back and forth throws nothing
/// away.
@MainActor
final class VideoViewModel: ObservableObject {
    @Published var codec: VideoCodec {
        didSet {
            defaults.set(codec.rawValue, forKey: Keys.codec)
            // CRF scales differ per encoder (51 vs 63) and so do sensible
            // defaults, so a codec switch resets it rather than carrying a
            // number that means something else.
            crf = Double(codec.defaultCRF)
        }
    }
    @Published var crf: Double {
        didSet { defaults.set(crf, forKey: Keys.crf) }
    }
    @Published var maxEdgeText: String {
        didSet { defaults.set(maxEdgeText, forKey: Keys.maxEdge) }
    }
    @Published var keepAudio: Bool {
        didSet { defaults.set(keepAudio, forKey: Keys.keepAudio) }
    }
    @Published var renamePattern: String {
        didSet { defaults.set(renamePattern, forKey: Keys.renamePattern) }
    }
    @Published private(set) var destinationDirectory: URL? {
        didSet { defaults.set(destinationDirectory?.path, forKey: Keys.destination) }
    }

    @Published private(set) var queue: [URL] = []
    @Published private(set) var results: [ConversionOutcome] = []
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var currentFileName: String?
    @Published private(set) var currentFraction: Double?
    @Published private(set) var rejectedCount = 0
    @Published private(set) var availableCodecs: [VideoCodec] = []

    private let engine: VideoEngine
    private let defaults = AppDefaults.store
    private var task: Task<Void, Never>?

    private enum Keys {
        static let codec = "videoCodec"
        static let crf = "videoCRF"
        static let maxEdge = "videoMaxEdge"
        static let keepAudio = "videoKeepAudio"
        static let renamePattern = "videoRenamePattern"
        static let destination = "videoDestination"
    }

    init() {
        let ffmpegURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)
        engine = VideoEngine(ffmpegURL: ffmpegURL)

        let storedCodec = defaults.string(forKey: Keys.codec).flatMap(VideoCodec.init(rawValue:))
        let resolved = storedCodec ?? .h264
        codec = resolved
        crf = defaults.object(forKey: Keys.crf) as? Double ?? Double(resolved.defaultCRF)
        maxEdgeText = defaults.string(forKey: Keys.maxEdge) ?? ""
        keepAudio = defaults.object(forKey: Keys.keepAudio) as? Bool ?? true
        renamePattern = defaults.string(forKey: Keys.renamePattern) ?? ""

        if let path = defaults.string(forKey: Keys.destination),
           FileManager.default.isWritableFile(atPath: path) {
            destinationDirectory = URL(fileURLWithPath: path)
        } else {
            destinationDirectory = nil
        }
    }

    var isAvailable: Bool { engine.isAvailable }

    /// Asks ffmpeg once which encoders this build has. VP9 and AV1 are build
    /// options and missing from some builds.
    func detectCodecs() async {
        let codecs = await engine.availableCodecs()
        availableCodecs = codecs
        if !codecs.isEmpty && !codecs.contains(codec) {
            codec = codecs[0]
        }
    }

    var maxEdge: Int? {
        let trimmed = maxEdgeText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    var settings: VideoSettings {
        VideoSettings(
            codec: codec,
            crf: Int(crf),
            maxEdge: maxEdge,
            keepAudio: keepAudio,
            destinationDirectory: destinationDirectory,
            nameTemplate: NameTemplate(renamePattern)
        )
    }

    var canConvert: Bool { !queue.isEmpty && !isRunning && isAvailable }

    // MARK: - Queue

    func enqueue(_ urls: [URL]) {
        let (accepted, rejected) = InputValidator.partitionVideos(urls)
        rejectedCount = rejected.count
        guard !accepted.isEmpty else { return }

        let known = Set(queue.map(\.path))
        queue.append(contentsOf: accepted.filter { !known.contains($0.path) })
    }

    func remove(_ url: URL) {
        queue.removeAll { $0 == url }
    }

    func clearQueue() {
        queue = []
        rejectedCount = 0
    }

    func clearResults() {
        results = []
        completed = 0
        total = 0
    }

    // MARK: - Destination

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Auswählen"
        panel.message = "Zielordner für die konvertierten Videos"

        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        destinationDirectory = chosen
    }

    func useSourceDirectory() {
        destinationDirectory = nil
    }

    var destinationLabel: String {
        destinationDirectory?.lastPathComponent ?? "neben dem Original"
    }

    var renamePreview: String? {
        guard let first = queue.first else { return nil }
        let template = NameTemplate(renamePattern)
        guard !template.isEmpty else { return nil }

        let firstName = template.previewFilename(for: first, number: 1, format: codec)
        guard queue.count > 1, let last = queue.last else { return firstName }
        let lastName = template.previewFilename(for: last, number: queue.count, format: codec)
        return "\(firstName)  …  \(lastName)"
    }

    // MARK: - Conversion

    func convert() {
        guard canConvert else { return }

        let inputs = queue
        isRunning = true
        results = []
        completed = 0
        total = inputs.count
        currentFileName = nil
        currentFraction = nil

        let runner = BatchRunner(engine: engine)
        let settings = settings

        task = Task {
            let outcomes = await runner.run(inputs: inputs, settings: settings) { update in
                Task { @MainActor in
                    self.completed = update.completed
                    self.currentFileName = update.currentFile?.lastPathComponent
                    self.currentFraction = update.currentFraction
                }
            }
            self.results = outcomes
            self.isRunning = false
            self.currentFileName = nil
            self.currentFraction = nil
        }
    }

    /// A software AV1 encode runs for minutes; stopping it has to be possible.
    func cancel() {
        task?.cancel()
    }

    // MARK: - Summary

    var successCount: Int { results.filter(\.isSuccess).count }
    var failureCount: Int { results.count - successCount }
    var cancelledCount: Int {
        results.filter { outcome in
            if case .failure(_, .cancelled) = outcome { return true }
            return false
        }.count
    }

    var totalSaved: Int {
        results.reduce(0) { sum, outcome in
            guard case .success(_, _, let before, let after) = outcome else { return sum }
            return sum + (before - after)
        }
    }

    /// Overall progress including the fraction of the file in flight, so the bar
    /// keeps moving during a long encode instead of sitting still.
    var fractionalProgress: Double {
        guard total > 0 else { return 0 }
        return (Double(completed) + (currentFraction ?? 0)) / Double(total)
    }
}

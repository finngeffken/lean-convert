import Foundation
import SwiftUI
import AppKit
import ConversionKit

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published var target: TargetFormat {
        didSet { defaults.set(target.rawValue, forKey: Keys.target) }
    }
    @Published var quality: Double {
        didSet { defaults.set(quality, forKey: Keys.quality) }
    }
    @Published var maxEdgeText: String {
        didSet { defaults.set(maxEdgeText, forKey: Keys.maxEdge) }
    }
    @Published var renamePattern: String {
        didSet { defaults.set(renamePattern, forKey: Keys.renamePattern) }
    }

    /// `nil` means "next to each original" — the default.
    @Published private(set) var destinationDirectory: URL? {
        didSet { defaults.set(destinationDirectory?.path, forKey: Keys.destination) }
    }

    /// Dropped files wait here until the user presses Convert.
    @Published private(set) var queue: [URL] = []
    @Published private(set) var results: [ConversionOutcome] = []
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var rejectedCount = 0

    /// Set once the user picks a format themselves — after that, HEIC drops no
    /// longer override their choice.
    private var userChoseFormat = false

    private let engine: ConversionEngine
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let target = "target"
        static let quality = "quality"
        static let maxEdge = "maxEdge"
        static let renamePattern = "renamePattern"
        static let destination = "destinationDirectory"
    }

    init() {
        let cwebpURL = Bundle.main.url(forResource: "cwebp", withExtension: nil)
        engine = ConversionEngine(cwebpURL: cwebpURL)

        let storedTarget = defaults.string(forKey: Keys.target)
            .flatMap(TargetFormat.init(rawValue:))
        target = storedTarget ?? .jpeg
        quality = defaults.object(forKey: Keys.quality) as? Double ?? 85
        maxEdgeText = defaults.string(forKey: Keys.maxEdge) ?? ""
        renamePattern = defaults.string(forKey: Keys.renamePattern) ?? ""

        // A remembered folder may be gone or read-only by now; falling back to
        // "next to the original" beats failing every file with a stale path.
        if let path = defaults.string(forKey: Keys.destination),
           FileManager.default.isWritableFile(atPath: path) {
            destinationDirectory = URL(fileURLWithPath: path)
        } else {
            destinationDirectory = nil
        }

        // A stored WebP preference is useless if the binary went missing.
        if target == .webp && !engine.supportsWebP {
            target = .jpeg
        }
    }

    var availableFormats: [TargetFormat] { engine.availableFormats }
    var supportsWebP: Bool { engine.supportsWebP }

    var maxEdge: Int? {
        let trimmed = maxEdgeText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    var settings: ConversionSettings {
        ConversionSettings(
            target: target,
            quality: Int(quality),
            maxEdge: maxEdge,
            destinationDirectory: destinationDirectory,
            nameTemplate: NameTemplate(renamePattern)
        )
    }

    var canConvert: Bool { !queue.isEmpty && !isRunning }

    func selectFormat(_ format: TargetFormat) {
        userChoseFormat = true
        target = format
    }

    // MARK: - Queue

    /// Adds dropped files to the queue. Nothing is converted until the user
    /// says so.
    func enqueue(_ urls: [URL]) {
        let (accepted, rejected) = InputValidator.partition(urls)
        rejectedCount = rejected.count

        guard !accepted.isEmpty else { return }

        let known = Set(queue.map(\.path))
        let fresh = accepted.filter { !known.contains($0.path) }
        queue.append(contentsOf: fresh)

        if !userChoseFormat, let suggestion = FormatSuggestion.suggestedTarget(for: queue) {
            target = suggestion
        }
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
        panel.message = "Zielordner für die konvertierten Dateien"

        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        destinationDirectory = chosen
    }

    func useSourceDirectory() {
        destinationDirectory = nil
    }

    var destinationLabel: String {
        destinationDirectory?.lastPathComponent ?? "neben dem Original"
    }

    // MARK: - Renaming preview

    /// Shows what the pattern does to the real queue, first and last entry.
    /// Silence when there is nothing to preview beats a made-up example.
    var renamePreview: String? {
        guard let first = queue.first else { return nil }
        let template = NameTemplate(renamePattern)
        guard !template.isEmpty else { return nil }

        let firstName = template.previewFilename(for: first, number: 1, format: target)
        guard queue.count > 1, let last = queue.last else {
            return "\(first.lastPathComponent) → \(firstName)"
        }
        let lastName = template.previewFilename(for: last, number: queue.count, format: target)
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

        let runner = BatchRunner(engine: engine)
        let settings = settings

        Task {
            let outcomes = await runner.run(inputs: inputs, settings: settings) { done, _ in
                Task { @MainActor in self.completed = done }
            }
            self.results = outcomes
            self.isRunning = false
        }
    }

    // MARK: - Summary

    var successCount: Int { results.filter(\.isSuccess).count }
    var failureCount: Int { results.count - successCount }

    /// Total bytes saved across the batch, negative if output grew.
    var totalSaved: Int {
        results.reduce(0) { sum, outcome in
            guard case .success(_, _, let before, let after) = outcome else { return sum }
            return sum + (before - after)
        }
    }
}

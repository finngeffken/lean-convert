import Foundation
import SwiftUI
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
    }

    init() {
        let cwebpURL = Bundle.main.url(forResource: "cwebp", withExtension: nil)
        engine = ConversionEngine(cwebpURL: cwebpURL)

        let storedTarget = defaults.string(forKey: Keys.target)
            .flatMap(TargetFormat.init(rawValue:))
        target = storedTarget ?? .jpeg
        quality = defaults.object(forKey: Keys.quality) as? Double ?? 85
        maxEdgeText = defaults.string(forKey: Keys.maxEdge) ?? ""

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
        ConversionSettings(target: target, quality: Int(quality), maxEdge: maxEdge)
    }

    func selectFormat(_ format: TargetFormat) {
        userChoseFormat = true
        target = format
    }

    func accept(_ urls: [URL]) {
        let (accepted, rejected) = InputValidator.partition(urls)
        rejectedCount = rejected.count

        guard !accepted.isEmpty else { return }

        if !userChoseFormat, let suggestion = FormatSuggestion.suggestedTarget(for: accepted) {
            target = suggestion
        }

        convert(accepted)
    }

    private func convert(_ inputs: [URL]) {
        guard !isRunning else { return }

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

    func clearResults() {
        results = []
        rejectedCount = 0
        completed = 0
        total = 0
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

import Foundation
import ConversionKit

/// Replicates how `ConverterViewModel` actually starts a batch: a `Task {}`
/// created inside a `@MainActor` type, with a progress callback that hops back
/// to the main actor for every file.
///
/// This is the one structural difference between the passing scale test and the
/// hang reported from the app.
@MainActor
final class FakeViewModel {
    private(set) var completed = 0
    private(set) var isRunning = false
    private(set) var results: [ConversionOutcome] = []

    private let engine = ConversionEngine(cwebpURL: nil)

    /// Mirrors ConverterViewModel.convert() exactly, including the nested
    /// `Task { @MainActor ... }` inside the progress closure.
    func convert(_ inputs: [URL], settings: ConversionSettings) {
        isRunning = true
        completed = 0
        results = []

        let runner = BatchRunner(engine: engine)

        Task {
            let outcomes = await runner.run(inputs: inputs, settings: settings) { done, _ in
                Task { @MainActor in self.completed = done }
            }
            self.results = outcomes
            self.isRunning = false
        }
    }
}

enum MainActorReproTests {

    /// Polls instead of awaiting the internal task, the same way the UI does —
    /// and gives up rather than hanging the whole suite forever.
    static func batchStartedFromMainActorFinishes() async throws {
        let directory = try TestImage.scratchDirectory("mainactor-repro")
        let target = try TestImage.scratchDirectory("mainactor-repro-out")

        let master = directory.appendingPathComponent("master.jpg")
        try TestImage.writeJPEG(width: 4000, height: 3000, to: master)

        var inputs: [URL] = []
        for index in 0..<49 {
            let copy = directory.appendingPathComponent(String(format: "src-%03d.jpg", index))
            try FileManager.default.copyItem(at: master, to: copy)
            inputs.append(copy)
        }

        let model = await FakeViewModel()
        await model.convert(
            inputs,
            settings: .init(
                target: .avif,
                quality: 85,
                maxEdge: 2000,
                destinationDirectory: target,
                nameTemplate: NameTemplate("AM-Website-{n}")
            )
        )

        let deadline = Date().addingTimeInterval(120)
        var lastCompleted = -1
        var stalledSince = Date()

        while Date() < deadline {
            let running = await model.isRunning
            let completed = await model.completed
            if !running { break }

            if completed != lastCompleted {
                lastCompleted = completed
                stalledSince = Date()
            } else if Date().timeIntervalSince(stalledSince) > 30 {
                throw TestFailure(
                    message: "Fortschritt hängt seit 30 s bei \(completed)/49",
                    file: #fileID,
                    line: #line
                )
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let running = await model.isRunning
        let completed = await model.completed
        try expect(!running, "Lauf muss beendet sein, war bei \(completed)/49")
        try expectEqual(await model.results.filter(\.isSuccess).count, 49, "alle Dateien")
    }
}

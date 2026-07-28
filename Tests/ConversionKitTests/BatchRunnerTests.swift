import Foundation
import ConversionKit

enum BatchTests {

    /// The central promise of the batch: one broken file costs you that file
    /// and nothing else.
    static func corruptFileDoesNotStopTheRest() async throws {
        let directory = try TestImage.scratchDirectory("batch-mixed")

        var inputs: [URL] = []
        for index in 0..<6 {
            let url = directory.appendingPathComponent("image-\(index).png")
            if index == 3 {
                try TestImage.writeCorrupt(to: url)
            } else {
                try TestImage.writePNG(width: 400, height: 300, to: url)
            }
            inputs.append(url)
        }

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(inputs: inputs, settings: .init(target: .jpeg, quality: 80))

        try expectEqual(outcomes.count, 6, "Anzahl Ergebnisse")
        try expectEqual(outcomes.filter(\.isSuccess).count, 5, "Erfolge")
        try expect(!outcomes[3].isSuccess, "die kaputte Datei ist die, die fehlschlägt")
    }

    static func resultsComeBackInInputOrder() async throws {
        let directory = try TestImage.scratchDirectory("batch-order")

        var inputs: [URL] = []
        for index in 0..<12 {
            let url = directory.appendingPathComponent("ordered-\(index).png")
            // Varying sizes make completion order differ from input order.
            try TestImage.writePNG(width: 200 + index * 120, height: 150, to: url)
            inputs.append(url)
        }

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(inputs: inputs, settings: .init(target: .jpeg, quality: 80))

        try expectEqual(outcomes.map(\.input), inputs, "Reihenfolge")
    }

    static func progressReportsEveryFileOnce() async throws {
        let directory = try TestImage.scratchDirectory("batch-progress")

        var inputs: [URL] = []
        for index in 0..<8 {
            let url = directory.appendingPathComponent("p-\(index).png")
            try TestImage.writePNG(width: 300, height: 200, to: url)
            inputs.append(url)
        }

        let counter = Counter()
        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        _ = await runner.run(
            inputs: inputs,
            settings: .init(target: .jpeg, quality: 80),
            progress: { done, total in counter.record(done: done, total: total) }
        )

        try expectEqual(counter.callCount, 8, "Anzahl Fortschrittsmeldungen")
        try expectEqual(counter.lastDone, 8, "letzter Stand")
        try expectEqual(counter.lastTotal, 8, "gemeldete Gesamtzahl")
    }

    static func everyFileIsProcessedBeyondTheConcurrencyLimit() async throws {
        let directory = try TestImage.scratchDirectory("batch-beyond-limit")

        var inputs: [URL] = []
        for index in 0..<20 {
            let url = directory.appendingPathComponent("many-\(index).png")
            try TestImage.writePNG(width: 200, height: 150, to: url)
            inputs.append(url)
        }

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(target: .jpeg, quality: 80),
            maxConcurrent: 3
        )

        try expectEqual(outcomes.count, 20, "Anzahl Ergebnisse")
        try expectEqual(outcomes.filter(\.isSuccess).count, 20, "alle müssen durchlaufen")
    }

    static func emptyInputReturnsEmpty() async throws {
        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(inputs: [], settings: .init(target: .jpeg))
        try expect(outcomes.isEmpty, "leere Eingabe muss leeres Ergebnis liefern")
    }

    static func concurrencyLimitIsClampedToAtLeastOne() async throws {
        let directory = try TestImage.scratchDirectory("batch-clamp")
        let input = directory.appendingPathComponent("single.png")
        try TestImage.writePNG(width: 300, height: 200, to: input)

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: [input],
            settings: .init(target: .jpeg),
            maxConcurrent: 0
        )

        try expectEqual(outcomes.count, 1, "Anzahl Ergebnisse")
        try expect(outcomes[0].isSuccess, "die einzige Datei muss konvertiert werden")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var done = 0
    private var total = 0

    func record(done: Int, total: Int) {
        lock.lock()
        calls += 1
        self.done = max(self.done, done)
        self.total = total
        lock.unlock()
    }

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var lastDone: Int { lock.lock(); defer { lock.unlock() }; return done }
    var lastTotal: Int { lock.lock(); defer { lock.unlock() }; return total }
}

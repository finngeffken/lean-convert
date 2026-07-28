import Foundation
import ConversionKit

/// Reproduction for the hang reported on a real 49-file batch.
///
/// Hypothesis under test: `engine.convert` blocks its thread, and with
/// `maxConcurrent` equal to the core count every thread of the Swift
/// concurrency cooperative pool is blocked — including the one that would
/// collect results — so the batch never progresses.
///
/// If the hypothesis holds, `fullConcurrency` hangs and `belowCoreCount`
/// passes.
enum ScaleTests {
    static let fileCount = 49

    private static func makeBatch(_ label: String, count: Int = fileCount) throws -> [URL] {
        let directory = try TestImage.scratchDirectory(label)
        let master = directory.appendingPathComponent("master.jpg")
        // Large enough that each conversion takes real time, which is what
        // widens the window for the starvation to bite.
        try TestImage.writeJPEG(width: 4000, height: 3000, to: master)

        var inputs: [URL] = []
        for index in 0..<count {
            let copy = directory.appendingPathComponent(String(format: "src-%03d.jpg", index))
            try FileManager.default.copyItem(at: master, to: copy)
            inputs.append(copy)
        }
        return inputs
    }

    static func belowCoreCount() async throws {
        let inputs = try makeBatch("scale-low")
        let target = try TestImage.scratchDirectory("scale-low-out")

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(
                target: .avif,
                quality: 85,
                maxEdge: 2000,
                destinationDirectory: target,
                nameTemplate: NameTemplate("AM-Website-{n}")
            ),
            maxConcurrent: 4
        )

        try expectEqual(outcomes.filter(\.isSuccess).count, fileCount, "alle Dateien")
    }

    /// Regression guard for the hang found in the app: more concurrent
    /// conversions than the machine has cores. A `ProcessRunner` that blocks its
    /// caller parks every thread of the cooperative pool in
    /// `DispatchGroup.wait()`, waiting on pipe readers that need a thread from
    /// that very pool. Nothing can then make progress — not even a timeout task,
    /// which is why the suite's watchdog runs on a thread of its own.
    static func oversubscribedConcurrency() async throws {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let inputs = try makeBatch("scale-oversubscribed", count: cores * 3)
        let target = try TestImage.scratchDirectory("scale-oversubscribed-out")

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(target: .jpeg, quality: 80, maxEdge: 1200, destinationDirectory: target),
            maxConcurrent: cores * 2
        )

        try expectEqual(outcomes.filter(\.isSuccess).count, inputs.count, "alle Dateien")
    }

    static func fullConcurrency() async throws {
        let inputs = try makeBatch("scale-full")
        let target = try TestImage.scratchDirectory("scale-full-out")

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(
                target: .avif,
                quality: 85,
                maxEdge: 2000,
                destinationDirectory: target,
                nameTemplate: NameTemplate("AM-Website-{n}")
            ),
            maxConcurrent: cores
        )

        try expectEqual(outcomes.filter(\.isSuccess).count, fileCount, "alle Dateien")
    }
}

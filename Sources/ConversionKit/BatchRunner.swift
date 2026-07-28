import Foundation

/// Runs a batch with bounded parallelism.
///
/// The work is CPU-bound inside external processes, so the core count is the
/// natural ceiling: more would not go faster and would make the machine
/// unusable while 200 files churn.
public struct BatchRunner: Sendable {
    let engine: ConversionEngine

    public init(engine: ConversionEngine) {
        self.engine = engine
    }

    /// Results come back in input order, regardless of completion order.
    /// `progress` fires on every completed file with (done, total).
    public func run(
        inputs: [URL],
        settings: ConversionSettings,
        maxConcurrent: Int = ProcessInfo.processInfo.activeProcessorCount,
        progress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> [ConversionOutcome] {
        guard !inputs.isEmpty else { return [] }

        let limit = max(1, min(maxConcurrent, inputs.count))
        let total = inputs.count
        let engine = engine

        var collected: [(Int, ConversionOutcome)] = []
        collected.reserveCapacity(total)

        await withTaskGroup(of: (Int, ConversionOutcome).self) { group in
            var next = 0
            var done = 0

            // Prime the group up to the limit, then top it up as slots free.
            while next < limit {
                let index = next
                let input = inputs[index]
                group.addTask { (index, engine.convert(input, settings: settings)) }
                next += 1
            }

            while let finished = await group.next() {
                collected.append(finished)
                done += 1
                progress(done, total)

                if next < total {
                    let index = next
                    let input = inputs[index]
                    group.addTask { (index, engine.convert(input, settings: settings)) }
                    next += 1
                }
            }
        }

        return collected.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

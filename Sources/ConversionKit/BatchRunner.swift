import Foundation

/// Runs a batch with bounded parallelism.
///
/// Generic over the converter so images and video share one implementation of
/// ordering, the concurrency window and per-file failure isolation.
public struct BatchRunner<Converter: MediaConverter>: Sendable {
    let engine: Converter

    public init(engine: Converter) {
        self.engine = engine
    }

    /// Results come back in input order, regardless of completion order.
    /// `maxConcurrent` defaults to what the converter considers sensible.
    ///
    /// Cancelling the surrounding task stops the batch: running tools are
    /// terminated and whatever finished so far is returned.
    public func run(
        inputs: [URL],
        settings: Converter.Settings,
        maxConcurrent: Int? = nil,
        progress: @Sendable @escaping (BatchProgress) -> Void = { _ in }
    ) async -> [ConversionOutcome] {
        guard !inputs.isEmpty else { return [] }

        let limit = max(1, min(maxConcurrent ?? engine.maxConcurrency, inputs.count))
        let total = inputs.count
        let engine = engine

        // One reserver for the whole batch: it is what keeps two files that
        // resolve to the same output name from both claiming it.
        let reserver = NameReserver()

        // Only meaningful while a single file is in flight — with ten parallel
        // image conversions there is no "current" file to speak of.
        let tracker = ProgressTracker(reportsInsideFile: limit == 1)

        var collected: [(Int, ConversionOutcome)] = []
        collected.reserveCapacity(total)

        await withTaskGroup(of: (Int, ConversionOutcome).self) { group in
            var next = 0
            var done = 0

            func addTask(_ index: Int) {
                let input = inputs[index]
                group.addTask {
                    let outcome = await engine.convert(
                        input,
                        settings: settings,
                        number: index + 1,
                        reserver: reserver,
                        progress: { fraction in
                            // Only report onward when the tracker took the
                            // value, so a converter without inside-file
                            // progress cannot double-report per file.
                            guard tracker.report(file: input, fraction: fraction) else { return }
                            progress(tracker.snapshot(completed: nil, total: total))
                        }
                    )
                    return (index, outcome)
                }
            }

            // Prime the group up to the limit, then top it up as slots free.
            while next < limit {
                addTask(next)
                next += 1
            }

            while let finished = await group.next() {
                collected.append(finished)
                done += 1
                tracker.finish()
                progress(tracker.snapshot(completed: done, total: total))

                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                if next < total {
                    addTask(next)
                    next += 1
                }
            }
        }

        return collected.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

/// Keeps the "inside the current file" part of progress, which several tasks
/// may touch.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private let reportsInsideFile: Bool
    private var completed = 0
    private var file: URL?
    private var fraction: Double?

    init(reportsInsideFile: Bool) {
        self.reportsInsideFile = reportsInsideFile
    }

    /// Returns false when inside-file progress is not meaningful for this run.
    func report(file: URL, fraction: Double) -> Bool {
        guard reportsInsideFile else { return false }
        lock.lock()
        self.file = file
        self.fraction = min(1, max(0, fraction))
        lock.unlock()
        return true
    }

    func finish() {
        lock.lock()
        completed += 1
        file = nil
        fraction = nil
        lock.unlock()
    }

    func snapshot(completed override: Int?, total: Int) -> BatchProgress {
        lock.lock()
        defer { lock.unlock() }
        return BatchProgress(
            completed: override ?? completed,
            total: total,
            currentFile: file,
            currentFraction: fraction
        )
    }
}

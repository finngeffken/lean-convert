import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    /// Runs an external tool to completion and captures both streams.
    ///
    /// This is `async` on purpose, and nothing in it may block the caller.
    /// The earlier synchronous version parked the calling thread in
    /// `DispatchGroup.wait()` until two reader closures on
    /// `DispatchQueue.global()` had drained the pipes — and inside a GUI app
    /// that global queue *is* the Swift concurrency cooperative pool, whose
    /// width equals the core count. With one conversion per core, every thread
    /// of that pool sat in `wait()` waiting for readers that could never get a
    /// thread. Nothing ran, no subprocess was even spawned, and AppKit's own
    /// XPC replies stalled too, freezing the window.
    ///
    /// So: the task suspends on a continuation instead of blocking a thread,
    /// and the pipes are drained by readability handlers that Dispatch services
    /// on its own queues.
    static func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = StreamCollector()

        // Drain while the tool runs, so a full pipe buffer can never stall it.
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.appendOut(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.appendErr(chunk)
            }
        }

        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            let resume = ResumeOnce()
            process.terminationHandler = { finished in
                if resume.claim() {
                    continuation.resume(returning: finished.terminationStatus)
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                if resume.claim() {
                    continuation.resume(throwing: error)
                }
            }
        }

        // The writer is gone now, so this cannot block. It only picks up
        // whatever the handlers had not seen by the time the tool exited.
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
        collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())

        return ProcessResult(
            exitCode: exitCode,
            stdout: collector.outText,
            stderr: collector.errText
        )
    }
}

/// Guarantees a continuation is resumed exactly once, whether the process
/// terminates normally or `run()` throws before it ever starts.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// Lock-guarded accumulation, since the two readability handlers run
/// concurrently on Dispatch-managed queues.
private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) {
        lock.lock(); out.append(data); lock.unlock()
    }

    func appendErr(_ data: Data) {
        lock.lock(); err.append(data); lock.unlock()
    }

    var outText: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: out, encoding: .utf8) ?? ""
    }

    var errText: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: err, encoding: .utf8) ?? ""
    }
}

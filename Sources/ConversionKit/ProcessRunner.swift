import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    /// True when the tool was killed because the surrounding task was cancelled.
    let wasCancelled: Bool
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
    ///
    /// `onStdoutLine` receives stdout line by line while the tool runs, which
    /// is how ffmpeg's `-progress pipe:1` output is turned into a percentage.
    /// Cancelling the task terminates the tool rather than letting a
    /// ten-minute encode run on unattended.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        onStdoutLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Tools must never wait on input they will not get.
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = StreamCollector(onLine: onStdoutLine)
        let state = ProcessBox(process)

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

        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resume = ResumeOnce()
                process.terminationHandler = { finished in
                    if resume.claim() {
                        continuation.resume(returning: finished.terminationStatus)
                    }
                }
                do {
                    try state.start()
                } catch {
                    process.terminationHandler = nil
                    if resume.claim() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            state.terminate()
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
            stderr: collector.errText,
            wasCancelled: state.wasTerminated
        )
    }
}

/// Bridges the non-Sendable `Process` into the cancellation handler, and closes
/// the window where cancellation arrives before the tool has even started.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var started = false
    private var cancelled = false

    init(_ process: Process) {
        self.process = process
    }

    var wasTerminated: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func start() throws {
        lock.lock()
        // Cancelled before launch: do not start at all.
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        started = true
        lock.unlock()
        try process.run()
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let shouldTerminate = started && process.isRunning
        lock.unlock()
        if shouldTerminate {
            process.terminate()
        }
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
    private var pending = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        out.append(data)
        var lines: [String] = []
        if onLine != nil, let text = String(data: data, encoding: .utf8) {
            pending += text
            while let breakIndex = pending.firstIndex(of: "\n") {
                lines.append(String(pending[pending.startIndex..<breakIndex]))
                pending = String(pending[pending.index(after: breakIndex)...])
            }
        }
        lock.unlock()
        // Called outside the lock: the handler is caller code and must not be
        // able to deadlock the collector.
        for line in lines { onLine?(line) }
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
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

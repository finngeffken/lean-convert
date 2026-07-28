import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    /// Runs an external tool to completion and captures both streams.
    ///
    /// stdout and stderr are drained on separate queues: reading one to EOF
    /// before touching the other deadlocks as soon as a tool fills the pipe
    /// buffer it is not being read from.
    static func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let collector = StreamCollector()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        group.enter()
        queue.async {
            collector.setOut(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        queue.async {
            collector.setErr(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: collector.outText,
            stderr: collector.errText
        )
    }
}

/// Small lock-guarded box so the two reader queues can hand their data back
/// without tripping over each other.
private final class StreamCollector {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func setOut(_ data: Data) {
        lock.lock(); out = data; lock.unlock()
    }

    func setErr(_ data: Data) {
        lock.lock(); err = data; lock.unlock()
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

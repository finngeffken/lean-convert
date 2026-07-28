import Foundation

/// A failed expectation, carrying enough location to find it again.
struct TestFailure: Error {
    let message: String
    let file: String
    let line: UInt
}

// MARK: - Expectations

func expect(
    _ condition: Bool,
    _ message: String,
    file: String = #fileID,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String = "",
    file: String = #fileID,
    line: UInt = #line
) throws {
    guard actual != expected else { return }
    let prefix = label.isEmpty ? "" : "\(label) — "
    throw TestFailure(
        message: "\(prefix)erwartet \(expected), bekommen \(actual)",
        file: file,
        line: line
    )
}

func expectNil<T>(
    _ value: T?,
    _ label: String = "",
    file: String = #fileID,
    line: UInt = #line
) throws {
    guard let value else { return }
    let prefix = label.isEmpty ? "" : "\(label) — "
    throw TestFailure(message: "\(prefix)erwartet nil, bekommen \(value)", file: file, line: line)
}

/// Unwraps or fails the test — the equivalent of `#require`.
func require<T>(
    _ value: T?,
    _ label: String = "",
    file: String = #fileID,
    line: UInt = #line
) throws -> T {
    guard let value else {
        let prefix = label.isEmpty ? "Wert" : label
        throw TestFailure(message: "\(prefix) war nil", file: file, line: line)
    }
    return value
}

func expectThrows(
    _ label: String = "",
    file: String = #fileID,
    line: UInt = #line,
    _ body: () async throws -> Void
) async throws {
    do {
        try await body()
    } catch {
        return
    }
    let prefix = label.isEmpty ? "" : "\(label) — "
    throw TestFailure(message: "\(prefix)erwartet: Fehler, bekommen: Erfolg", file: file, line: line)
}

// MARK: - Runner

/// Minimal test runner.
///
/// Neither test framework is available here: XCTest ships only with a full
/// Xcode, and the Testing.framework in the Command Line Tools links against a
/// `lib_TestingInterop.dylib` that Apple does not ship. Rather than make a
/// small image converter depend on a multi-gigabyte Xcode install, the suite is
/// an ordinary executable that exits non-zero when something fails.
final class TestRunner {
    private var passed = 0
    private var skipped = 0
    private var failures: [(name: String, failure: TestFailure)] = []

    func suite(_ name: String) {
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
    }

    func skip(_ name: String, _ reason: String) {
        skipped += 1
        print("  – \(name)  (übersprungen: \(reason))")
    }

    /// Async tests get a watchdog. A deadlocked cooperative thread pool cannot
    /// be detected from inside Swift concurrency — a timeout task would need a
    /// pool thread to resume, and there are none left. The watchdog therefore
    /// runs on a real thread of its own and turns a hang into a visible,
    /// non-zero-exit failure instead of an eternally silent test run.
    func test(_ name: String, timeout: TimeInterval = 120, _ body: () async throws -> Void) async {
        let watchdog = Watchdog(name: name, timeout: timeout)
        watchdog.arm()
        defer { watchdog.disarm() }

        do {
            try await body()
            pass(name)
        } catch let failure as TestFailure {
            fail(name, failure)
        } catch {
            fail(name, TestFailure(message: "unerwarteter Fehler: \(error)", file: "-", line: 0))
        }
    }

    private func pass(_ name: String) {
        passed += 1
        print("  \u{001B}[32m✓\u{001B}[0m \(name)")
    }

    private func fail(_ name: String, _ failure: TestFailure) {
        failures.append((name, failure))
        print("  \u{001B}[31m✗\u{001B}[0m \(name)")
        print("      \(failure.message)")
        if failure.line > 0 {
            print("      \(failure.file):\(failure.line)")
        }
    }

    /// Fires from a plain `Thread`, deliberately outside the Swift concurrency
    /// pool, so it still runs when that pool is wedged.
    private final class Watchdog: @unchecked Sendable {
        private let name: String
        private let timeout: TimeInterval
        private let lock = NSLock()
        private var finished = false

        init(name: String, timeout: TimeInterval) {
            self.name = name
            self.timeout = timeout
        }

        func arm() {
            let thread = Thread { [self] in
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.25)
                    lock.lock()
                    let done = finished
                    lock.unlock()
                    if done { return }
                }
                FileHandle.standardError.write(Data("""

                \u{001B}[31m✗ HÄNGT\u{001B}[0m \(name)
                      Kein Fortschritt in \(Int(timeout)) s — vermutlich verklemmt.
                      Der Wachhund bricht ab, damit das kein stiller Dauerlauf wird.

                """.utf8))
                exit(1)
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }

        func disarm() {
            lock.lock()
            finished = true
            lock.unlock()
        }
    }

    func finish() -> Never {
        print("")
        if failures.isEmpty {
            var line = "\u{001B}[32m\(passed) bestanden\u{001B}[0m"
            if skipped > 0 { line += ", \(skipped) übersprungen" }
            print(line)
            exit(0)
        }

        print("\u{001B}[31m\(failures.count) fehlgeschlagen\u{001B}[0m, \(passed) bestanden"
              + (skipped > 0 ? ", \(skipped) übersprungen" : ""))
        for (name, failure) in failures {
            print("  ✗ \(name): \(failure.message)")
        }
        exit(1)
    }
}

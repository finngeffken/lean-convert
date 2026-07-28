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
    _ body: () throws -> Void
) throws {
    do {
        try body()
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

    func test(_ name: String, _ body: () throws -> Void) {
        record(name) { try body() }
    }

    func test(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            pass(name)
        } catch let failure as TestFailure {
            fail(name, failure)
        } catch {
            fail(name, TestFailure(message: "unerwarteter Fehler: \(error)", file: "-", line: 0))
        }
    }

    private func record(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
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

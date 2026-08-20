import Foundation

/// Why a single file failed. Failures are always scoped to one file — a bad
/// image never aborts the rest of a batch.
public enum FailureReason: Sendable, Equatable {
    case unreadable(String)
    case unsupportedInput(String)
    case destinationNotWritable(String)
    case toolMissing(String)
    case toolFailed(tool: String, exitCode: Int32, stderr: String)
    /// The tool reported success but produced nothing usable.
    case noOutputProduced(String)
    /// The run was cancelled. Not really an error, but it has to be
    /// distinguishable from a tool that failed on its own.
    case cancelled

    public var message: String {
        switch self {
        case .unreadable(let detail):
            "Nicht lesbar oder beschädigt: \(detail)"
        case .unsupportedInput(let detail):
            "Eingabeformat nicht unterstützt: \(detail)"
        case .destinationNotWritable(let path):
            "Zielordner nicht schreibbar: \(path)"
        case .toolMissing(let tool):
            "\(tool) nicht gefunden — ohne dieses Binary ist das Format nicht verfügbar."
        case .toolFailed(let tool, let code, let stderr):
            "\(tool) endete mit Code \(code): \(stderr.isEmpty ? "keine Details" : stderr)"
        case .noOutputProduced(let path):
            "Keine Ausgabedatei erzeugt: \(path)"
        case .cancelled:
            "Abgebrochen"
        }
    }
}

public enum ConversionOutcome: Sendable {
    case success(input: URL, output: URL, bytesBefore: Int, bytesAfter: Int)
    case failure(input: URL, reason: FailureReason)

    public var input: URL {
        switch self {
        case .success(let input, _, _, _): input
        case .failure(let input, _): input
        }
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Negative values mean the file got bigger — worth showing honestly
    /// rather than clamping to zero.
    public var savedFraction: Double? {
        guard case .success(_, _, let before, let after) = self, before > 0 else { return nil }
        return (Double(before) - Double(after)) / Double(before)
    }
}

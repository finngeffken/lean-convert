import Foundation
import UniformTypeIdentifiers
import ConversionKit

/// Container identifiers the tests assert against. AVIF has no `UTType`
/// constant in this SDK, so its identifier is spelled out.
enum ContainerType {
    static let jpeg = UTType.jpeg.identifier
    static let png = UTType.png.identifier
    static let webp = UTType.webP.identifier
    static let avif = "public.avif"
}

enum TestSupport {
    /// The binary lives in the app bundle at runtime, so tests locate it in the
    /// repository instead. WebP tests are skipped when it is absent.
    static let cwebpURL: URL? = {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ConversionKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let candidate = repoRoot.appendingPathComponent("Resources/cwebp")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }()

    static var hasCwebp: Bool { cwebpURL != nil }

    static func engine() -> ConversionEngine {
        ConversionEngine(cwebpURL: cwebpURL)
    }

    /// An engine that deliberately has no WebP support.
    static func engineWithoutWebP() -> ConversionEngine {
        ConversionEngine(cwebpURL: nil)
    }
}

/// Optional accessors so tests can use `require(...)` instead of a `guard case`
/// ladder in every single test.
extension ConversionOutcome {
    var successOutput: URL? {
        if case .success(_, let output, _, _) = self { return output }
        return nil
    }

    var byteSizes: (before: Int, after: Int)? {
        if case .success(_, _, let before, let after) = self { return (before, after) }
        return nil
    }

    var failureReason: FailureReason? {
        if case .failure(_, let reason) = self { return reason }
        return nil
    }
}

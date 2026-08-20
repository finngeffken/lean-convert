import Foundation
import ConversionKit

/// Diagnostic run against the actual reported batch: 49 real 6000×4000
/// photographs. Reads only; every output goes to a scratch directory.
///
/// Skipped when the folder is not present, so this never breaks on another
/// machine.
enum RealFilesRepro {
    static let sourceFolder = URL(
        fileURLWithPath: "/Users/finngeffken/Downloads/Bildmaterial_AM/Auswahl AM_Fotos 8.7.26"
    )

    static var isAvailable: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: sourceFolder.path))?
            .contains { $0.hasSuffix(".JPG") } ?? false
    }

    static func realBatchFinishes() async throws {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: sourceFolder.path)
            .filter { $0.hasSuffix(".JPG") }
            .sorted()
        let inputs = names.map { sourceFolder.appendingPathComponent($0) }
        let target = try TestImage.scratchDirectory("real-batch-out")

        print("      \(inputs.count) echte Dateien, Ziel: \(target.lastPathComponent)")

        let started = Date()
        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(
                target: .avif,
                quality: 85,
                maxEdge: 2000,
                destinationDirectory: target,
                nameTemplate: NameTemplate("AM-Website-{n}")
            )
        ) { update in
            if update.completed % 10 == 0 || update.completed == update.total {
                print("      \(update.completed)/\(update.total) nach \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            }
        }

        let elapsed = Date().timeIntervalSince(started)
        let failures = outcomes.filter { !$0.isSuccess }
        for failure in failures.prefix(3) {
            if let reason = failure.failureReason {
                print("      Fehler: \(failure.input.lastPathComponent) — \(reason.message)")
            }
        }
        print("      Gesamt: \(String(format: "%.1f", elapsed)) s")

        try expectEqual(outcomes.count, inputs.count, "Anzahl Ergebnisse")
        try expectEqual(failures.count, 0, "keine Fehlschläge")
    }
}

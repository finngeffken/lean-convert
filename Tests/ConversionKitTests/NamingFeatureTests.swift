import Foundation
import ConversionKit

enum TemplateTests {

    static func emptyPatternKeepsOriginalName() async throws {
        let input = URL(fileURLWithPath: "/tmp/a3e32b79-01b1.jpg")
        try expectEqual(NameTemplate("").baseName(for: input, number: 7), "a3e32b79-01b1")
        try expect(NameTemplate("   ").isEmpty, "reine Leerzeichen zählen als leer")
    }

    static func counterTokenPadsToTokenLength() async throws {
        let input = URL(fileURLWithPath: "/tmp/whatever.jpg")
        try expectEqual(NameTemplate("{n}").baseName(for: input, number: 5), "5")
        try expectEqual(NameTemplate("{nn}").baseName(for: input, number: 5), "05")
        try expectEqual(NameTemplate("{nnn}").baseName(for: input, number: 5), "005")
        try expectEqual(NameTemplate("{nn}").baseName(for: input, number: 123), "123",
                        "die Nummer wird nicht abgeschnitten, nur aufgefüllt")
    }

    static func nameTokenInsertsOriginal() async throws {
        let input = URL(fileURLWithPath: "/tmp/hero-shot.png")
        try expectEqual(NameTemplate("{name}-web").baseName(for: input, number: 1), "hero-shot-web")
        try expectEqual(NameTemplate("2027_{name}").baseName(for: input, number: 1), "2027_hero-shot")
    }

    static func combinedTokens() async throws {
        let input = URL(fileURLWithPath: "/tmp/a3e32b79.jpg")
        try expectEqual(
            NameTemplate("AM-Kalender-{nn}").baseName(for: input, number: 3),
            "AM-Kalender-03"
        )
        try expectEqual(
            NameTemplate("{nn}_{name}").baseName(for: input, number: 12),
            "12_a3e32b79"
        )
    }

    /// A typo should be visible in the preview, not silently swallowed.
    static func unknownTokenStaysLiteral() async throws {
        let input = URL(fileURLWithPath: "/tmp/pic.jpg")
        try expectEqual(NameTemplate("{nmae}-x").baseName(for: input, number: 1), "{nmae}-x")
    }

    static func unclosedBraceIsTakenLiterally() async throws {
        let input = URL(fileURLWithPath: "/tmp/pic.jpg")
        try expectEqual(NameTemplate("shot-{n").baseName(for: input, number: 1), "shot-{n")
    }

    /// Slashes would create directories, colons are illegal, a leading dot
    /// would hide the file.
    static func illegalCharactersAreStripped() async throws {
        let input = URL(fileURLWithPath: "/tmp/pic.jpg")
        try expectEqual(NameTemplate("a/b").baseName(for: input, number: 1), "a-b")
        try expectEqual(NameTemplate("a:b").baseName(for: input, number: 1), "a-b")
        try expectEqual(NameTemplate("..hidden").baseName(for: input, number: 1), "hidden")
    }

    /// Separators are replaced, not reinterpreted — same principle as unknown
    /// tokens staying literal. `---.jpg` is odd but valid and visible, and the
    /// user typed it.
    static func separatorOnlyPatternStaysLiteral() async throws {
        let input = URL(fileURLWithPath: "/tmp/original.jpg")
        try expectEqual(NameTemplate("///").baseName(for: input, number: 1), "---")
    }

    /// The fallback exists for the case where nothing at all survives: a
    /// dot-only pattern would otherwise produce a nameless, hidden file.
    static func patternThatResolvesToNothingFallsBackToOriginal() async throws {
        let input = URL(fileURLWithPath: "/tmp/original.jpg")
        try expectEqual(NameTemplate("...").baseName(for: input, number: 1), "original",
                        "leeres Ergebnis fällt auf den Originalnamen zurück")
    }

    static func previewIncludesTargetExtension() async throws {
        let input = URL(fileURLWithPath: "/tmp/a3e32b79.jpg")
        let template = NameTemplate("AM-{nn}")
        try expectEqual(template.previewFilename(for: input, number: 4, format: .webp), "AM-04.webp")
        try expectEqual(template.previewFilename(for: input, number: 4, format: .jpeg), "AM-04.jpg")
    }
}

enum DestinationTests {

    static func outputLandsInChosenDirectory() async throws {
        let source = try TestImage.scratchDirectory("dest-source")
        let target = try TestImage.scratchDirectory("dest-target")
        let input = source.appendingPathComponent("photo.png")
        try TestImage.writePNG(width: 400, height: 300, to: input)

        let outcome = await TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, quality: 80, destinationDirectory: target)
        )

        let output = try require(outcome.successOutput)
        try expectEqual(output.deletingLastPathComponent().path, target.path)
        try expectEqual(output.lastPathComponent, "photo.jpg")
        try expect(
            !FileManager.default.fileExists(atPath: source.appendingPathComponent("photo.jpg").path),
            "im Quellordner darf nichts liegen, wenn ein Ziel gewählt ist"
        )
    }

    static func nilDestinationStillMeansNextToOriginal() async throws {
        let source = try TestImage.scratchDirectory("dest-default")
        let input = source.appendingPathComponent("photo.png")
        try TestImage.writePNG(width: 200, height: 200, to: input)

        let outcome = await TestSupport.engine().convert(input, settings: .init(target: .jpeg))

        let output = try require(outcome.successOutput)
        try expectEqual(output.deletingLastPathComponent().path, source.path)
    }

    static func unwritableDestinationFails() async throws {
        let source = try TestImage.scratchDirectory("dest-unwritable")
        let input = source.appendingPathComponent("photo.png")
        try TestImage.writePNG(width: 200, height: 200, to: input)

        let missing = source.appendingPathComponent("gibt-es-nicht")
        let outcome = await TestSupport.engine().convert(
            input,
            settings: .init(target: .jpeg, destinationDirectory: missing)
        )

        let reason = try require(outcome.failureReason, "Fehlschlag")
        guard case .destinationNotWritable = reason else {
            throw TestFailure(
                message: "erwartet .destinationNotWritable, bekommen \(reason)",
                file: #fileID,
                line: #line
            )
        }
    }

    /// Renaming and a target folder have to work together — that is the whole
    /// point for a folder full of UUID filenames.
    static func renamingIntoChosenDirectory() async throws {
        let source = try TestImage.scratchDirectory("combo-source")
        let target = try TestImage.scratchDirectory("combo-target")
        let input = source.appendingPathComponent("a3e32b79-01b1-4eff.jpg")
        try TestImage.writeJPEG(width: 600, height: 400, to: input)

        let outcome = await TestSupport.engine().convert(
            input,
            settings: .init(
                target: .webp,
                quality: 80,
                destinationDirectory: target,
                nameTemplate: NameTemplate("AM-Kalender-{nn}")
            ),
            number: 7
        )

        let output = try require(outcome.successOutput)
        try expectEqual(output.lastPathComponent, "AM-Kalender-07.webp")
        try expectEqual(output.deletingLastPathComponent().path, target.path)
    }
}

enum ReserverTests {

    static func reservesDistinctNamesForIdenticalRequests() async throws {
        let directory = try TestImage.scratchDirectory("reserve-same")
        let a = directory.appendingPathComponent("one.png")
        let b = directory.appendingPathComponent("two.png")

        let reserver = NameReserver()
        let template = NameTemplate("fixed")

        let first = reserver.reserve(for: a, format: .jpeg, in: directory, nameTemplate: template)
        let second = reserver.reserve(for: b, format: .jpeg, in: directory, nameTemplate: template)

        try expectEqual(first.lastPathComponent, "fixed.jpg")
        try expectEqual(second.lastPathComponent, "fixed-1.jpg",
                        "der zweite darf den ersten nicht überschreiben, auch ohne Datei auf Platte")
    }

    static func respectsFilesAlreadyOnDisk() async throws {
        let directory = try TestImage.scratchDirectory("reserve-existing")
        let input = directory.appendingPathComponent("shot.png")
        try Data().write(to: directory.appendingPathComponent("shot.jpg"))

        let reserved = NameReserver().reserve(for: input, format: .jpeg, in: directory)
        try expectEqual(reserved.lastPathComponent, "shot-1.jpg")
    }
}

enum BatchNamingTests {

    /// The race the reserver exists for: every file resolves to the same base
    /// name, all of them run in parallel, and no two may share an output path.
    static func parallelBatchWithFixedNameProducesDistinctFiles() async throws {
        let directory = try TestImage.scratchDirectory("batch-fixed-name")

        var inputs: [URL] = []
        for index in 0..<20 {
            let url = directory.appendingPathComponent("src-\(index).png")
            try TestImage.writePNG(width: 200, height: 150, to: url)
            inputs.append(url)
        }

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(target: .jpeg, quality: 80, nameTemplate: NameTemplate("sammlung")),
            maxConcurrent: 8
        )

        let outputs = outcomes.compactMap(\.successOutput)
        try expectEqual(outputs.count, 20, "alle müssen konvertiert werden")
        try expectEqual(
            Set(outputs.map(\.path)).count,
            20,
            "keine zwei Dateien dürfen denselben Pfad bekommen"
        )
    }

    /// Numbering must follow input order even though completion order does not.
    static func counterFollowsInputOrder() async throws {
        let directory = try TestImage.scratchDirectory("batch-numbering")

        var inputs: [URL] = []
        for index in 0..<12 {
            let url = directory.appendingPathComponent("src-\(index).png")
            // Varying sizes make completion order differ from input order.
            try TestImage.writePNG(width: 200 + index * 100, height: 150, to: url)
            inputs.append(url)
        }

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: inputs,
            settings: .init(target: .jpeg, quality: 80, nameTemplate: NameTemplate("AM-{nn}")),
            maxConcurrent: 8
        )

        let names = outcomes.compactMap(\.successOutput).map(\.lastPathComponent)
        let expected = (1...12).map { String(format: "AM-%02d.jpg", $0) }
        try expectEqual(names, expected, "Nummerierung folgt der Eingabereihenfolge")
    }

    /// Two files with the same name from different folders, collected into one
    /// destination — reachable only since the target-folder feature exists.
    static func sameFilenameFromDifferentFoldersDoesNotCollide() async throws {
        let folderA = try TestImage.scratchDirectory("collide-a")
        let folderB = try TestImage.scratchDirectory("collide-b")
        let target = try TestImage.scratchDirectory("collide-target")

        let a = folderA.appendingPathComponent("bild.png")
        let b = folderB.appendingPathComponent("bild.png")
        try TestImage.writePNG(width: 300, height: 200, to: a)
        try TestImage.writePNG(width: 400, height: 250, to: b)

        let runner = BatchRunner(engine: TestSupport.engineWithoutWebP())
        let outcomes = await runner.run(
            inputs: [a, b],
            settings: .init(target: .jpeg, quality: 80, destinationDirectory: target)
        )

        let outputs = outcomes.compactMap(\.successOutput)
        try expectEqual(outputs.count, 2, "beide müssen durchlaufen")
        try expectEqual(Set(outputs.map(\.path)).count, 2, "beide brauchen eigene Pfade")
    }
}

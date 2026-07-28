import Foundation

/// Picks a destination path that does not exist yet.
///
/// The hard rule of this app: never overwrite anything. If `bild.webp` is
/// taken, the output becomes `bild-1.webp`, then `bild-2.webp`. This also
/// covers converting a file into its own format — `bild.png` → `bild-1.png`
/// rather than clobbering the original.
public enum OutputNaming {
    public static func destination(
        for input: URL,
        format: TargetFormat,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension

        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

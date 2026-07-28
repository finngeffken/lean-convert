import Foundation

/// Picks a destination path that does not exist yet.
///
/// The hard rule of this app: never overwrite anything. If `bild.webp` is
/// taken, the output becomes `bild-1.webp`, then `bild-2.webp`. This also
/// covers converting a file into its own format — `bild.png` → `bild-1.png`
/// rather than clobbering the original.
///
/// A single `NameReserver` does the actual work so that batch runs and one-off
/// conversions share one implementation; passing a reserver additionally keeps
/// parallel files in the same batch from claiming the same name.
public enum OutputNaming {
    public static func destination(
        for input: URL,
        format: TargetFormat,
        in directory: URL? = nil,
        nameTemplate: NameTemplate = .keepOriginal,
        number: Int = 1,
        reserver: NameReserver? = nil
    ) -> URL {
        (reserver ?? NameReserver()).reserve(
            for: input,
            format: format,
            in: directory,
            nameTemplate: nameTemplate,
            number: number
        )
    }
}

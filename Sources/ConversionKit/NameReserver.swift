import Foundation

/// Hands out output paths that collide with neither an existing file nor
/// another file in the same batch.
///
/// The filesystem check alone is not enough once a batch runs in parallel: two
/// inputs can resolve to the same output name — same filename from two source
/// folders into one destination, or a rename pattern without a `{n}` counter —
/// and both would see the path as free at the same moment. Reserved names are
/// therefore remembered, under a lock, for the lifetime of the batch.
public final class NameReserver: @unchecked Sendable {
    private let lock = NSLock()
    private var reserved = Set<String>()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func reserve(
        for input: URL,
        format: some OutputFormat,
        in directory: URL? = nil,
        nameTemplate: NameTemplate = .keepOriginal,
        number: Int = 1
    ) -> URL {
        let targetDirectory = directory ?? input.deletingLastPathComponent()
        let base = nameTemplate.baseName(for: input, number: number)
        let ext = format.fileExtension

        lock.lock()
        defer { lock.unlock() }

        var candidate = targetDirectory.appendingPathComponent("\(base).\(ext)")
        var counter = 1
        while reserved.contains(candidate.path) || fileManager.fileExists(atPath: candidate.path) {
            candidate = targetDirectory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }

        reserved.insert(candidate.path)
        return candidate
    }
}

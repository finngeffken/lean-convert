import SwiftUI
import QuickLookThumbnailing

/// Supplies preview images for the queue.
///
/// QuickLook is the right tool here rather than decoding the files ourselves:
/// it is native, it caches at system level, and it produces a poster frame for
/// videos for free — so one code path covers both modes.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]
    private var inFlight: Set<String> = []

    private static let side: CGFloat = 320

    func thumbnail(for url: URL) -> NSImage? {
        images[url.path]
    }

    /// Idempotent: rows call this on appear and may appear repeatedly while
    /// scrolling.
    func load(_ url: URL) {
        let key = url.path
        guard images[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Self.side, height: Self.side),
            scale: 2,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            Task { @MainActor in
                self.inFlight.remove(key)
                guard let representation else { return }
                self.images[key] = representation.nsImage
            }
        }
    }

    /// Dropping a file from the queue should not keep its preview around.
    func forget(_ url: URL) {
        images.removeValue(forKey: url.path)
    }
}

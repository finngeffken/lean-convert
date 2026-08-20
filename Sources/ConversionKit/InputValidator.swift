import Foundation
import UniformTypeIdentifiers

/// Keeps folders, videos and archives out before a batch starts.
///
/// Rejecting at the drop zone rather than mid-run means the user finds out
/// immediately, instead of reading failure rows for files that never belonged.
public enum InputValidator {
    public static func isSupportedImage(_ url: URL) -> Bool {
        conforms(url, to: .image)
    }

    public static func isSupportedVideo(_ url: URL) -> Bool {
        conforms(url, to: .movie)
    }

    private static func conforms(_ url: URL, to kind: UTType) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }

        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }

        return type.conforms(to: kind)
    }

    public static func partition(_ urls: [URL]) -> (accepted: [URL], rejected: [URL]) {
        split(urls, by: isSupportedImage)
    }

    public static func partitionVideos(_ urls: [URL]) -> (accepted: [URL], rejected: [URL]) {
        split(urls, by: isSupportedVideo)
    }

    private static func split(
        _ urls: [URL],
        by accepts: (URL) -> Bool
    ) -> (accepted: [URL], rejected: [URL]) {
        var accepted: [URL] = []
        var rejected: [URL] = []
        for url in urls {
            if accepts(url) {
                accepted.append(url)
            } else {
                rejected.append(url)
            }
        }
        return (accepted, rejected)
    }
}

/// Preselects a sensible target for HEIC drops — the common case being iPhone
/// photos that need to become ordinary JPEGs.
public enum FormatSuggestion {
    /// Returns a suggestion only when the whole drop is HEIC, so a mixed batch
    /// never has its format quietly changed.
    public static func suggestedTarget(for urls: [URL]) async -> TargetFormat? {
        guard !urls.isEmpty else { return nil }

        let heicExtensions: Set<String> = ["heic", "heif", "heics"]
        let allHEIC = urls.allSatisfy {
            heicExtensions.contains($0.pathExtension.lowercased())
        }
        guard allHEIC else { return nil }

        // Probing every file in a large drop is not worth the wait; a sample
        // answers "is there transparency here" well enough for a preselection.
        var hasAlpha = false
        for url in urls.prefix(5) {
            if let info = try? await ImageProbe.probe(url), info.hasAlpha {
                hasAlpha = true
                break
            }
        }

        return hasAlpha ? .png : .jpeg
    }
}

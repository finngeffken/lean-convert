import Foundation
import UniformTypeIdentifiers

/// Keeps folders, videos and archives out before a batch starts.
///
/// Rejecting at the drop zone rather than mid-run means the user finds out
/// immediately, instead of reading failure rows for files that never belonged.
public enum InputValidator {
    public static func isSupportedImage(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }

        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        else { return false }

        return type.conforms(to: .image)
    }

    public static func partition(_ urls: [URL]) -> (accepted: [URL], rejected: [URL]) {
        var accepted: [URL] = []
        var rejected: [URL] = []
        for url in urls {
            if isSupportedImage(url) {
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
    public static func suggestedTarget(for urls: [URL]) -> TargetFormat? {
        guard !urls.isEmpty else { return nil }

        let heicExtensions: Set<String> = ["heic", "heif", "heics"]
        let allHEIC = urls.allSatisfy {
            heicExtensions.contains($0.pathExtension.lowercased())
        }
        guard allHEIC else { return nil }

        // Probing every file in a large drop is not worth the wait; a sample
        // answers "is there transparency here" well enough for a preselection.
        let sample = urls.prefix(5)
        let hasAlpha = sample.contains { (try? ImageProbe.probe($0))?.hasAlpha == true }

        return hasAlpha ? .png : .jpeg
    }
}

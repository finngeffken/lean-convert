import AppKit
import SwiftUI

/// Settings storage. A snapshot run uses its own domain so rendering sample
/// states can never overwrite the user's remembered settings.
enum AppDefaults {
    static let store: UserDefaults = Snapshot.isActive
        ? UserDefaults(suiteName: "de.geffken.leanconvert.snapshot")!
        : .standard
}

/// `LEANCONVERT_SNAPSHOT_OUT=<dir> LEANCONVERT_SNAPSHOT_FILES=<paths, one per
/// line> LeanConvert --snapshot` renders the window in three states to PNGs
/// and quits.
///
/// Exists because screen recording is unavailable to the build environment:
/// the app draws its own view hierarchy into a bitmap, which needs no
/// permission, so the design can be checked rather than guessed.
@MainActor
enum Snapshot {
    nonisolated static let isActive = CommandLine.arguments.contains("--snapshot")

    // Paths come from the environment, not from arguments: once macOS knows
    // the app as an image opener, file paths on the command line are treated
    // as documents to open, and SwiftUI then never creates its window.
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["LEANCONVERT_SNAPSHOT_OUT"].map { URL(fileURLWithPath: $0) }
    }

    static var samples: [URL] {
        (ProcessInfo.processInfo.environment["LEANCONVERT_SNAPSHOT_FILES"] ?? "")
            .split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    static var images: ConverterViewModel?
    static var outputScratch: URL?

    static func register(images: ConverterViewModel) {
        guard isActive, self.images == nil else { return }
        self.images = images
        Task { await run() }
    }

    private static func run() async {
        guard let out = outputDirectory, let images else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        render(out.appendingPathComponent("1-leer.png"))

        FileHandle.standardError.write(Data("samples: \(samples.count) queue-before: \(images.queue.count)\n".utf8))
        images.enqueue(samples)
        FileHandle.standardError.write(Data("queue-after: \(images.queue.count)\n".utf8))
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        render(out.appendingPathComponent("2-warteschlange.png"))

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("leanconvert-snapshot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        images.setDestinationForSnapshot(scratch)
        images.target = .webp
        images.maxEdgeText = "1600"
        images.convert()
        while images.isRunning { try? await Task.sleep(nanoseconds: 200_000_000) }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        render(out.appendingPathComponent("3-ergebnis.png"))

        NSApp.terminate(nil)
    }

    private static func render(_ url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let frame = window.contentView?.superview ?? window.contentView else { return }
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// A ScrollView, except during a snapshot run: macOS 26 scroll views are not
/// drawn by `cacheDisplay`, so the snapshot lays the same content out flat.
struct Scrollable<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if Snapshot.isActive {
            VStack(spacing: 0) { content(); Spacer(minLength: 0) }
        } else {
            ScrollView { content() }
        }
    }
}

/// `.inspector` normally; a plain trailing column during a snapshot run, since
/// the glass inspector pane cannot be captured either.
struct InspectorHost<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let panel: () -> Panel

    func body(content: Content) -> some View {
        if Snapshot.isActive {
            HStack(spacing: 0) {
                content
                if isPresented {
                    Divider()
                    panel()
                        .frame(width: 290)
                        .background(Palette.surface)
                }
            }
        } else {
            content.inspector(isPresented: $isPresented) {
                panel().inspectorColumnWidth(min: 260, ideal: 290, max: 340)
            }
        }
    }
}

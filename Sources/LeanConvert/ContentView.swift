import SwiftUI
import UniformTypeIdentifiers
import ConversionKit

enum Mode: String, CaseIterable, Identifiable {
    case images
    case video

    var id: String { rawValue }
    var title: String { self == .images ? "Bilder" : "Video" }
    var noun: String { self == .images ? "Bilder" : "Videos" }
    var formats: [String] {
        self == .images
            ? ["HEIC", "JPEG", "PNG", "WebP", "AVIF"]
            : ["MOV", "MP4", "M4V"]
    }
    var contentTypes: [UTType] { self == .images ? [.image] : [.movie] }

    func count(_ n: Int) -> String {
        switch self {
        case .images: "\(n) \(n == 1 ? "Bild" : "Bilder")"
        case .video: "\(n) \(n == 1 ? "Video" : "Videos")"
        }
    }
}

struct ContentView: View {
    @StateObject private var images = ConverterViewModel()
    @StateObject private var videos = VideoViewModel()
    @StateObject private var thumbnails = ThumbnailStore()
    @ObservedObject private var inbound = InboundFiles.shared

    @State private var mode: Mode = .images
    @State private var showInspector = true
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            canvas
            if isRunning || (!queue.isEmpty && results.isEmpty) {
                actionBar
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: queue.isEmpty)
        .animation(.spring(duration: 0.35), value: results.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.workCanvas)
        .overlay { dropHighlight }
        .dropDestination(for: URL.self) { urls, _ in
            enqueue(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Label("Einstellungen", systemImage: "slider.horizontal.3")
                }
                .help("Einstellungen ein- und ausblenden (⌥⌘I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .modifier(InspectorHost(isPresented: $showInspector) {
            Scrollable {
                VStack(alignment: .leading, spacing: 22) {
                    switch mode {
                    case .images: ImageInspector(model: images)
                    case .video: VideoInspector(model: videos)
                    }
                }
                .padding(18)
            }
        })
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: mode.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { enqueue(urls) }
        }
        .background { shortcuts }
        .tint(Palette.accent)
        .task { await videos.detectCodecs() }
        .onAppear { Snapshot.register(images: images) }
        .onChange(of: inbound.urls) { _, urls in
            guard !urls.isEmpty else { return }
            route(inbound.take())
        }
    }

    // MARK: - State

    private var queue: [URL] { mode == .images ? images.queue : videos.queue }
    private var results: [ConversionOutcome] { mode == .images ? images.results : videos.results }
    private var isRunning: Bool { mode == .images ? images.isRunning : videos.isRunning }
    private var canConvert: Bool { mode == .images ? images.canConvert : videos.canConvert }

    private func enqueue(_ urls: [URL]) {
        withAnimation(.spring(duration: 0.35)) {
            mode == .images ? images.enqueue(urls) : videos.enqueue(urls)
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if !results.isEmpty && !isRunning {
            resultsView
        } else if !queue.isEmpty {
            queueView
        } else {
            EmptyState(mode: mode) { importing = true }
        }
    }

    private var queueView: some View {
        Scrollable {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mode.count(queue.count))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(byteText(queue.reduce(0) { $0 + fileSize($1) }))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Hinzufügen…") { importing = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .disabled(isRunning)
                    Button("Alle entfernen") {
                        withAnimation { mode == .images ? images.clearQueue() : videos.clearQueue() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isRunning)
                }
                .font(.callout)

                TileGrid {
                    ForEach(queue, id: \.path) { url in
                        MediaTile(
                            url: url,
                            title: url.lastPathComponent,
                            detail: byteText(fileSize(url)),
                            onRemove: isRunning ? nil : {
                                withAnimation(.spring(duration: 0.3)) {
                                    thumbnails.forget(url)
                                    mode == .images ? images.remove(url) : videos.remove(url)
                                }
                            },
                            thumbnails: thumbnails
                        )
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 100)
        }
    }

    private var resultsView: some View {
        let successes = results.compactMap { outcome -> (Int, Int)? in
            if case .success(_, _, let before, let after) = outcome { return (before, after) }
            return nil
        }
        let failed = results.count - successes.count

        return Scrollable {
            VStack(alignment: .leading, spacing: 24) {
                ResultHero(
                    before: successes.reduce(0) { $0 + $1.0 },
                    after: successes.reduce(0) { $0 + $1.1 },
                    converted: successes.count,
                    failed: failed,
                    onAgain: {
                        withAnimation { mode == .images ? images.clearResults() : videos.clearResults() }
                    },
                    onDone: {
                        withAnimation {
                            if mode == .images {
                                images.clearResults(); images.clearQueue()
                            } else {
                                videos.clearResults(); videos.clearQueue()
                            }
                        }
                    }
                )

                TileGrid {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, outcome in
                        resultTile(outcome)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private func resultTile(_ outcome: ConversionOutcome) -> some View {
        switch outcome {
        case .success(_, let output, let before, let after):
            let saved = before > 0 ? Double(before - after) / Double(before) : 0
            let percent = Int((abs(saved) * 100).rounded())
            MediaTile(
                url: output,
                title: output.lastPathComponent,
                detail: "\(byteText(before)) → \(byteText(after))",
                badge: (saved >= 0 ? "−\(percent) %" : "+\(percent) %",
                        saved >= 0 ? Palette.success : Palette.failure),
                onReveal: { NSWorkspace.shared.activateFileViewerSelecting([output]) },
                thumbnails: thumbnails
            )
        case .failure(let input, let reason):
            MediaTile(
                url: input,
                title: input.lastPathComponent,
                detail: reason.message,
                failed: reason != .cancelled,
                thumbnails: thumbnails
            )
        }
    }

    // MARK: - Action bar

    /// Floating glass capsule: the content scrolls underneath, and the one
    /// action the window is for is always in reach.
    private var actionBar: some View {
        HStack(spacing: 14) {
            if isRunning {
                ProgressView(value: progressValue)
                    .frame(width: 140)
                Text(progressText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Abbrechen") {
                    mode == .images ? images.cancel() : videos.cancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            } else {
                Text(settingsSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    mode == .images ? images.convert() : videos.convert()
                } label: {
                    Label("\(mode.count(queue.count)) konvertieren", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(GradientButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canConvert)
                .help("⌘↩")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassCapsule()
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
    }

    private var progressValue: Double {
        mode == .images
            ? Double(images.completed) / Double(max(1, images.total))
            : videos.fractionalProgress
    }

    private var progressText: String {
        if mode == .video, let name = videos.currentFileName {
            return "\(videos.completed + 1) von \(videos.total) · \(name)"
        }
        let done = mode == .images ? images.completed : videos.completed
        let total = mode == .images ? images.total : videos.total
        return "\(done) von \(total)"
    }

    /// What is about to happen, said in one line next to the button.
    private var settingsSummary: String {
        if mode == .images {
            var parts = [images.target.displayName]
            if images.target.supportsQuality { parts.append("Q \(Int(images.quality))") }
            if let edge = images.maxEdge { parts.append("≤ \(edge) px") }
            return parts.joined(separator: " · ")
        }
        var parts = [videos.codec.displayName, "CRF \(Int(videos.crf))"]
        if let edge = videos.maxEdge { parts.append("≤ \(edge) px") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Drop and shortcuts

    @ViewBuilder
    private var dropHighlight: some View {
        if dropTargeted {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(Palette.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(10)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Invisible buttons that carry the keyboard shortcuts.
    private var shortcuts: some View {
        Group {
            Button("") { importing = true }.keyboardShortcut("o")
            Button("") { mode = .images }.keyboardShortcut("1")
            Button("") { mode = .video }.keyboardShortcut("2")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: - Routing

    /// Files arriving on the Dock icon do not know which mode is showing, so
    /// they are sorted by type and the mode follows them when it is unambiguous.
    private func route(_ urls: [URL]) {
        let (pictures, rest) = InputValidator.partition(urls)
        let (movies, _) = InputValidator.partitionVideos(rest)

        if !pictures.isEmpty { images.enqueue(pictures) }
        if !movies.isEmpty { videos.enqueue(movies) }

        if pictures.isEmpty && !movies.isEmpty {
            mode = .video
        } else if movies.isEmpty && !pictures.isEmpty {
            mode = .images
        }
    }
}

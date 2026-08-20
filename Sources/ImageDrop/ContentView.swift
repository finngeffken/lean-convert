import SwiftUI
import ConversionKit

enum Mode: String, CaseIterable, Identifiable {
    case images
    case video

    var id: String { rawValue }
    var title: String { self == .images ? "Bilder" : "Video" }
    var noun: String { self == .images ? "Bilder" : "Videos" }
    var symbol: String { self == .images ? "photo.on.rectangle.angled" : "film" }
}

struct ContentView: View {
    @StateObject private var images = ConverterViewModel()
    @StateObject private var videos = VideoViewModel()
    @StateObject private var thumbnails = ThumbnailStore()
    @ObservedObject private var inbound = InboundFiles.shared
    @State private var mode: Mode = .images

    var body: some View {
        HStack(spacing: 0) {
            workArea
                .frame(minWidth: 420)

            Divider()

            inspector
                .frame(width: 300)
                .background(.regularMaterial)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
        }
        .task { await videos.detectCodecs() }
        .onChange(of: inbound.urls) { _, urls in
            guard !urls.isEmpty else { return }
            route(inbound.take())
        }
    }

    // MARK: - Work area

    private var queue: [URL] { mode == .images ? images.queue : videos.queue }
    private var results: [ConversionOutcome] { mode == .images ? images.results : videos.results }
    private var isRunning: Bool { mode == .images ? images.isRunning : videos.isRunning }

    @ViewBuilder
    private var workArea: some View {
        VStack(spacing: 12) {
            DropZone(
                compact: !queue.isEmpty,
                noun: mode.noun,
                symbol: mode.symbol,
                onDrop: { urls in
                    mode == .images ? images.enqueue(urls) : videos.enqueue(urls)
                }
            )

            if !queue.isEmpty {
                QueueList(
                    queue: queue,
                    rejectedCount: mode == .images ? images.rejectedCount : videos.rejectedCount,
                    isRunning: isRunning,
                    onRemove: { url in
                        thumbnails.forget(url)
                        mode == .images ? images.remove(url) : videos.remove(url)
                    },
                    onClear: {
                        mode == .images ? images.clearQueue() : videos.clearQueue()
                    },
                    thumbnails: thumbnails
                )
            }

            if !results.isEmpty {
                ResultsList(
                    results: results,
                    summary: summary,
                    onClear: {
                        mode == .images ? images.clearResults() : videos.clearResults()
                    },
                    thumbnails: thumbnails
                )
                .frame(maxHeight: queue.isEmpty ? .infinity : 240)
            }
        }
        .padding(16)
    }

    private var summary: String {
        if mode == .images {
            var parts = ["\(images.successCount) konvertiert"]
            if images.failureCount > 0 { parts.append("\(images.failureCount) fehlgeschlagen") }
            if let saved = savedText(images.totalSaved) { parts.append(saved) }
            return parts.joined(separator: " · ")
        }
        var parts = ["\(videos.successCount) konvertiert"]
        let realFailures = videos.failureCount - videos.cancelledCount
        if realFailures > 0 { parts.append("\(realFailures) fehlgeschlagen") }
        if videos.cancelledCount > 0 { parts.append("\(videos.cancelledCount) abgebrochen") }
        if let saved = savedText(videos.totalSaved) { parts.append(saved) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        switch mode {
        case .images: ImageInspector(model: images)
        case .video: VideoInspector(model: videos)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if isRunning {
                progressArea
            }

            Spacer()

            if isRunning {
                Button("Abbrechen") {
                    mode == .images ? images.cancel() : videos.cancel()
                }
            }

            Button(convertLabel) {
                mode == .images ? images.convert() : videos.convert()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(mode == .images ? !images.canConvert : !videos.canConvert)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var progressArea: some View {
        if mode == .images {
            ProgressView(value: Double(images.completed), total: Double(max(1, images.total)))
                .frame(width: 140)
            Text("\(images.completed) von \(images.total)")
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            // Includes the fraction of the file in flight, so a long encode
            // does not look stalled.
            ProgressView(value: videos.fractionalProgress)
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(videos.completed) von \(videos.total)")
                    .font(.callout).monospacedDigit()
                if let name = videos.currentFileName {
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var convertLabel: String {
        let count = queue.count
        guard count > 0 else { return "Konvertieren" }
        let noun = mode == .images ? "Bild" : "Video"
        return "\(count) \(count == 1 ? noun : noun + "s") konvertieren"
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

// MARK: - Image inspector

private struct ImageInspector: View {
    @ObservedObject var model: ConverterViewModel

    var body: some View {
        Form {
            Section("Format") {
                Picker("Ziel", selection: Binding(
                    get: { model.target },
                    set: { model.selectFormat($0) }
                )) {
                    ForEach(model.availableFormats) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)

                if model.target.supportsQuality {
                    LabeledContent("Qualität") {
                        SliderRow(
                            value: $model.quality,
                            range: 1...model.maxQuality,
                            caption: model.target == .avif
                                ? "AVIF geht bis 99 — bei 100 schreibt macOS keine Datei."
                                : "Höher ist besser."
                        )
                    }
                } else {
                    LabeledContent("Qualität") {
                        Text("verlustfrei")
                            .foregroundStyle(.secondary)
                    }
                }

                MaxEdgeField(text: $model.maxEdgeText, isActive: model.maxEdge != nil)
            }

            Section("Ausgabe") {
                RenameField(pattern: $model.renamePattern, preview: model.renamePreview)
                DestinationField(
                    label: model.destinationLabel,
                    isCustom: model.destinationDirectory != nil,
                    fullPath: model.destinationDirectory?.path,
                    onChoose: { model.chooseDestination() },
                    onReset: { model.useSourceDirectory() }
                )
            }

            if !model.supportsWebP {
                Section {
                    Label("cwebp fehlt — WebP nicht verfügbar.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Video inspector

private struct VideoInspector: View {
    @ObservedObject var model: VideoViewModel

    var body: some View {
        Form {
            if !model.isAvailable {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("ffmpeg fehlt", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.medium))
                        Text("Einmalig ./fetch-ffmpeg.sh ausführen und neu bauen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.orange)
                }
            }

            Section("Codec") {
                if !model.availableCodecs.isEmpty {
                    Picker("Codec", selection: $model.codec) {
                        ForEach(model.availableCodecs) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)

                    Text(model.codec.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Qualität") {
                    SliderRow(
                        value: $model.crf,
                        range: Double(model.codec.crfRange.lowerBound)...Double(model.codec.crfRange.upperBound),
                        // CRF runs the other way round to the image slider, and
                        // saying so beats letting people find out the hard way.
                        caption: "CRF — kleiner ist besser, bis \(model.codec.crfRange.upperBound)."
                    )
                }

                MaxEdgeField(text: $model.maxEdgeText, isActive: model.maxEdge != nil)
                Toggle("Tonspur behalten", isOn: $model.keepAudio)
            }

            Section("Ausgabe") {
                RenameField(pattern: $model.renamePattern, preview: model.renamePreview)
                DestinationField(
                    label: model.destinationLabel,
                    isCustom: model.destinationDirectory != nil,
                    fullPath: model.destinationDirectory?.path,
                    onChoose: { model.chooseDestination() },
                    onReset: { model.useSourceDirectory() }
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Inspector building blocks

private struct SliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: 1)
                Text("\(Int(value))")
                    .monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MaxEdgeField: View {
    @Binding var text: String
    let isActive: Bool

    var body: some View {
        LabeledContent("Max. Kante") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TextField("unbegrenzt", text: $text)
                        .frame(width: 80)
                    Text("px").foregroundStyle(.secondary)
                }
                if isActive {
                    Text("Nur verkleinernd.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RenameField: View {
    @Binding var pattern: String
    let preview: String?

    var body: some View {
        LabeledContent("Umbenennen") {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Originalname", text: $pattern)
                Text(preview ?? "{name}, {n}, {nn}, {nnn}")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct DestinationField: View {
    let label: String
    let isCustom: Bool
    let fullPath: String?
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        LabeledContent("Ziel") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: isCustom ? "folder" : "arrow.turn.down.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(fullPath ?? "Jede Datei landet neben ihrem Original.")
                }
                HStack(spacing: 8) {
                    Button("Ordner wählen…", action: onChoose)
                        .controlSize(.small)
                    if isCustom {
                        Button("Zurücksetzen", action: onReset)
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

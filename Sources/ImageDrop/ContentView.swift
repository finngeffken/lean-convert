import SwiftUI
import ConversionKit

enum Mode: String, CaseIterable, Identifiable {
    case images
    case video

    var id: String { rawValue }
    var title: String { self == .images ? "Bilder" : "Video" }
}

struct ContentView: View {
    @StateObject private var images = ConverterViewModel()
    @StateObject private var videos = VideoViewModel()
    @ObservedObject private var inbound = InboundFiles.shared
    @State private var mode: Mode = .images

    var body: some View {
        VStack(spacing: 0) {
            Picker("Modus", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 4)

            ScrollView {
                Group {
                    switch mode {
                    case .images: ImagePane(model: images)
                    case .video: VideoPane(model: videos)
                    }
                }
                .padding(20)
            }

            Divider()
            actionBar
        }
        .task { await videos.detectCodecs() }
        .onChange(of: inbound.urls) { _, urls in
            guard !urls.isEmpty else { return }
            route(inbound.take())
        }
    }

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

    // MARK: - Action bar

    private var isRunning: Bool {
        mode == .images ? images.isRunning : videos.isRunning
    }

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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var progressArea: some View {
        if mode == .images {
            ProgressView(value: Double(images.completed), total: Double(max(1, images.total)))
                .frame(maxWidth: 160)
            Text("\(images.completed)/\(images.total)")
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            // Includes the fraction of the file in flight, so a long encode
            // does not look stalled.
            ProgressView(value: videos.fractionalProgress)
                .frame(maxWidth: 160)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(videos.completed)/\(videos.total)")
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
        let count = mode == .images ? images.queue.count : videos.queue.count
        let noun = mode == .images ? "Bild" : "Video"
        guard count > 0 else { return "Konvertieren" }
        return "\(count) \(count == 1 ? noun : noun + "s") konvertieren"
    }
}

// MARK: - Image pane

private struct ImagePane: View {
    @ObservedObject var model: ConverterViewModel

    var body: some View {
        VStack(spacing: 16) {
            DropZone(
                hasQueue: !model.queue.isEmpty,
                isRunning: model.isRunning,
                noun: "Bilder",
                onDrop: { model.enqueue($0) }
            )

            if !model.queue.isEmpty {
                QueuePanel(
                    queue: model.queue,
                    rejectedCount: model.rejectedCount,
                    isRunning: model.isRunning,
                    noun: "Bilder",
                    onRemove: { model.remove($0) },
                    onClear: { model.clearQueue() }
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                Picker("Zielformat", selection: Binding(
                    get: { model.target },
                    set: { model.selectFormat($0) }
                )) {
                    ForEach(model.availableFormats) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("Qualität")
                    Slider(value: $model.quality, in: 1...model.maxQuality, step: 1)
                        .disabled(!model.target.supportsQuality)
                    Text("\(Int(model.quality))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                        .foregroundStyle(model.target.supportsQuality ? .primary : .tertiary)
                }

                if !model.target.supportsQuality {
                    Text("PNG ist verlustfrei — die Qualität hat keinen Effekt.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.target == .avif {
                    Text("AVIF geht bis 99 — bei 100 kann macOS keine AVIF-Datei schreiben.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                MaxEdgeRow(text: $model.maxEdgeText, isActive: model.maxEdge != nil)

                Divider()

                RenameRow(pattern: $model.renamePattern, preview: model.renamePreview)
                DestinationRow(
                    label: model.destinationLabel,
                    isCustom: model.destinationDirectory != nil,
                    fullPath: model.destinationDirectory?.path,
                    onChoose: { model.chooseDestination() },
                    onReset: { model.useSourceDirectory() }
                )

                if !model.supportsWebP {
                    Text("WebP nicht verfügbar: cwebp fehlt im App-Bundle.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            if !model.results.isEmpty {
                ResultsPanel(
                    results: model.results,
                    summary: summary,
                    onClear: { model.clearResults() }
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var summary: String {
        var parts = ["\(model.successCount) konvertiert"]
        if model.failureCount > 0 { parts.append("\(model.failureCount) fehlgeschlagen") }
        if let saved = savedText(model.totalSaved) { parts.append(saved) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Video pane

private struct VideoPane: View {
    @ObservedObject var model: VideoViewModel

    var body: some View {
        VStack(spacing: 16) {
            if !model.isAvailable {
                unavailableNotice
            }

            DropZone(
                hasQueue: !model.queue.isEmpty,
                isRunning: model.isRunning,
                noun: "Videos",
                onDrop: { model.enqueue($0) }
            )

            if !model.queue.isEmpty {
                QueuePanel(
                    queue: model.queue,
                    rejectedCount: model.rejectedCount,
                    isRunning: model.isRunning,
                    noun: "Videos",
                    onRemove: { model.remove($0) },
                    onClear: { model.clearQueue() }
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                if !model.availableCodecs.isEmpty {
                    Picker("Codec", selection: $model.codec) {
                        ForEach(model.availableCodecs) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(model.codec.hint)
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Text("Qualität")
                    Slider(
                        value: $model.crf,
                        in: Double(model.codec.crfRange.lowerBound)...Double(model.codec.crfRange.upperBound),
                        step: 1
                    )
                    Text("\(Int(model.crf))")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }

                // The image slider means "higher is better"; CRF means the
                // opposite. Naming it beats letting people find out the hard way.
                Text("CRF — hier ist **kleiner besser**, umgekehrt zum Bild-Regler. \(Int(model.crf)) von \(model.codec.crfRange.upperBound).")
                    .font(.caption).foregroundStyle(.secondary)

                MaxEdgeRow(text: $model.maxEdgeText, isActive: model.maxEdge != nil)

                Toggle("Tonspur behalten", isOn: $model.keepAudio)

                Divider()

                RenameRow(pattern: $model.renamePattern, preview: model.renamePreview)
                DestinationRow(
                    label: model.destinationLabel,
                    isCustom: model.destinationDirectory != nil,
                    fullPath: model.destinationDirectory?.path,
                    onChoose: { model.chooseDestination() },
                    onReset: { model.useSourceDirectory() }
                )
            }

            if !model.results.isEmpty {
                ResultsPanel(
                    results: model.results,
                    summary: summary,
                    onClear: { model.clearResults() }
                )
            }

            Spacer(minLength: 0)
        }
    }

    private var unavailableNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ffmpeg fehlt — Video ist nicht verfügbar.")
                .font(.callout.weight(.medium))
            Text("Einmalig `./fetch-ffmpeg.sh` im Projektordner ausführen und die App neu bauen.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summary: String {
        var parts = ["\(model.successCount) konvertiert"]
        let realFailures = model.failureCount - model.cancelledCount
        if realFailures > 0 { parts.append("\(realFailures) fehlgeschlagen") }
        if model.cancelledCount > 0 { parts.append("\(model.cancelledCount) abgebrochen") }
        if let saved = savedText(model.totalSaved) { parts.append(saved) }
        return parts.joined(separator: " · ")
    }
}

private struct MaxEdgeRow: View {
    @Binding var text: String
    let isActive: Bool

    var body: some View {
        HStack {
            Text("Max. Kante")
            TextField("unbegrenzt", text: $text)
                .frame(width: 90)
            Text("px").foregroundStyle(.secondary)
            Spacer()
            if isActive {
                Text("nur verkleinernd")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

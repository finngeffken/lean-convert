import SwiftUI
import ConversionKit

enum Mode: String, CaseIterable, Identifiable {
    case images
    case video

    var id: String { rawValue }
    var title: String { self == .images ? "Bilder" : "Video" }
    var noun: String { self == .images ? "Bilder" : "Videos" }
    var symbol: String { self == .images ? "photo.on.rectangle.angled" : "film" }
    var railSymbol: String { self == .images ? "photo" : "film" }
}

struct ContentView: View {
    @StateObject private var images = ConverterViewModel()
    @StateObject private var videos = VideoViewModel()
    @StateObject private var thumbnails = ThumbnailStore()
    @ObservedObject private var inbound = InboundFiles.shared
    @State private var mode: Mode = .images

    var body: some View {
        HStack(spacing: 0) {
            ModeRail(mode: $mode)

            Divider()

            workArea
                .frame(minWidth: 400)
                .background(Palette.canvas)

            Divider()

            inspector
                .frame(width: Metrics.inspectorWidth)
                .background(Palette.surface)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .tint(Palette.accent)
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
    private var rejectedCount: Int { mode == .images ? images.rejectedCount : videos.rejectedCount }

    @ViewBuilder
    private var workArea: some View {
        VStack(spacing: Metrics.gutter) {
            DropZone(
                compact: !queue.isEmpty,
                noun: mode.noun,
                symbol: mode.symbol,
                onDrop: { urls in
                    mode == .images ? images.enqueue(urls) : videos.enqueue(urls)
                }
            )

            if !queue.isEmpty {
                ListCard(
                    title: "\(queue.count) in der Warteschlange",
                    note: rejectedCount > 0 ? "· \(rejectedCount) übersprungen" : nil,
                    noteHelp: "Passt nicht in diesen Modus.",
                    actionTitle: "Leeren",
                    actionEnabled: !isRunning,
                    action: { mode == .images ? images.clearQueue() : videos.clearQueue() }
                ) {
                    ForEach(queue, id: \.path) { url in
                        FileRow(url: url, subtitle: nil, thumbnails: thumbnails) {
                            Button {
                                thumbnails.forget(url)
                                mode == .images ? images.remove(url) : videos.remove(url)
                            } label: {
                                Image(systemName: "xmark")
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .disabled(isRunning)
                            .help("Aus der Warteschlange nehmen")
                        }
                        Divider().padding(.leading, 56)
                    }
                }
            }

            if !results.isEmpty {
                ListCard(
                    title: summary,
                    actionTitle: "Leeren",
                    actionEnabled: true,
                    action: { mode == .images ? images.clearResults() : videos.clearResults() }
                ) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, outcome in
                        ResultRow(outcome: outcome, thumbnails: thumbnails)
                        Divider().padding(.leading, 56)
                    }
                }
                .frame(maxHeight: queue.isEmpty ? .infinity : 250)
            }
        }
        .padding(Metrics.gutter)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch mode {
                case .images: ImageInspector(model: images)
                case .video: VideoInspector(model: videos)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if isRunning { progressArea }

            Spacer()

            if isRunning {
                Button("Abbrechen") {
                    mode == .images ? images.cancel() : videos.cancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button(convertLabel) {
                mode == .images ? images.convert() : videos.convert()
            }
            .buttonStyle(AccentButton())
            .keyboardShortcut(.defaultAction)
            .disabled(mode == .images ? !images.canConvert : !videos.canConvert)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var progressArea: some View {
        if mode == .images {
            ProgressView(value: Double(images.completed), total: Double(max(1, images.total)))
                .frame(width: 130)
            Text("\(images.completed) von \(images.total)")
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            // Includes the fraction of the file in flight, so a long encode
            // does not look stalled.
            ProgressView(value: videos.fractionalProgress)
                .frame(width: 130)
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

// MARK: - Mode rail

/// The narrow left rail. Replaces a segmented control in the title bar: it
/// reads as part of the app rather than as a setting, and it leaves the top of
/// the window quiet.
private struct ModeRail: View {
    @Binding var mode: Mode

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Mode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: candidate.railSymbol)
                            .font(.system(size: 16, weight: .medium))
                        Text(candidate.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        mode == candidate ? Palette.accent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: Metrics.smallRadius)
                    )
                    .foregroundStyle(
                        mode == candidate ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary)
                    )
                }
                .buttonStyle(.plain)
                .help(candidate.title)
            }
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: Metrics.railWidth)
        .background(Palette.surface)
    }
}

// MARK: - Buttons

private struct AccentButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Palette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: Metrics.smallRadius)
            )
            .foregroundStyle(.white)
    }
}

// MARK: - Image inspector

private struct ImageInspector: View {
    @ObservedObject var model: ConverterViewModel

    var body: some View {
        InspectorGroup(title: "Format") {
            Picker("", selection: Binding(
                get: { model.target },
                set: { model.selectFormat($0) }
            )) {
                ForEach(model.availableFormats) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.target.supportsQuality {
                Field(
                    label: "Qualität",
                    hint: model.target == .avif
                        ? "AVIF geht bis 99 — bei 100 schreibt macOS keine Datei."
                        : "Höher ist besser."
                ) {
                    SliderRow(value: $model.quality, range: 1...model.maxQuality)
                }
            } else {
                Field(label: "Qualität", hint: "PNG ist verlustfrei.") {
                    Text("—").foregroundStyle(.tertiary)
                }
            }

            MaxEdgeField(text: $model.maxEdgeText, isActive: model.maxEdge != nil)
        }

        Divider()

        InspectorGroup(title: "Ausgabe") {
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
            Notice(text: "cwebp fehlt — WebP nicht verfügbar.", detail: nil)
        }
    }
}

// MARK: - Video inspector

private struct VideoInspector: View {
    @ObservedObject var model: VideoViewModel

    var body: some View {
        if !model.isAvailable {
            Notice(
                text: "ffmpeg fehlt",
                detail: "Einmalig ./fetch-ffmpeg.sh ausführen und neu bauen."
            )
        }

        InspectorGroup(title: "Codec") {
            if !model.availableCodecs.isEmpty {
                Picker("", selection: $model.codec) {
                    ForEach(model.availableCodecs) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(model.codec.hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Field(
                label: "Qualität",
                // CRF runs the other way round to the image slider, and saying
                // so beats letting people find out the hard way.
                hint: "CRF — kleiner ist besser, bis \(model.codec.crfRange.upperBound)."
            ) {
                SliderRow(
                    value: $model.crf,
                    range: Double(model.codec.crfRange.lowerBound)...Double(model.codec.crfRange.upperBound)
                )
            }

            MaxEdgeField(text: $model.maxEdgeText, isActive: model.maxEdge != nil)
            Toggle("Tonspur behalten", isOn: $model.keepAudio)
                .font(.callout)
        }

        Divider()

        InspectorGroup(title: "Ausgabe") {
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
}

// MARK: - Inspector building blocks

private struct SliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: 1)
            Text("\(Int(value))")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MaxEdgeField: View {
    @Binding var text: String
    let isActive: Bool

    var body: some View {
        Field(label: "Max. Kante", hint: isActive ? "Nur verkleinernd." : nil) {
            HStack(spacing: 6) {
                TextField("unbegrenzt", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("px").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RenameField: View {
    @Binding var pattern: String
    let preview: String?

    var body: some View {
        Field(label: "Umbenennen", hint: preview ?? "{name} · {n} · {nn} · {nnn}") {
            TextField("Originalname", text: $pattern)
                .textFieldStyle(.roundedBorder)
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
        Field(label: "Ziel") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: isCustom ? "folder.fill" : "arrow.turn.down.right")
                        .imageScale(.small)
                        .foregroundStyle(isCustom ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.tertiary))
                    Text(label)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(fullPath ?? "Jede Datei landet neben ihrem Original.")
                }
                HStack(spacing: 10) {
                    Button("Ordner wählen…", action: onChoose)
                        .controlSize(.small)
                    if isCustom {
                        Button("Zurücksetzen", action: onReset)
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
    }
}

private struct Notice: View {
    let text: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
                .foregroundStyle(Palette.warm)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.smallRadius))
    }
}

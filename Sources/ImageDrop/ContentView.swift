import SwiftUI
import ConversionKit

struct ContentView: View {
    @StateObject private var model = ConverterViewModel()
    @ObservedObject private var inbound = InboundFiles.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    DropZone(hasQueue: !model.queue.isEmpty)

                    if !model.queue.isEmpty {
                        queuePanel
                    }

                    settingsPanel

                    if !model.results.isEmpty {
                        resultsPanel
                    }
                }
                .padding(20)
            }

            Divider()
            actionBar
        }
        .onChange(of: inbound.urls) { _, urls in
            guard !urls.isEmpty else { return }
            model.enqueue(inbound.take())
        }
    }

    // MARK: - Queue

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.queue.count) \(model.queue.count == 1 ? "Bild" : "Bilder") in der Warteschlange")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Leeren") { model.clearQueue() }
                    .buttonStyle(.link)
                    .disabled(model.isRunning)
            }

            if model.rejectedCount > 0 {
                Text("\(model.rejectedCount) Objekt(e) übersprungen — keine Bilddateien.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.queue, id: \.path) { url in
                        HStack(spacing: 6) {
                            Text(url.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.remove(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isRunning)
                            .help("Aus der Warteschlange nehmen")
                        }
                    }
                }
            }
            .frame(maxHeight: 130)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Zielformat", selection: Binding(
                get: { model.target },
                set: { model.selectFormat($0) }
            )) {
                ForEach(model.availableFormats) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("Qualität")
                Slider(value: $model.quality, in: 1...100, step: 1)
                    .disabled(!model.target.supportsQuality)
                Text("\(Int(model.quality))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
                    .foregroundStyle(model.target.supportsQuality ? .primary : .tertiary)
            }

            if !model.target.supportsQuality {
                Text("PNG ist verlustfrei — die Qualität hat keinen Effekt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Max. Kante")
                TextField("unbegrenzt", text: $model.maxEdgeText)
                    .frame(width: 90)
                Text("px")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.maxEdge != nil {
                    Text("nur verkleinernd")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            renameSection
            destinationSection

            if !model.supportsWebP {
                Text("WebP nicht verfügbar: cwebp fehlt im App-Bundle.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Umbenennen")
                TextField("Originalname behalten", text: $model.renamePattern)
            }

            if let preview = model.renamePreview {
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Platzhalter: {name} = Originalname, {n} / {nn} / {nnn} = Nummer mit Nullen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationSection: some View {
        HStack {
            Text("Ziel")
            Image(systemName: model.destinationDirectory == nil ? "arrow.turn.down.right" : "folder")
                .foregroundStyle(.secondary)
            Text(model.destinationLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.destinationDirectory?.path ?? "Jede Datei landet neben ihrem Original.")
            Spacer()
            if model.destinationDirectory != nil {
                Button("Zurücksetzen") { model.useSourceDirectory() }
                    .buttonStyle(.link)
            }
            Button("Ordner wählen…") { model.chooseDestination() }
        }
    }

    // MARK: - Results

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summaryLine)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Liste leeren") { model.clearResults() }
                    .buttonStyle(.link)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.results.enumerated()), id: \.offset) { _, outcome in
                    ResultRow(outcome: outcome)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryLine: String {
        var parts = ["\(model.successCount) konvertiert"]
        if model.failureCount > 0 {
            parts.append("\(model.failureCount) fehlgeschlagen")
        }
        let saved = model.totalSaved
        if saved > 0 {
            parts.append("\(ByteCountFormatter.string(fromByteCount: Int64(saved), countStyle: .file)) gespart")
        } else if saved < 0 {
            parts.append("\(ByteCountFormatter.string(fromByteCount: Int64(-saved), countStyle: .file)) größer")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            if model.isRunning {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.total)))
                    .frame(maxWidth: 160)
                Text("\(model.completed)/\(model.total)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(convertLabel) { model.convert() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canConvert)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var convertLabel: String {
        guard !model.queue.isEmpty else { return "Konvertieren" }
        return "\(model.queue.count) \(model.queue.count == 1 ? "Bild" : "Bilder") konvertieren"
    }
}

/// Split out so the drop modifier lives on a concrete view and the closure
/// stays readable.
private struct DropZone: View {
    let hasQueue: Bool
    @ObservedObject private var inbound = InboundFiles.shared
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 2, dash: [7, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .frame(height: hasQueue ? 84 : 130)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: hasQueue ? 20 : 28))
                        .foregroundStyle(.secondary)
                    Text(hasQueue ? "Weitere Bilder hierher ziehen" : "Bilder hierher ziehen")
                        .font(hasQueue ? .callout : .headline)
                    if !hasQueue {
                        Text("oder auf das Dock-Icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                inbound.urls.append(contentsOf: urls)
                return true
            } isTargeted: { targeted = $0 }
    }
}

private struct ResultRow: View {
    let outcome: ConversionOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch outcome {
            case .success(_, let output, _, _):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(output.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let saved = outcome.savedFraction {
                    Text(saved >= 0
                         ? "−\(Int((saved * 100).rounded()))%"
                         : "+\(Int((-saved * 100).rounded()))%")
                        .monospacedDigit()
                        .font(.callout)
                        .foregroundStyle(saved >= 0 ? .green : .orange)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Im Finder zeigen")

            case .failure(let input, let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(reason.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

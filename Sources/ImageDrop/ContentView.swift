import SwiftUI
import ConversionKit

struct ContentView: View {
    @StateObject private var model = ConverterViewModel()
    @ObservedObject private var inbound = InboundFiles.shared

    var body: some View {
        VStack(spacing: 16) {
            DropZone(isRunning: model.isRunning)
            settingsPanel

            if model.isRunning {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.total))) {
                    Text("Konvertiere \(model.completed) von \(model.total)")
                        .font(.callout)
                }
            }

            if !model.results.isEmpty {
                resultsPanel
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .onChange(of: inbound.urls) { _, urls in
            guard !urls.isEmpty else { return }
            model.accept(inbound.take())
        }
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

            HStack {
                Text("Qualität")
                Slider(value: $model.quality, in: 1...100, step: 1)
                    .disabled(!model.target.supportsQuality)
                Text("\(Int(model.quality))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
                    .foregroundStyle(model.target.supportsQuality ? .primary : .tertiary)
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

            if !model.target.supportsQuality {
                Text("PNG ist verlustfrei — die Qualität hat keinen Effekt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.supportsWebP {
                Text("WebP nicht verfügbar: cwebp fehlt im App-Bundle.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
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

            if model.rejectedCount > 0 {
                Text("\(model.rejectedCount) Objekt(e) übersprungen — keine Bilddateien.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.results.enumerated()), id: \.offset) { _, outcome in
                        ResultRow(outcome: outcome)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
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
}

/// Split out so the drop modifier lives on a concrete view and the closure
/// stays readable.
private struct DropZone: View {
    let isRunning: Bool
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
            .frame(height: 130)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(isRunning ? "Läuft…" : "Bilder hierher ziehen")
                        .font(.headline)
                    Text("oder auf das Dock-Icon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .padding(.vertical, 2)
    }
}

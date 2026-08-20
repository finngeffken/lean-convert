import SwiftUI
import ConversionKit

/// Drop target. Shared by both modes; what happens with the files is the
/// caller's business.
struct DropZone: View {
    let hasQueue: Bool
    let isRunning: Bool
    let noun: String
    let onDrop: ([URL]) -> Void

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
                    Image(systemName: noun == "Videos" ? "film" : "photo.on.rectangle.angled")
                        .font(.system(size: hasQueue ? 20 : 28))
                        .foregroundStyle(.secondary)
                    Text(hasQueue ? "Weitere \(noun) hierher ziehen" : "\(noun) hierher ziehen")
                        .font(hasQueue ? .callout : .headline)
                    if !hasQueue {
                        Text("oder auf das Dock-Icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return true
            } isTargeted: { targeted = $0 }
    }
}

struct QueuePanel: View {
    let queue: [URL]
    let rejectedCount: Int
    let isRunning: Bool
    let noun: String
    let onRemove: (URL) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(queue.count) \(queue.count == 1 ? noun.dropLast() : Substring(noun)) in der Warteschlange")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Leeren", action: onClear)
                    .buttonStyle(.link)
                    .disabled(isRunning)
            }

            if rejectedCount > 0 {
                Text("\(rejectedCount) Objekt(e) übersprungen — passen nicht in diesen Modus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(queue, id: \.path) { url in
                        HStack(spacing: 6) {
                            Text(url.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button { onRemove(url) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isRunning)
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
}

struct DestinationRow: View {
    let label: String
    let isCustom: Bool
    let fullPath: String?
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack {
            Text("Ziel")
            Image(systemName: isCustom ? "folder" : "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fullPath ?? "Jede Datei landet neben ihrem Original.")
            Spacer()
            if isCustom {
                Button("Zurücksetzen", action: onReset)
                    .buttonStyle(.link)
            }
            Button("Ordner wählen…", action: onChoose)
        }
    }
}

struct RenameRow: View {
    @Binding var pattern: String
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Umbenennen")
                TextField("Originalname behalten", text: $pattern)
            }

            if let preview {
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
}

struct ResultsPanel: View {
    let results: [ConversionOutcome]
    let summary: String
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Liste leeren", action: onClear)
                    .buttonStyle(.link)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, outcome in
                    ResultRow(outcome: outcome)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ResultRow: View {
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
                // A cancelled file is not a defect; it should not shout at you
                // in warning orange.
                let cancelled = reason == .cancelled
                Image(systemName: cancelled ? "slash.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(cancelled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
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

/// Formats a byte delta for the summary line.
func savedText(_ saved: Int) -> String? {
    guard saved != 0 else { return nil }
    let formatted = ByteCountFormatter.string(
        fromByteCount: Int64(abs(saved)),
        countStyle: .file
    )
    return saved > 0 ? "\(formatted) gespart" : "\(formatted) größer"
}

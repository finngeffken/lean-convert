import SwiftUI
import ConversionKit

// MARK: - Drop zone

/// Drop target. Shared by both modes; what happens with the files is the
/// caller's business.
///
/// Two sizes: the hero version fills the empty work area, the compact version
/// steps aside once there is a queue to look at.
struct DropZone: View {
    let compact: Bool
    let noun: String
    let symbol: String
    let onDrop: ([URL]) -> Void

    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay { label }
            .frame(height: compact ? 56 : nil)
            .frame(maxHeight: compact ? 56 : .infinity)
            .animation(.easeOut(duration: 0.12), value: targeted)
            .dropDestination(for: URL.self) { urls, _ in
                onDrop(urls)
                return true
            } isTargeted: { targeted = $0 }
    }

    @ViewBuilder
    private var label: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .imageScale(.small)
                Text("Weitere hierher ziehen")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("\(noun) hierher ziehen")
                    .font(.title3.weight(.medium))
                Text("oder auf das Dock-Icon")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Queue

struct QueueList: View {
    let queue: [URL]
    let rejectedCount: Int
    let isRunning: Bool
    let onRemove: (URL) -> Void
    let onClear: () -> Void

    @ObservedObject var thumbnails: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(queue, id: \.path) { url in
                        FileRow(
                            url: url,
                            thumbnails: thumbnails,
                            trailing: {
                                Button {
                                    onRemove(url)
                                } label: {
                                    Image(systemName: "xmark")
                                        .imageScale(.small)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .disabled(isRunning)
                                .help("Aus der Warteschlange nehmen")
                            }
                        )
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("\(queue.count) in der Warteschlange")
                .font(.callout.weight(.medium))
            if rejectedCount > 0 {
                Text("· \(rejectedCount) übersprungen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Passt nicht in diesen Modus.")
            }
            Spacer()
            Button("Leeren", action: onClear)
                .buttonStyle(.link)
                .disabled(isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - Results

struct ResultsList: View {
    let results: [ConversionOutcome]
    let summary: String
    let onClear: () -> Void

    @ObservedObject var thumbnails: ThumbnailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(summary)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Leeren", action: onClear)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, outcome in
                        ResultRow(outcome: outcome, thumbnails: thumbnails)
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }
}

// MARK: - Rows

/// One file with its preview. The shared shape behind queue and result rows, so
/// the two lists line up instead of each inventing its own metrics.
private struct FileRow<Trailing: View>: View {
    let url: URL
    @ObservedObject var thumbnails: ThumbnailStore
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: url, thumbnails: thumbnails)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

struct Thumbnail: View {
    let url: URL
    @ObservedObject var thumbnails: ThumbnailStore

    var body: some View {
        ZStack {
            if let image = thumbnails.thumbnail(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task { thumbnails.load(url) }
    }
}

struct ResultRow: View {
    let outcome: ConversionOutcome
    @ObservedObject var thumbnails: ThumbnailStore

    var body: some View {
        switch outcome {
        case .success(_, let output, let before, let after):
            FileRow(url: output, thumbnails: thumbnails) {
                HStack(spacing: 10) {
                    Text("\(byteText(before)) → \(byteText(after))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    savedBadge
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Im Finder zeigen")
                }
            }

        case .failure(let input, let reason):
            // A cancelled file is not a defect and should not shout in orange.
            let cancelled = reason == .cancelled
            HStack(spacing: 10) {
                Image(systemName: cancelled ? "minus.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(cancelled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(input.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(reason.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private var savedBadge: some View {
        if let saved = outcome.savedFraction {
            let grew = saved < 0
            Text(grew
                 ? "+\(Int((-saved * 100).rounded()))%"
                 : "−\(Int((saved * 100).rounded()))%")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (grew ? Color.orange : Color.green).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(grew ? Color.orange : Color.green)
        }
    }
}

// MARK: - Formatting

func byteText(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

/// Formats a byte delta for the summary line.
func savedText(_ saved: Int) -> String? {
    guard saved != 0 else { return nil }
    let formatted = byteText(abs(saved))
    return saved > 0 ? "\(formatted) gespart" : "\(formatted) größer"
}

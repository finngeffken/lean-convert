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
        RoundedRectangle(cornerRadius: Metrics.radius)
            .strokeBorder(
                targeted ? Palette.accent : Palette.hairline,
                style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [5, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(targeted ? Palette.accent.opacity(0.07) : Palette.surface.opacity(0.5))
            )
            .overlay { label }
            .frame(maxHeight: compact ? 54 : .infinity)
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
            .foregroundStyle(targeted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
        } else {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(targeted ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.tertiary))
                VStack(spacing: 3) {
                    Text("\(noun) hierher ziehen")
                        .font(.system(size: 15, weight: .medium))
                    Text("oder auf das Dock-Icon")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - List container

/// Card with a compact header bar and a scrolling body. Queue and results share
/// it so the two lists cannot drift apart visually.
struct ListCard<Body_: View>: View {
    let title: String
    var note: String?
    var noteHelp: String?
    let actionTitle: String
    let actionEnabled: Bool
    let action: () -> Void
    @ViewBuilder let rows: () -> Body_

    var body: some View {
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    if let note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .help(noteHelp ?? "")
                    }
                    Spacer()
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(actionEnabled ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.tertiary))
                        .disabled(!actionEnabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) { rows() }
                }
            }
        }
    }
}

// MARK: - Rows

/// One file with its preview. The shared shape behind queue and result rows, so
/// the two lists line up instead of each inventing its own metrics.
struct FileRow<Trailing: View>: View {
    let url: URL
    let subtitle: String?
    @ObservedObject var thumbnails: ThumbnailStore
    @ViewBuilder let trailing: () -> Trailing

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: url, thumbnails: thumbnails)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hovering ? Palette.accent.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
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
                    .fill(.quaternary.opacity(0.6))
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.smallRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.smallRadius)
                .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5)
        }
        .task { thumbnails.load(url) }
    }
}

struct ResultRow: View {
    let outcome: ConversionOutcome
    @ObservedObject var thumbnails: ThumbnailStore

    var body: some View {
        switch outcome {
        case .success(_, let output, let before, let after):
            FileRow(
                url: output,
                subtitle: "\(byteText(before)) → \(byteText(after))",
                thumbnails: thumbnails
            ) {
                HStack(spacing: 8) {
                    savedBadge
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Im Finder zeigen")
                }
            }

        case .failure(let input, let reason):
            // Cancelling is not a defect, so it stays grey while real failures
            // get the red.
            let cancelled = reason == .cancelled
            HStack(spacing: 10) {
                Image(systemName: cancelled ? "minus.circle" : "exclamationmark.circle.fill")
                    .foregroundStyle(cancelled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.failure))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(input.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(reason.message)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var savedBadge: some View {
        if let saved = outcome.savedFraction {
            let grew = saved < 0
            Badge(
                text: grew
                    ? "+\(Int((-saved * 100).rounded()))%"
                    : "−\(Int((saved * 100).rounded()))%",
                color: grew ? Palette.failure : Palette.success
            )
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

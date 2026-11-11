import SwiftUI
import ConversionKit

// MARK: - Empty state

/// The first thing anyone sees. Calm on purpose: the app icon, one sentence,
/// and what goes in. The whole window is the drop target, so there is no box
/// to aim at.
struct EmptyState: View {
    let mode: Mode
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: Color(hex: 0xFF6A2A).opacity(0.25), radius: 18, y: 8)

            VStack(spacing: 6) {
                Text("\(mode.noun) hier ablegen")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                HStack(spacing: 4) {
                    Text("oder")
                    Button("Dateien auswählen", action: onChoose)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                    Text("· ⌘O")
                        .foregroundStyle(.tertiary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(mode.formats, id: \.self) { FormatChip(text: $0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tiles

/// One file as an image-first card. For an image tool the content is the most
/// attractive thing on screen, so it gets the space instead of a list row.
struct MediaTile: View {
    let url: URL
    let title: String
    var detail: String?
    var badge: (text: String, color: Color)?
    var failed = false
    var onRemove: (() -> Void)?
    var onReveal: (() -> Void)?
    @ObservedObject var thumbnails: ThumbnailStore

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { preview }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
                }
                .overlay(alignment: .bottomLeading) { badgeView }
                .overlay(alignment: .topTrailing) { removeButton }
                .shadow(color: .black.opacity(hovering ? 0.16 : 0.07), radius: hovering ? 14 : 6, y: hovering ? 7 : 3)
                .scaleEffect(hovering ? 1.015 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(failed ? AnyShapeStyle(Palette.failure) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .onTapGesture(count: 2) { onReveal?() }
        .help(onReveal == nil ? url.path : "Doppelklick: im Finder zeigen")
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.4))
            if let image = thumbnails.thumbnail(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(failed ? 0 : 1)
                    .opacity(failed ? 0.45 : 1)
                    .transition(.opacity)
            }
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.failure)
            }
        }
        .animation(.easeOut(duration: 0.2), value: thumbnails.thumbnail(for: url) != nil)
        .task { thumbnails.load(url) }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge.text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badge.color.opacity(0.92), in: Capsule())
                .padding(8)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if let onRemove, hovering {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .padding(7)
            .transition(.scale.combined(with: .opacity))
            .help("Aus der Warteschlange nehmen")
        }
    }
}

struct TileGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)],
            alignment: .leading,
            spacing: 22
        ) {
            content()
        }
    }
}

// MARK: - Result hero

/// The moment the app exists for. One big number in the brand gradient, then
/// the two sensible next steps.
struct ResultHero: View {
    let before: Int
    let after: Int
    let converted: Int
    let failed: Int
    let onAgain: () -> Void
    let onDone: () -> Void

    private var fraction: Double {
        before > 0 ? Double(before - after) / Double(before) : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(fraction >= 0 ? AnyShapeStyle(Palette.brandGradient) : AnyShapeStyle(Palette.failure))
                    .contentTransition(.numericText())
                Text(subline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Andere Einstellungen", action: onAgain)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("Zurück zur Warteschlange, um dieselben Dateien anders zu konvertieren.")
            Button("Fertig", action: onDone)
                .buttonStyle(GradientButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.brandGradient.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        }
    }

    private var headline: String {
        let percent = Int((abs(fraction) * 100).rounded())
        return fraction >= 0 ? "−\(percent) %" : "+\(percent) %"
    }

    private var subline: String {
        var parts: [String] = []
        let delta = before - after
        parts.append(delta >= 0 ? "\(byteText(delta)) gespart" : "\(byteText(-delta)) größer geworden")
        parts.append("\(converted) \(converted == 1 ? "Datei" : "Dateien")")
        if failed > 0 { parts.append("\(failed) fehlgeschlagen") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Formatting

func byteText(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

func savedText(_ saved: Int) -> String? {
    guard saved != 0 else { return nil }
    let formatted = byteText(abs(saved))
    return saved > 0 ? "\(formatted) gespart" : "\(formatted) größer"
}

func fileSize(_ url: URL) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
}

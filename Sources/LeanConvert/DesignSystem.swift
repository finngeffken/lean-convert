import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The app's colours, taken from the icon's gradient.
///
/// Only the brand tones are fixed values. Everything structural — surfaces,
/// text, separators — stays semantic so light and dark mode both stay correct
/// without a second palette.
///
/// Note on orange: it is the brand colour here, which means it can no longer
/// double as the warning colour. Failures are red, growth in file size is red,
/// success is green. Brand and status are deliberately separate vocabularies.
enum Palette {
    /// The icon's gradient runs #FF0808 → #FFCA4D. This is its midpoint, so
    /// the accent belongs to the mark rather than merely resembling it.
    static let accent = Color(hex: 0xFF692A)
    /// The gradient's golden end, for notices.
    static let warm = Color(hex: 0xFFCA4D)

    static let success = Color(hex: 0x1BA672)
    /// Deeper and less orange than the brand tone, so a failure cannot be
    /// mistaken for an accent.
    static let failure = Color(hex: 0xD92D20)

    /// Page background behind the cards.
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    /// Card and panel surface.
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
}

enum Metrics {
    static let radius: CGFloat = 10
    static let smallRadius: CGFloat = 6
    static let gutter: CGFloat = 14
    static let railWidth: CGFloat = 60
    static let inspectorWidth: CGFloat = 296
}

// MARK: - Building blocks

/// A white surface with a hairline border and no drop shadow — the flat card
/// look, rather than the heavy grouped-form boxes macOS gives by default.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
    }
}

/// Small tinted pill. Used for formats and for the size delta.
struct Badge: View {
    let text: String
    var color: Color = Palette.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The quiet grey label above a group of controls.
struct GroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

/// One labelled control in the inspector. Replaces `LabeledContent` inside a
/// grouped `Form`: the label sits above its control, which leaves the full
/// panel width for the control itself and keeps every row aligned.
struct Field<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.callout)
            content()
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A group of fields, separated from the next by a hairline rather than by a
/// box within a box.
struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Brand gradient and glass

extension Palette {
    /// The icon's gradient, used sparingly: the primary action and the one
    /// number the app exists to produce.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF3D1F), Color(hex: 0xFF7A2C), Color(hex: 0xFFB443)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Calm, near-white working surface. The grey under-page colour read as an
    /// empty placeholder rather than as a place to work.
    static let workCanvas = Color(nsColor: .textBackgroundColor)
}

extension View {
    /// Liquid Glass on macOS 26, a material capsule before that.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self.background(.regularMaterial, in: Circle())
        }
    }
}

/// The one loud control in the window.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Palette.brandGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: Color(hex: 0xFF6A2A).opacity(isEnabled ? 0.35 : 0), radius: 8, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Small format chip for the empty state.
struct FormatChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

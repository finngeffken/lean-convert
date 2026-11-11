import SwiftUI
import ConversionKit

// MARK: - Image inspector

struct ImageInspector: View {
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
                        ? (model.writesCompatibleAVIF
                            ? "Webflow-tauglich, ohne EXIF. Transparente Bilder laufen über macOS und behalten es."
                            : "Ohne ffmpeg: ab 1024 px nicht Webflow-tauglich.")
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

struct VideoInspector: View {
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

struct SliderRow: View {
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

struct MaxEdgeField: View {
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

struct RenameField: View {
    @Binding var pattern: String
    let preview: String?

    var body: some View {
        Field(label: "Umbenennen", hint: preview ?? "{name} · {n} · {nn} · {nnn}") {
            TextField("Originalname", text: $pattern)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct DestinationField: View {
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

struct Notice: View {
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

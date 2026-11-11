// Renders Lean Convert icon variants at 1024 px on the macOS icon grid:
// an 824 px continuous squircle centred on a transparent 1024 canvas.
//   swift IconDesign.swift <outdir>
import SwiftUI
import AppKit

let red = Color(red: 1.0, green: 0.24, blue: 0.12)
let orange = Color(red: 1.0, green: 0.48, blue: 0.17)
let gold = Color(red: 1.0, green: 0.76, blue: 0.29)

struct Squircle<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [red, orange, gold], startPoint: .topLeading, endPoint: .bottomTrailing))
            content()
            // Glass sheen across the top, the macOS 26 highlight.
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center))
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

struct Glass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color(red: 0.55, green: 0.1, blue: 0).opacity(0.35), radius: 22, y: 14)
    }
}

/// A: "Squeeze" – two chevrons pressing a diamond. The original mark's
/// zigzag, reduced to the act of compressing.
struct VariantA: View {
    var body: some View {
        Squircle {
            ZStack {
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .fill(LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(45))
                    .modifier(Glass())
                chevron.offset(x: -250)
                chevron.scaleEffect(x: -1).offset(x: 250)
            }
        }
    }
    var chevron: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 90, y: 110))
            p.addLine(to: CGPoint(x: 0, y: 220))
        }
        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 52, lineCap: .round, lineJoin: .round))
        .frame(width: 90, height: 220)
        .modifier(Glass())
    }
}

/// B: "Shrink" – a large ghost frame and a solid smaller one in front: the
/// same picture, lighter.
struct VariantB: View {
    var body: some View {
        Squircle {
            ZStack {
                RoundedRectangle(cornerRadius: 70, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 22, dash: [44, 30]))
                    .frame(width: 560, height: 460)
                    .offset(x: -30, y: -28)
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .fill(.white)
                    .frame(width: 360, height: 296)
                    .overlay {
                        ZStack {
                            Circle().fill(gold).frame(width: 66).offset(x: 80, y: -60)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: 296))
                                p.addLine(to: CGPoint(x: 130, y: 140))
                                p.addLine(to: CGPoint(x: 220, y: 230))
                                p.addLine(to: CGPoint(x: 280, y: 175))
                                p.addLine(to: CGPoint(x: 360, y: 296))
                                p.closeSubpath()
                            }
                            .fill(LinearGradient(colors: [red, orange], startPoint: .top, endPoint: .bottom))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
                    }
                    .offset(x: 70, y: 70)
                    .modifier(Glass())
            }
        }
    }
}

/// C: "Facets" – three nested diamonds shrinking inward, the original mark
/// given depth: outline, glass, solid core.
struct VariantC: View {
    var body: some View {
        Squircle {
            ZStack {
                diamond(400).stroke(.white.opacity(0.5), lineWidth: 24)
                diamond(280).fill(.white.opacity(0.3))
                    .overlay(diamond(280).stroke(.white.opacity(0.75), lineWidth: 4))
                diamond(150).fill(LinearGradient(colors: [.white, .white.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .modifier(Glass())
            }
        }
    }
    func diamond(_ side: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
            .size(width: side, height: side)
            .offset(x: -side / 2, y: -side / 2)
            .rotation(.degrees(45), anchor: .topLeading)
            .offset(x: 412, y: 412)
    }
}

@MainActor
func render<V: View>(_ view: V, to url: URL) {
    let renderer = ImageRenderer(content: view.frame(width: 1024, height: 1024))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("fail \(url.lastPathComponent)"); return }
    try! png.write(to: url)
    print("ok \(url.lastPathComponent)")
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    render(VariantA(), to: out.appendingPathComponent("icon-a.png"))
    render(VariantB(), to: out.appendingPathComponent("icon-b.png"))
    render(VariantC(), to: out.appendingPathComponent("icon-c.png"))
}

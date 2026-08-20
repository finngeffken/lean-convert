import SwiftUI
import ConversionKit

@main
struct ImageDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("ImageDrop") {
            ContentView()
                .frame(minWidth: 780, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Files dropped on the Dock icon arrive through the app delegate, not through
/// the window, so they need a place to land that the view can observe.
@MainActor
final class InboundFiles: ObservableObject {
    static let shared = InboundFiles()
    @Published var urls: [URL] = []

    func take() -> [URL] {
        let pending = urls
        urls = []
        return pending
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            InboundFiles.shared.urls.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

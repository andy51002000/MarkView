import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Called by Finder / LaunchServices when the user double-clicks files.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            DocumentStore.shared.load(url: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        DocumentStore.shared.load(url: URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MarkViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore.shared
    @StateObject private var zoom = ZoomModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(zoom)
                .frame(minWidth: 640, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    store.openWithPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            // Browser-style zoom: ⌘+ / ⌘− / ⌘0. "=" is the unshifted key
            // of "+" on US layouts, so ⌘= works as ⌘+ like in browsers.
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    zoom.zoomIn()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom In (=)") {
                    zoom.zoomIn()
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out") {
                    zoom.zoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size") {
                    zoom.reset()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Divider()
            }
        }
    }
}

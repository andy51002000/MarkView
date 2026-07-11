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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 640, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    store.openWithPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

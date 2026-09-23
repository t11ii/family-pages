import AppKit
import SwiftUI

@main
struct FamilyPublisherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Family Publisher", id: "main") {
            ContentView().environment(Publisher.shared)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView().environment(Publisher.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Finder "Open With → Family Publisher" and drops onto the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            if !Publisher.shared.isBusy { Publisher.shared.file = url }
        }
    }
}

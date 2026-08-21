import SwiftUI

// Quit when the main window closes, instead of lingering in the Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Offer to move into /Applications when launched from Downloads.
        Relocator.offerIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }
}

@main
struct MotionGraphicsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SystemMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentional menu-bar-only app: no Dock icon, no launch window.
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("SilBar menu bar monitor")

        let monitor = SystemMonitor()
        self.monitor = monitor
        statusBarController = StatusBarController(monitor: monitor)
    }
}

@main
struct SilBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

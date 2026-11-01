import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The bundled app sets LSUIElement; this also covers `swift run`, where there is no
        // Info.plist, so the app never shows a Dock icon either way.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }

    /// Launching the app again while it is running opens Settings, the only window it has.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.openSettings()
        return false
    }
}

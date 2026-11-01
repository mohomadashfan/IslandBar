import IslandCore
import SwiftUI

@main
struct IslandBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("IslandBar", systemImage: "capsule.inset.filled") {
            MenuBarContent(environment: appDelegate.environment)
        }
    }
}

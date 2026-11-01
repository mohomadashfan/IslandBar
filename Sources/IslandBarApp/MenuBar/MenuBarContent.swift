import AppKit
import FeatureCaffeinate
import IslandCore
import SwiftUI

struct MenuBarContent: View {
    let environment: AppEnvironment

    private var settings: SettingsStore { environment.settings }

    var body: some View {
        if settings.lastError != nil {
            Text("Settings could not be read or saved")
            Divider()
        }

        Toggle("Show Island", isOn: settings.binding(\.general.isIslandEnabled))

        Button("Toggle Island") { environment.islands.toggleOnActiveDisplay() }
            .disabled(!settings.settings.general.isIslandEnabled)

        if environment.registry.isActive(.focus) {
            Divider()
            Button(focusTitle) { environment.focus.startOrPause() }
        }

        if environment.registry.isActive(.caffeinate) {
            Divider()
            Menu(environment.caffeinate.state.isActive ? "Keep Mac Awake (On)" : "Keep Mac Awake") {
                ForEach(CaffeinateDuration.allCases) { duration in
                    Button(duration.displayName) { environment.caffeinate.start(duration) }
                }
                if environment.caffeinate.state.isActive {
                    Divider()
                    Button("Turn Off") { environment.caffeinate.stop() }
                }
            }
        }

        Divider()

        Button("Settings…") { environment.openSettings() }
            .keyboardShortcut(",")

        Button("About IslandBar") { environment.openSettings(.about) }

        Divider()

        Button("Quit IslandBar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var focusTitle: String {
        let timer = environment.focus.timer
        if timer.isRunning { return "Pause \(timer.phase.displayName)" }
        if timer.isPaused { return "Resume \(timer.phase.displayName)" }
        return "Start \(timer.phase.displayName)"
    }
}

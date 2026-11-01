import IslandCore
import SwiftUI

struct GeneralSettingsPane: View {
    let environment: AppEnvironment

    @State private var isConfirmingRestore = false

    private var loginItem: LoginItemController { environment.loginItem }
    private var settings: SettingsStore { environment.settings }

    var body: some View {
        Form {
            Section {
                Toggle("Show the island", isOn: settings.binding(\.general.isIslandEnabled))
            }

            Section("Interaction") {
                Toggle("Expand when the pointer rests on the island", isOn: settings.binding(\.general.expandOnHover))
                ValueSlider(title: "Hover delay", value: settings.binding(\.general.hoverDelay), range: 0...1, step: 0.05, format: SettingsFormat.seconds)
                    .disabled(!settings.settings.general.expandOnHover)
                ValueSlider(title: "Collapse delay", value: settings.binding(\.general.collapseDelay), range: 0...2, step: 0.05, format: SettingsFormat.seconds)
                Toggle("Collapse when clicking elsewhere", isOn: settings.binding(\.general.collapseOnClickOutside))
                Toggle("Haptic feedback on expand", isOn: settings.binding(\.general.hapticFeedback))
                SettingsNote("Click the island to keep it open. Press Escape to close it.")
            }

            Section("Keyboard") {
                Picker("Toggle island", selection: settings.binding(\.general.toggleShortcut)) {
                    ForEach(ToggleShortcut.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if let error = environment.hotKeyError {
                    Text(error).foregroundStyle(.orange)
                }
            }

            Section("Full Screen and Screen Sharing") {
                Toggle("Show the island over full-screen apps", isOn: settings.binding(\.general.showInFullScreenApps))
                Toggle("Hide the island from screenshots and screen sharing", isOn: settings.binding(\.general.hideFromScreenCapture))
                SettingsNote("Keeps your notes, notifications and track titles out of recordings and video calls. Some capture tools may not honour this request.")
            }

            Section("Startup") {
                Toggle(
                    "Launch IslandBar at login",
                    isOn: Binding(
                        get: { loginItem.isEnabled || loginItem.requiresApproval },
                        set: { loginItem.setEnabled($0) }
                    )
                )
                if loginItem.requiresApproval {
                    HStack {
                        SettingsNote("Allow IslandBar in System Settings › General › Login Items to finish enabling.")
                        Spacer()
                        Button("Open…") { loginItem.openSystemSettings() }
                    }
                }
                if let message = loginItem.lastErrorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }

            if let error = settings.lastError {
                Section("Storage") {
                    Text(Self.describe(error)).foregroundStyle(.red)
                    Text(AppPaths.settingsFile().path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults…") { isConfirmingRestore = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .confirmationDialog("Restore all settings to their defaults?", isPresented: $isConfirmingRestore) {
            Button("Restore Defaults", role: .destructive) { settings.restoreDefaults() }
        } message: {
            Text("Every section returns to its default. Shelf items, focus notes and login item status are not changed.")
        }
    }

    private static func describe(_ error: PersistenceError) -> String {
        switch error {
        case .readFailed(let detail): "Settings could not be read: \(detail)"
        case .decodeFailed: "The settings file was unreadable and has been set aside. Defaults are in use."
        case .writeFailed(let detail): "Settings could not be saved: \(detail)"
        }
    }
}

import IslandCore
import IslandWindows
import SwiftUI

struct DisplaySettingsPane: View {
    let settings: SettingsStore
    let monitor: DisplayMonitor

    private var displays: DisplaySettings { settings.settings.displays }

    var body: some View {
        Form {
            Section("Defaults") {
                Toggle("Show on the built-in display", isOn: settings.binding(\.displays.showOnBuiltInDisplay))
                Toggle("Show on external displays", isOn: settings.binding(\.displays.showOnExternalDisplays))
            }

            Section("Connected Displays") {
                if monitor.displays.isEmpty {
                    Text("No displays detected.").foregroundStyle(.secondary)
                }
                ForEach(monitor.displays) { display in
                    Toggle(isOn: enabledBinding(for: display)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name)
                            Text(description(of: display))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !displays.overrides.isEmpty {
                    Button("Use Defaults for All Displays") {
                        settings.update { $0.displays.overrides.removeAll() }
                    }
                }
            }

            Section("Displays Without a Notch") {
                Picker("Virtual island", selection: settings.binding(\.displays.virtualIslandStyle)) {
                    ForEach(VirtualIslandStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ValueSlider(title: "Horizontal offset", value: settings.binding(\.displays.horizontalOffset), range: -600...600, step: 10, format: SettingsFormat.points)
                ValueSlider(title: "Vertical offset", value: settings.binding(\.displays.verticalOffset), range: 0...60, step: 1, format: SettingsFormat.points)
                    .disabled(displays.virtualIslandStyle != .floating)
                Toggle("Hide when there is nothing to show", isOn: settings.binding(\.displays.hideVirtualIslandWhenIdle))
                SettingsNote("A hidden island still expands when you move the pointer to it.")
            }
        }
        .formStyle(.grouped)
        .onAppear { monitor.refresh() }
    }

    private func description(of display: DisplayDescriptor) -> String {
        var parts = [display.isBuiltIn ? "Built-in" : "External"]
        parts.append("\(Int(display.frame.width))×\(Int(display.frame.height)) pt")
        if display.backingScale > 1 { parts.append("@\(Int(display.backingScale))x") }
        parts.append(display.hasNotch ? "Notch" : "Virtual island")
        return parts.joined(separator: " · ")
    }

    private func enabledBinding(for display: DisplayDescriptor) -> Binding<Bool> {
        Binding(
            get: { DisplaySelection.isEnabled(display, settings: settings.settings.displays) },
            set: { enabled in
                settings.update { settings in
                    let defaultValue = display.isBuiltIn ? settings.displays.showOnBuiltInDisplay : settings.displays.showOnExternalDisplays
                    settings.displays.overrides[display.id.rawValue] = enabled == defaultValue ? nil : enabled
                }
            }
        )
    }
}

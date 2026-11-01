import FeatureAudioMixer
import FeatureBluetooth
import FeatureCaffeinate
import IslandCore
import SwiftUI

struct SoundSettingsPane: View {
    let settings: SettingsStore
    let module: SoundMixerModule

    @State private var isConfirmingEnable = false

    private var mixer: SoundMixerSettings { settings.settings.soundMixer }

    var body: some View {
        Form {
            Section {
                Toggle("Per-app volume and equaliser", isOn: Binding(
                    get: { mixer.isEnabled },
                    set: { enabled in
                        if enabled { isConfirmingEnable = true } else { settings.update { $0.soundMixer.isEnabled = false } }
                    }
                ))
                .disabled(!module.isSupported)
                if !module.isSupported {
                    SettingsNote("Requires macOS 14.2 or later.")
                }
                if let error = module.errorMessage, mixer.isEnabled {
                    Text(error).foregroundStyle(.orange)
                    Button("Open System Audio Recording Settings…") { SoundMixerModule.openPrivacySettings() }
                }
            }

            Section("Equaliser") {
                Toggle("Equaliser on", isOn: settings.binding(\.soundMixer.equalizerEnabled))
                Picker("Preset", selection: settings.binding(\.soundMixer.equalizerPreset)) {
                    ForEach(EqualizerPreset.allCases) { Text($0.displayName).tag($0) }
                }
                SettingsNote("Adjust individual bands on the Sound page of the expanded island. Boosts are balanced automatically so loud passages do not distort.")
            }
            .disabled(!mixer.isEnabled)

            Section("Saved App Volumes") {
                if mixer.appVolumes.isEmpty && mixer.mutedApps.isEmpty {
                    Text("Every app plays at its normal volume.").foregroundStyle(.secondary)
                }
                ForEach(mixer.appVolumes.keys.sorted(), id: \.self) { bundleID in
                    LabeledContent(bundleID, value: "\(Int(((mixer.appVolumes[bundleID] ?? 1) * 100).rounded()))%")
                }
                ForEach(mixer.mutedApps, id: \.self) { bundleID in
                    LabeledContent(bundleID, value: "Muted")
                }
                Button("Reset All App Volumes") { settings.update { $0.soundMixer.resetApps() } }
                    .disabled(mixer.appVolumes.isEmpty && mixer.mutedApps.isEmpty)
            }

            Section("How It Works") {
                SettingsNote("When you change an app's volume or turn on the equaliser, IslandBar uses Core Audio process taps to take that app's sound, adjusts it, and plays it on your current output device. Apps you have not changed play directly as usual. Turning this off, or quitting IslandBar, restores normal audio immediately.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Turn on per-app volume?", isPresented: $isConfirmingEnable) {
            Button("Turn On") { settings.update { $0.soundMixer.isEnabled = true } }
        } message: {
            Text("macOS will ask you to allow IslandBar to record system audio. IslandBar only processes audio live to change volume and apply the equaliser; nothing is recorded or saved.")
        }
    }
}

struct BluetoothSettingsPane: View {
    let settings: SettingsStore
    let module: BluetoothModule

    var body: some View {
        Form {
            Section {
                Toggle("Show Bluetooth devices", isOn: settings.binding(\.bluetooth.isEnabled))
                Toggle("Announce devices connecting and disconnecting", isOn: settings.binding(\.bluetooth.announceConnections))
                Toggle("Warn when a device's battery is low", isOn: settings.binding(\.bluetooth.lowBatteryAlerts))
            }
            Section("Connected Now") {
                if module.devices.isEmpty {
                    Text("No Bluetooth audio or input devices connected.").foregroundStyle(.secondary)
                }
                ForEach(module.devices) { device in
                    LabeledContent {
                        Text(device.batteryPercent.map { "\($0)%" } ?? device.kind.displayName)
                    } label: {
                        Label(device.name, systemImage: device.symbolName)
                    }
                }
            }
            Section("How It Works") {
                SettingsNote("IslandBar reads which Bluetooth headphones, speakers, keyboards, mice and trackpads are connected from macOS's device lists, so it needs no Bluetooth permission. Battery levels appear for devices that report them, such as Apple keyboards, mice and trackpads; macOS does not share AirPods battery levels with other apps.")
            }
        }
        .formStyle(.grouped)
    }
}

struct CaffeinateSettingsPane: View {
    let settings: SettingsStore
    let module: CaffeinateModule

    var body: some View {
        Form {
            Section {
                Toggle("Show Keep Awake", isOn: settings.binding(\.caffeinate.isEnabled))
                Toggle("Let the display sleep (keep the Mac itself awake)", isOn: settings.binding(\.caffeinate.allowDisplaySleep))
                Toggle("Show in the compact island while on", isOn: settings.binding(\.caffeinate.showLiveActivity))
            }
            Section("Now") {
                HStack {
                    Text(module.state.isActive ? "Keeping your Mac awake" : "Off")
                    Spacer()
                    if module.state.isActive {
                        Button("Turn Off") { module.stop() }
                    } else {
                        Menu("Turn On") {
                            ForEach(CaffeinateDuration.allCases) { duration in
                                Button(duration.displayName) { module.start(duration) }
                            }
                        }
                        .fixedSize()
                    }
                }
                if let error = module.lastError {
                    Text(error).foregroundStyle(.orange)
                }
            }
            Section {
                SettingsNote("Uses the same power assertion as macOS's caffeinate command. It ends automatically when the time runs out or IslandBar quits, so your Mac never stays awake by accident. Use the cup in the island's header or the menu bar to turn it on quickly.")
            }
        }
        .formStyle(.grouped)
    }
}

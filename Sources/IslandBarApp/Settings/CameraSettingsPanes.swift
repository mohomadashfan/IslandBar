import FeatureMirror
import FeaturePrivacyIndicators
import IslandCore
import SwiftUI

struct PrivacyIndicatorSettingsPane: View {
    let settings: SettingsStore
    let module: PrivacyIndicatorModule

    var body: some View {
        Form {
            Section {
                Toggle("Show when the camera or microphone is in use", isOn: settings.binding(\.privacyIndicators.isEnabled))
                Toggle("Camera", isOn: settings.binding(\.privacyIndicators.showCamera))
                Toggle("Microphone", isOn: settings.binding(\.privacyIndicators.showMicrophone))
                Toggle("Show in the compact island while in use", isOn: settings.binding(\.privacyIndicators.showLiveActivity))
            }
            Section("Right Now") {
                LabeledContent("Camera", value: module.usage.cameraInUse ? module.usage.activeCameras.joined(separator: ", ") : "Not in use")
                LabeledContent("Microphone", value: microphoneText)
            }
            Section("How It Works") {
                SettingsNote("IslandBar listens for macOS's own device-state changes through CoreAudio and CoreMediaIO. It never captures audio or video for this, needs no permission, and does no polling.")
                SettingsNote("macOS tells apps which process is using the microphone (on macOS 14.2 and later) but not which app is using the camera. Always-on system listeners such as “Hey Siri” detection are ignored, as macOS's own indicator does.")
            }
        }
        .formStyle(.grouped)
    }

    private var microphoneText: String {
        guard module.usage.microphoneInUse else { return "Not in use" }
        return module.usage.microphoneApps.isEmpty ? "In use" : module.usage.microphoneApps.joined(separator: ", ")
    }
}

struct MirrorSettingsPane: View {
    let settings: SettingsStore
    let module: MirrorModule

    var body: some View {
        Form {
            Section {
                Toggle("Show the Mirror page", isOn: settings.binding(\.mirror.isEnabled))
                Toggle("Flip the image like a mirror", isOn: settings.binding(\.mirror.mirrorImage))
                Toggle("Start the camera when the Mirror page opens", isOn: settings.binding(\.mirror.startAutomatically))
                SettingsNote("When off, the camera only starts after you tap “Turn On Camera”. Either way it turns off as soon as the island closes or you switch pages.")
            }
            Section("Camera") {
                Picker("Camera", selection: settings.binding(\.mirror.cameraID)) {
                    Text("System default").tag(String?.none)
                    ForEach(module.cameras) { camera in
                        Text(camera.name).tag(Optional(camera.id))
                    }
                }
                if !MirrorModule.isAvailable {
                    SettingsNote("The camera is only available when running the bundled IslandBar.app.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

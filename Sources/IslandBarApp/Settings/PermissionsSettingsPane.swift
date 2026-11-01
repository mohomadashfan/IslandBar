import AVFoundation
import FeatureAudioMixer
import FeatureMedia
import FeatureMirror
import FeatureNotifications
import IslandCore
import SwiftUI

struct PermissionsSettingsPane: View {
    let environment: AppEnvironment

    @State private var automation: [PlayerKind: AutomationPermission] = [:]
    @State private var isConfirmingErase = false

    var body: some View {
        Form {
            Section("Automation (Media controls)") {
                ForEach(PlayerKind.allCases) { player in
                    LabeledContent(player.displayName) {
                        HStack {
                            Text(automation[player]?.displayName ?? "Checking…").foregroundStyle(.secondary)
                            if automation[player] == .notDetermined {
                                Button("Allow…") { request(player) }
                            }
                        }
                    }
                }
                SettingsNote("For Music and Spotify, lets IslandBar play, pause and skip tracks and read artwork and playback position; track names appear even without it. For browsers, it is needed to see what media tabs are playing (browsers are only used if you turn them on in Settings › Media). macOS can only report the status while the app is running.")
                Button("Open Automation Settings…") { AutomationPermission.openSystemSettings() }
            }

            Section("Camera (Mirror)") {
                LabeledContent("Camera", value: describe(camera: AVCaptureDevice.authorizationStatus(for: .video)))
                SettingsNote("Only requested when you tap “Turn On Camera” on the Mirror page. Video is shown live and never recorded or sent anywhere.")
                Button("Open Camera Privacy Settings…") { MirrorModule.openPrivacySettings() }
            }

            Section("System Audio Recording (Sound)") {
                SettingsNote("Only requested when you turn on per-app volume in Settings › Sound. macOS lists this under Screen & System Audio Recording › System Audio Recording Only. IslandBar uses it to route apps' audio through its mixer; nothing is recorded or saved.")
                Button("Open System Audio Recording Settings…") { SoundMixerModule.openPrivacySettings() }
            }

            Section("Camera & Microphone Indicator") {
                SettingsNote("Detecting that a camera or microphone is in use needs no permission. IslandBar never captures audio, and never uses the camera except for Mirror.")
            }

            Section("Notifications") {
                LabeledContent("Notification Center", value: NotificationsModule.isSystemDeliveryAvailable
                               ? PermissionText.describe(environment.notifications.systemAuthorization)
                               : "Unavailable outside the app bundle")
                SettingsNote("Only requested if you turn on “Also send to Notification Center”.")
            }

            Section("Files") {
                SettingsNote("Files you drop on the shelf are accessible because you dropped them. If a file lives in Desktop, Documents or Downloads, macOS may ask once for access to that folder after a restart. Full Disk Access is not needed.")
            }

            Section("Login Item") {
                LabeledContent("Launch at login", value: environment.loginItem.isEnabled ? "On" : (environment.loginItem.requiresApproval ? "Needs approval" : "Off"))
            }

            Section("Your Data") {
                SettingsNote("Everything IslandBar keeps stays on this Mac, in one folder readable only by your account: settings, Focus notes, the File Shelf's file references and (if you turn it on) incoming developer events. Recent activity is kept in memory only and is gone when IslandBar quits.")
                LabeledContent("Location") {
                    Text(AppPaths.applicationSupportDirectory().path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Show in Finder") {
                        let folder = AppPaths.applicationSupportDirectory()
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    Spacer()
                    Button("Erase All IslandBar Data…", role: .destructive) { isConfirmingErase = true }
                }
            }

            Section("Revoking Permissions") {
                SettingsNote("Permissions you granted belong to macOS. Revoke them any time in System Settings › Privacy & Security, or reset all of IslandBar's at once in Terminal:")
                Text("tccutil reset All \(Bundle.main.bundleIdentifier ?? "io.github.islandbar.IslandBar")")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Not Used") {
                SettingsNote("IslandBar never asks for Accessibility, Input Monitoring, Screen Recording, Full Disk Access, Location, Microphone or Contacts. The keyboard shortcut and click-outside detection work without them. There is no telemetry and no network access, except artwork downloads if you turn them on.")
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .confirmationDialog("Erase all IslandBar data?", isPresented: $isConfirmingErase) {
            Button("Erase and Quit", role: .destructive) { environment.eraseAllDataAndQuit() }
        } message: {
            Text("Deletes your settings, Focus notes and shelf, turns off launch at login, and quits. Your files on the shelf are not touched. Permissions in System Settings are not changed.")
        }
    }

    private func describe(camera status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func refresh() async {
        for player in PlayerKind.allCases {
            automation[player] = await AutomationPermission.determine(for: player.bundleIdentifier, askUserIfNeeded: false)
        }
        environment.notifications.refreshAuthorization()
        environment.loginItem.refresh()
    }

    private func request(_ player: PlayerKind) {
        Task {
            automation[player] = await AutomationPermission.determine(for: player.bundleIdentifier, askUserIfNeeded: true)
        }
    }
}

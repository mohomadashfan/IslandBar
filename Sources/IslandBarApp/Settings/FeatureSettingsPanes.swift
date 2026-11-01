import AppKit
import FeatureDeveloper
import FeatureFileShelf
import FeatureFocus
import FeatureMedia
import FeatureNotifications
import FeatureSystemMonitor
import IslandCore
import SwiftUI
import UserNotifications

struct MediaSettingsPane: View {
    let settings: SettingsStore
    let module: MediaModule

    @State private var newSite = ""

    private var media: MediaSettings { settings.settings.media }
    private let browsers: [(PlayerKind, WritableKeyPath<AppSettings, Bool>)] = [
        (.chrome, \.media.browserChrome), (.safari, \.media.browserSafari),
        (.edge, \.media.browserEdge), (.brave, \.media.browserBrave),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Show media in the island", isOn: settings.binding(\.media.isEnabled))
                Toggle("Show playback as a live activity", isOn: settings.binding(\.media.showLiveActivity))
            }
            Section("Apps") {
                Toggle("Music", isOn: settings.binding(\.media.useAppleMusic))
                Toggle("Spotify", isOn: settings.binding(\.media.useSpotify))
            }

            Section("Web Browsers") {
                Toggle("Show media playing in web browsers", isOn: settings.binding(\.media.useBrowsers))
                if media.useBrowsers {
                    ForEach(browsers, id: \.0) { browser, keyPath in
                        LabeledContent {
                            HStack {
                                if settings.settings[keyPath: keyPath] {
                                    browserStatus(browser)
                                }
                                Toggle("", isOn: settings.binding(keyPath)).labelsHidden()
                            }
                        } label: {
                            Text(browser.displayName)
                        }
                    }
                    SettingsNote("Each browser needs two things, once: allow IslandBar under Automation when macOS asks, and in the browser turn on **Allow JavaScript from Apple Events** (Chrome, Edge, Brave: View › Developer; Safari: Settings › Advanced › Show features for web developers, then the Develop menu).")
                    SettingsNote("IslandBar only looks at tabs on the sites below, and only reads whether audio or video is playing, its title and position. It never reads page content, form data or cookies. Note that the browser setting lets any app you have allowed to control that browser run scripts in its pages.")
                }
            }

            if media.useBrowsers {
                Section("Sites") {
                    ForEach(media.browserSites, id: \.self) { site in
                        HStack {
                            Text(site)
                            Spacer()
                            Button("Remove") {
                                settings.update { $0.media.browserSites.removeAll { $0 == site } }
                            }
                        }
                    }
                    HStack {
                        TextField("Add a site, e.g. music.example.com", text: $newSite)
                            .onSubmit(addSite)
                        Button("Add", action: addSite)
                            .disabled(BrowserMedia.normalizedSite(newSite).isEmpty)
                    }
                    Button("Restore Default Sites") {
                        settings.update { $0.media.browserSites = MediaSettings.defaultBrowserSites }
                    }
                    .disabled(media.browserSites == MediaSettings.defaultBrowserSites)
                }
            }

            Section("Artwork") {
                Toggle("Download artwork from the web", isOn: settings.binding(\.media.fetchRemoteArtwork))
                SettingsNote("Spotify and websites only provide artwork as a web address. When this is on, IslandBar downloads it over HTTPS from the service's own image servers (for example i.scdn.co or i.ytimg.com). Music artwork is always read locally.")
            }

            Section("How It Works") {
                SettingsNote("macOS has no public API for system-wide “Now Playing” information. IslandBar reads the track updates Music and Spotify broadcast themselves, and, if you turn it on, asks your browser what its media tabs are playing. Controls, playback position and Music artwork use AppleScript, which macOS asks you to allow once per app.")
                Button("Open Automation Privacy Settings…") { AutomationPermission.openSystemSettings() }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func browserStatus(_ browser: PlayerKind) -> some View {
        switch module.setupHint(for: browser) {
        case .allowAutomation:
            Button("Allow Access…") { module.requestPermission(for: browser) }
        case .enableJavaScript:
            Label("Turn on JavaScript from Apple Events", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(browser.javaScriptSettingLocation ?? "")
        case nil:
            if module.permission(for: browser) == .granted {
                Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                Text("Not running").foregroundStyle(.secondary)
            }
        }
    }

    private func addSite() {
        let site = BrowserMedia.normalizedSite(newSite)
        guard !site.isEmpty else { return }
        settings.update { settings in
            if !settings.media.browserSites.contains(site) {
                settings.media.browserSites.append(site)
            }
        }
        newSite = ""
    }
}

struct ShelfSettingsPane: View {
    let settings: SettingsStore
    let module: FileShelfModule

    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable the File Shelf", isOn: settings.binding(\.shelf.isEnabled))
                Picker("Remove items", selection: settings.binding(\.shelf.expiry)) {
                    ForEach(ShelfExpiry.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Stepper("Keep at most \(settings.settings.shelf.maxItems) items", value: settings.binding(\.shelf.maxItems), in: 5...100, step: 5)
            }
            Section {
                SettingsNote("Drag files onto the island to park them. The shelf stores a reference to each file, never a copy, and removing an item never deletes the file.")
                HStack {
                    Text("\(module.items.count) item\(module.items.count == 1 ? "" : "s") on the shelf")
                    Spacer()
                    Button("Clear Shelf…") { isConfirmingClear = true }
                        .disabled(module.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove all items from the shelf?", isPresented: $isConfirmingClear) {
            Button("Clear Shelf", role: .destructive) { module.removeAll() }
        } message: {
            Text("Your files are not affected.")
        }
    }
}

struct FocusSettingsPane: View {
    let settings: SettingsStore
    let module: FocusModule

    var body: some View {
        let focus = settings.settings.focus
        Form {
            Section {
                Toggle("Enable the Focus timer", isOn: settings.binding(\.focus.isEnabled))
                Toggle("Show the countdown as a live activity", isOn: settings.binding(\.focus.showLiveActivity))
            }
            Section("Durations") {
                Stepper("Focus: \(Int(focus.workMinutes)) min", value: settings.binding(\.focus.workMinutes), in: 1...180, step: 1)
                Stepper("Short break: \(Int(focus.shortBreakMinutes)) min", value: settings.binding(\.focus.shortBreakMinutes), in: 1...60, step: 1)
                Stepper("Long break: \(Int(focus.longBreakMinutes)) min", value: settings.binding(\.focus.longBreakMinutes), in: 1...120, step: 1)
                Stepper("Long break after \(focus.sessionsBeforeLongBreak) sessions", value: settings.binding(\.focus.sessionsBeforeLongBreak), in: 1...12)
                Toggle("Start the next phase automatically", isOn: settings.binding(\.focus.autoStartNextPhase))
            }
            Section {
                SettingsNote("The timer keeps running while IslandBar is quit or the Mac is asleep; it is calculated from timestamps.")
                HStack {
                    Text("\(module.timer.completedWorkSessions) sessions completed")
                    Spacer()
                    Button("Reset Sessions") { module.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettingsPane: View {
    let settings: SettingsStore
    let module: SystemMonitorModule

    var body: some View {
        Form {
            Section {
                Toggle("Enable System Monitor", isOn: settings.binding(\.systemMonitor.isEnabled))
                ValueSlider(title: "Update every", value: settings.binding(\.systemMonitor.sampleInterval),
                            range: SystemMonitorSettings.sampleIntervalRange, step: 0.5, format: { String(format: "%.1f s", $0) })
                Picker("Compact indicator", selection: settings.binding(\.systemMonitor.compactIndicator)) {
                    ForEach(SystemIndicator.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                SettingsNote("Metrics are only sampled while the System page is open, or continuously while a compact indicator is chosen.")
            }
            Section("Metrics") {
                Toggle("CPU", isOn: settings.binding(\.systemMonitor.showCPU))
                Toggle("Memory", isOn: settings.binding(\.systemMonitor.showMemory))
                Toggle("Network", isOn: settings.binding(\.systemMonitor.showNetwork))
                Toggle("Disk", isOn: settings.binding(\.systemMonitor.showDisk))
                Toggle("Battery", isOn: settings.binding(\.systemMonitor.showBattery))
                Toggle("GPU utilization", isOn: settings.binding(\.systemMonitor.showGPU))
                SettingsNote("GPU utilization is read from statistics the graphics driver publishes and is not available on every Mac. Temperatures have no public API and are not shown.")
            }
            Section("This Mac") {
                Text(module.hardware.summary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

struct DeveloperSettingsPane: View {
    let settings: SettingsStore
    let module: DeveloperModule

    @State private var addError: String?

    private var exampleCommand: String {
        "scripts/islandbar-event --kind build --state running --title \"swift build\""
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Developer Activity", isOn: settings.binding(\.developer.isEnabled))
                Toggle("Show running activity in the compact island", isOn: settings.binding(\.developer.showLiveActivity))
            }

            Section("Git Repositories") {
                if settings.settings.developer.repositories.isEmpty {
                    Text("No repositories added.").foregroundStyle(.secondary)
                }
                ForEach(settings.settings.developer.repositories, id: \.self) { path in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                            Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remove") {
                            settings.update { $0.developer.repositories.removeAll { $0 == path } }
                        }
                    }
                }
                HStack {
                    Button("Add Repository…", action: addRepository)
                    if let addError {
                        Text(addError).foregroundStyle(.orange)
                    }
                }
                SettingsNote("IslandBar watches only the folders you add here and runs read-only git commands. It does not take Git's index lock, so it never gets in the way of your own git operations.")
            }

            Section("Local Events") {
                Toggle("Accept events from local tools", isOn: settings.binding(\.developer.eventInboxEnabled))
                LabeledContent("Events folder") {
                    HStack {
                        Text(module.inboxPath).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Button("Show") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: module.inboxPath)])
                        }
                    }
                }
                Stepper("Treat running items as stale after \(Int(settings.settings.developer.staleActivityMinutes)) min",
                        value: settings.binding(\.developer.staleActivityMinutes), in: 5...240, step: 5)
                SettingsNote("Build scripts, VS Code tasks and coding agents can report progress by writing small JSON files into this folder; IslandBar never monitors other apps on its own. Use the bundled helper, for example:")
                Text(exampleCommand).font(.caption.monospaced()).textSelection(.enabled)
                if module.rejectedEventCount > 0 {
                    Text("\(module.rejectedEventCount) invalid event file\(module.rejectedEventCount == 1 ? " was" : "s were") ignored.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more Git repositories to follow."
        guard panel.runModal() == .OK else { return }

        let chosen = panel.urls.map(\.standardizedFileURL.path)
        let repositories = chosen.filter(GitParser.isRepository)
        addError = repositories.count < chosen.count ? "Some folders are not Git repositories and were skipped." : nil
        settings.update { settings in
            for path in repositories where !settings.developer.repositories.contains(path) {
                settings.developer.repositories.append(path)
            }
        }
    }
}

struct NotificationSettingsPane: View {
    let settings: SettingsStore
    let module: NotificationsModule

    var body: some View {
        let notifications = settings.settings.notifications
        Form {
            Section("In the Island") {
                Toggle("Show activity banners", isOn: settings.binding(\.notifications.showBanners))
                ValueSlider(title: "Banner duration", value: settings.binding(\.notifications.bannerDuration), range: 1...10, step: 0.5, format: { String(format: "%.1f s", $0) })
                    .disabled(!notifications.showBanners)
                Toggle("Show the recent activity page", isOn: settings.binding(\.notifications.showHistoryTab))
            }
            Section("Sources") {
                Toggle("Focus timer", isOn: settings.binding(\.notifications.focusBanners))
                Toggle("File Shelf", isOn: settings.binding(\.notifications.shelfBanners))
                Toggle("Developer activity", isOn: settings.binding(\.notifications.developerBanners))
                Toggle("Media track changes", isOn: settings.binding(\.notifications.mediaBanners))
                Toggle("System (low battery)", isOn: settings.binding(\.notifications.systemBanners))
                Toggle("Camera and microphone turning on", isOn: settings.binding(\.notifications.privacyBanners))
                Toggle("Bluetooth devices", isOn: settings.binding(\.notifications.deviceBanners))
            }
            Section("macOS Notifications") {
                Toggle("Also send to Notification Center", isOn: settings.binding(\.notifications.deliverSystemNotifications))
                    .disabled(!NotificationsModule.isSystemDeliveryAvailable)
                if !NotificationsModule.isSystemDeliveryAvailable {
                    SettingsNote("Only available when running the bundled IslandBar.app.")
                } else if notifications.deliverSystemNotifications {
                    LabeledContent("Permission", value: describe(module.systemAuthorization))
                    Button("Open Notification Settings…") { NotificationsModule.openSystemSettings() }
                }
                SettingsNote("IslandBar only shows its own activity. It cannot read notifications from other apps.")
            }
        }
        .formStyle(.grouped)
        .onAppear { module.refreshAuthorization() }
    }

    private func describe(_ status: UNAuthorizationStatus?) -> String {
        PermissionText.describe(status)
    }
}

enum PermissionText {
    static func describe(_ status: UNAuthorizationStatus?) -> String {
        switch status {
        case .authorized: "Allowed"
        case .provisional: "Allowed quietly"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        case .ephemeral: "Temporary"
        case nil: "Unknown"
        @unknown default: "Unknown"
        }
    }
}

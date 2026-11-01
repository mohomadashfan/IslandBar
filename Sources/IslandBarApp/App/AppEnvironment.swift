import AppKit
import FeatureAudioMixer
import FeatureBluetooth
import FeatureCaffeinate
import FeatureDeveloper
import FeatureFileShelf
import FeatureFocus
import FeatureMedia
import FeatureMirror
import FeatureNotifications
import FeaturePrivacyIndicators
import FeatureSystemMonitor
import IslandCore
import IslandDesign
import IslandWindows
import Observation
import SwiftUI

/// Composition root: builds and owns the long-lived services and hands them out explicitly.
/// Nothing else in the app reaches for globals or singletons of our own.
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let activity = ActivityCenter()
    let registry = FeatureRegistry()
    let loginItem = LoginItemController()

    let media: MediaModule
    let shelf: FileShelfModule
    let focus: FocusModule
    let system: SystemMonitorModule
    let developer: DeveloperModule
    let notifications: NotificationsModule
    let privacy: PrivacyIndicatorModule
    let mirror: MirrorModule
    let soundMixer: SoundMixerModule
    let bluetooth: BluetoothModule
    let caffeinate: CaffeinateModule
    let modules: [any IslandModule]

    let presenter: IslandPresenter
    let islands: IslandManager
    private(set) var hotKeyError: String?

    private var settingsWindow: SettingsWindowController?
    private var hotKey: GlobalHotKey?
    private var registeredShortcut: ToggleShortcut?
    private var isStarted = false

    init() {
        settings = SettingsStore(persistence: JSONFileStore(fileURL: AppPaths.settingsFile(), defaults: .defaults))

        media = MediaModule(activity: activity)
        shelf = FileShelfModule(activity: activity)
        focus = FocusModule(activity: activity)
        system = SystemMonitorModule(activity: activity)
        developer = DeveloperModule(activity: activity)
        notifications = NotificationsModule(activity: activity)
        privacy = PrivacyIndicatorModule(activity: activity)
        mirror = MirrorModule(settings: settings)
        soundMixer = SoundMixerModule(settings: settings)
        bluetooth = BluetoothModule(activity: activity)
        caffeinate = CaffeinateModule(activity: activity)
        // Order here is the order of the module switcher in the expanded island.
        modules = [media, soundMixer, shelf, focus, mirror, system, bluetooth, developer, privacy, notifications, caffeinate]
        for module in modules {
            do {
                try registry.register(module)
            } catch {
                assertionFailure("Duplicate feature id \(module.id.rawValue)")
            }
        }

        let presenter = IslandPresenter(settings: settings, activity: activity, registry: registry, modules: modules)
        self.presenter = presenter
        islands = IslandManager(
            configuration: IslandWindowConfiguration(settings: settings.settings),
            makeRootView: { model in AnyView(IslandRootView(model: model, presenter: presenter)) },
            frameProvider: { model in presenter.frameRequest(for: model) }
        )
        presenter.openSettings = { [weak self] in self?.openSettings() }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        AppPaths.secureDataDirectory()
        applySettings()
        islands.start()
        observeSettings()
        #if DEBUG
        installDebugHooks()
        #endif
    }

    #if DEBUG
    /// Development aid for screenshots and UI review: lets a local script expand the island to a
    /// page without a pointer. Compiled out of release builds.
    private var debugObservers: [NSObjectProtocol] = []

    private func installDebugHooks() {
        let center = DistributedNotificationCenter.default()
        debugObservers.append(center.addObserver(forName: Notification.Name("io.github.islandbar.debug.expand"), object: nil, queue: .main) { [weak self] note in
            let page = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let model = self.islands.models.first else { return }
                if let page { self.presenter.requestPage(FeatureID(rawValue: page)) }
                if !model.presentation.isExpanded { model.toggle() }
            }
        })
        debugObservers.append(center.addObserver(forName: Notification.Name("io.github.islandbar.debug.collapse"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.islands.collapseAll() }
        })
    }
    #endif

    /// Set when the user erases their data, so quitting does not write settings back.
    private var isErasing = false

    /// Stops every module, deletes everything IslandBar has stored and quits. Permissions granted
    /// in System Settings are owned by macOS and must be revoked there.
    func eraseAllDataAndQuit() {
        isErasing = true
        registry.deactivateAll()
        islands.stop()
        loginItem.setEnabled(false)
        try? FileManager.default.removeItem(at: AppPaths.applicationSupportDirectory())
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        NSApp.terminate(nil)
    }

    func shutdown() {
        guard !isErasing else { return }
        settings.flush()
        registry.deactivateAll()
        islands.stop()
        hotKey?.unregister()
    }

    func openSettings(_ section: SettingsSection? = nil) {
        let controller = settingsWindow ?? SettingsWindowController(environment: self)
        settingsWindow = controller
        controller.show(section: section)
    }

    // MARK: Settings propagation

    private func observeSettings() {
        withObservationTracking {
            _ = settings.settings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.applySettings()
                self.observeSettings()
            }
        }
    }

    private func applySettings() {
        let current = settings.settings
        activity.configuration = ActivityCenter.Configuration(current.notifications)
        for module in modules {
            module.apply(current)
            registry.setEnabled(module.isEnabled(in: current), for: module.id)
        }
        islands.apply(IslandWindowConfiguration(settings: current))
        updateHotKey(current.general.isIslandEnabled ? current.general.toggleShortcut : .disabled)
    }

    private func updateHotKey(_ shortcut: ToggleShortcut) {
        guard shortcut != registeredShortcut else { return }
        hotKey?.unregister()
        hotKey = nil
        registeredShortcut = shortcut
        hotKeyError = nil
        guard shortcut != .disabled else { return }
        hotKey = GlobalHotKey(shortcut: shortcut) { [weak self] in
            self?.islands.toggleOnActiveDisplay()
        }
        if hotKey == nil {
            hotKeyError = "\(shortcut.displayName) is already used by another app."
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    /// `swift run` executes a bare binary; some system services (login items, notifications)
    /// only work from inside an .app bundle.
    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Login items point at a specific copy of the app, so they should point at the installed one.
    static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }
}

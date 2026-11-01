import AppKit
import Observation
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, animation, displays
    case media, sound, shelf, focus, mirror, privacy, bluetooth, caffeinate, system, developer, notifications
    case permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .animation: "Animation"
        case .displays: "Displays"
        case .media: "Media"
        case .shelf: "File Shelf"
        case .focus: "Focus"
        case .mirror: "Mirror"
        case .sound: "Sound"
        case .bluetooth: "Bluetooth Devices"
        case .caffeinate: "Keep Awake"
        case .privacy: "Camera & Mic"
        case .system: "System Monitor"
        case .developer: "Developer"
        case .notifications: "Notifications"
        case .permissions: "Privacy & Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .animation: "wand.and.stars"
        case .displays: "display.2"
        case .media: "music.note"
        case .shelf: "tray.full"
        case .focus: "timer"
        case .mirror: "person.crop.square"
        case .sound: "slider.vertical.3"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .caffeinate: "cup.and.saucer"
        case .privacy: "video"
        case .system: "gauge.with.dots.needle.33percent"
        case .developer: "hammer"
        case .notifications: "bell.badge"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    static let groups: [[SettingsSection]] = [
        [.general, .appearance, .animation, .displays],
        [.media, .sound, .shelf, .focus, .mirror, .privacy, .bluetooth, .caffeinate, .system, .developer, .notifications],
        [.permissions, .about],
    ]
}

@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsSection? = .general
}

/// The settings window is a plain AppKit window so that both the menu bar and the island can open
/// it reliably; SwiftUI's `Settings` scene cannot be opened from an `NSPanel`.
@MainActor
final class SettingsWindowController {
    private let environment: AppEnvironment
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show(section: SettingsSection?) {
        if let section {
            navigation.selection = section
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(environment: environment, navigation: navigation)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "IslandBar Settings"
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentMinSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("IslandBarSettings")
        if !window.setFrameUsingName("IslandBarSettings") {
            window.center()
        }
        return window
    }
}

struct SettingsRootView: View {
    let environment: AppEnvironment
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(SettingsSection.groups.indices, id: \.self) { index in
                    Section {
                        ForEach(SettingsSection.groups[index]) { section in
                            Label(section.title, systemImage: section.symbol).tag(section)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail(for: navigation.selection ?? .general)
                .navigationTitle((navigation.selection ?? .general).title)
        }
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsPane(environment: environment)
        case .appearance: AppearanceSettingsPane(settings: environment.settings)
        case .animation: AnimationSettingsPane(settings: environment.settings)
        case .displays: DisplaySettingsPane(settings: environment.settings, monitor: environment.islands.displayMonitor)
        case .media: MediaSettingsPane(settings: environment.settings, module: environment.media)
        case .shelf: ShelfSettingsPane(settings: environment.settings, module: environment.shelf)
        case .focus: FocusSettingsPane(settings: environment.settings, module: environment.focus)
        case .mirror: MirrorSettingsPane(settings: environment.settings, module: environment.mirror)
        case .sound: SoundSettingsPane(settings: environment.settings, module: environment.soundMixer)
        case .bluetooth: BluetoothSettingsPane(settings: environment.settings, module: environment.bluetooth)
        case .caffeinate: CaffeinateSettingsPane(settings: environment.settings, module: environment.caffeinate)
        case .privacy: PrivacyIndicatorSettingsPane(settings: environment.settings, module: environment.privacy)
        case .system: SystemSettingsPane(settings: environment.settings, module: environment.system)
        case .developer: DeveloperSettingsPane(settings: environment.settings, module: environment.developer)
        case .notifications: NotificationSettingsPane(settings: environment.settings, module: environment.notifications)
        case .permissions: PermissionsSettingsPane(environment: environment)
        case .about: AboutSettingsPane()
        }
    }
}

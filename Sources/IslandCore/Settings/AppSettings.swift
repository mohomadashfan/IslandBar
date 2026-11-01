import Foundation

/// Root of all persisted user preferences.
///
/// Every property has a default. Stored files are decoded by merging them over the defaults
/// (see `JSONMerge`), so files written by older versions keep loading after options are added.
public struct AppSettings: Codable, Sendable, Equatable {
    /// 2: the expanded island gained a page dock, so the default height grew from 200 to 236.
    /// 3: the developer events folder became opt-in.
    public static let currentSchemaVersion = 3
    public static let defaults = AppSettings()

    public var schemaVersion = AppSettings.currentSchemaVersion
    public var general = GeneralSettings()
    public var appearance = AppearanceSettings()
    public var animation = AnimationSettings()
    public var displays = DisplaySettings()
    public var media = MediaSettings()
    public var shelf = FileShelfSettings()
    public var focus = FocusSettings()
    public var systemMonitor = SystemMonitorSettings()
    public var developer = DeveloperSettings()
    public var privacyIndicators = PrivacyIndicatorSettings()
    public var mirror = MirrorSettings()
    public var soundMixer = SoundMixerSettings()
    public var bluetooth = BluetoothSettings()
    public var caffeinate = CaffeinateSettings()
    public var notifications = NotificationSettings()

    public init() {}

    /// Decodes settings, filling anything missing from `defaults`.
    public static func decode(from data: Data) throws -> AppSettings {
        try JSONMerge.decode(AppSettings.self, from: data, over: .defaults).migrated()
    }

    /// Upgrades settings written by older versions.
    public func migrated() -> AppSettings {
        var settings = self
        if settings.schemaVersion < 2 {
            // Keep the content area the same size now that the page dock takes ~36 pt.
            if settings.appearance.layout.expandedHeight == 200 {
                settings.appearance.layout.expandedHeight = LayoutSettings().expandedHeight
            }
        }
        if settings.schemaVersion < 3 {
            // Earlier versions enabled it by default; nobody explicitly chose it.
            settings.developer.eventInboxEnabled = false
        }
        settings.schemaVersion = Self.currentSchemaVersion
        return settings
    }
}

public enum ToggleShortcut: String, Codable, Sendable, CaseIterable {
    case disabled
    case controlOptionSpace
    case controlOptionI

    public var displayName: String {
        switch self {
        case .disabled: "None"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionI: "⌃⌥I"
        }
    }
}

public struct GeneralSettings: Codable, Sendable, Equatable {
    /// Master switch for showing the island on any display.
    public var isIslandEnabled = true
    public var expandOnHover = true
    /// Seconds the pointer must rest on the island before it expands.
    public var hoverDelay = 0.15
    /// Seconds after the pointer leaves before a hover-expanded island collapses.
    public var collapseDelay = 0.35
    public var collapseOnClickOutside = true
    public var toggleShortcut = ToggleShortcut.controlOptionSpace
    public var showInFullScreenApps = false
    public var hapticFeedback = true
    /// Ask macOS to leave the island out of screenshots, recordings and screen sharing, so notes,
    /// notifications and track titles are not shown to an audience.
    public var hideFromScreenCapture = true

    public init() {}
}

public enum VirtualIslandStyle: String, Codable, Sendable, CaseIterable {
    /// Flush with the top edge of the screen, like a notch.
    case attachedToTop
    /// Floating just below the menu bar.
    case floating

    public var displayName: String {
        switch self {
        case .attachedToTop: "Attached to top edge"
        case .floating: "Floating below menu bar"
        }
    }
}

public struct DisplaySettings: Codable, Sendable, Equatable {
    public var showOnBuiltInDisplay = true
    public var showOnExternalDisplays = true
    /// Per-display choice keyed by display UUID; takes precedence over the two flags above.
    public var overrides: [String: Bool] = [:]
    public var virtualIslandStyle = VirtualIslandStyle.attachedToTop
    /// Horizontal offset of the virtual island from the screen centre, in points.
    public var horizontalOffset = 0.0
    /// Extra distance below the menu bar for floating virtual islands, in points.
    public var verticalOffset = 0.0
    /// Hide the virtual island entirely while it has nothing to show (still hoverable).
    public var hideVirtualIslandWhenIdle = false

    public init() {}
}

public struct NotificationSettings: Codable, Sendable, Equatable {
    /// Shows the recent-activity list as a page of the expanded island.
    public var showHistoryTab = true
    public var showBanners = true
    public var bannerDuration = 4.0
    public var focusBanners = true
    public var shelfBanners = true
    public var developerBanners = true
    public var mediaBanners = false
    public var systemBanners = true
    public var privacyBanners = true
    public var deviceBanners = true
    /// Also deliver activity as macOS notifications (asks for permission when enabled).
    public var deliverSystemNotifications = false
    public var historyLimit = 30

    public init() {}

    public var enabledSources: Set<ActivitySource> {
        var sources: Set<ActivitySource> = [.app]
        if focusBanners { sources.insert(.focus) }
        if shelfBanners { sources.insert(.shelf) }
        if developerBanners { sources.insert(.developer) }
        if mediaBanners { sources.insert(.media) }
        if systemBanners { sources.insert(.system) }
        if privacyBanners { sources.insert(.privacy) }
        if deviceBanners { sources.insert(.devices) }
        return sources
    }
}

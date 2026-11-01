import Foundation

public struct MediaSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var useAppleMusic = true
    public var useSpotify = true
    public var showLiveActivity = true
    /// Spotify and web players only expose artwork as a URL; fetching it contacts their image servers.
    public var fetchRemoteArtwork = false

    /// Read playback from browser tabs via the browser's AppleScript support. Off by default
    /// because it requires "Allow JavaScript from Apple Events" in the browser.
    public var useBrowsers = false
    public var browserChrome = true
    public var browserSafari = true
    public var browserEdge = true
    public var browserBrave = true
    /// Only tabs on these sites (and their subdomains) are inspected.
    public var browserSites = MediaSettings.defaultBrowserSites

    public init() {}

    public static let defaultBrowserSites = [
        "youtube.com", "soundcloud.com", "open.spotify.com", "music.apple.com", "bandcamp.com",
        "deezer.com", "tidal.com", "music.amazon.com", "mixcloud.com", "vimeo.com", "twitch.tv",
    ]
}

public enum ShelfExpiry: String, Codable, Sendable, CaseIterable {
    case never, oneHour, oneDay, oneWeek

    public var displayName: String {
        switch self {
        case .never: "Never"
        case .oneHour: "After 1 hour"
        case .oneDay: "After 1 day"
        case .oneWeek: "After 1 week"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .oneHour: 3600
        case .oneDay: 86_400
        case .oneWeek: 604_800
        }
    }
}

public struct FileShelfSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var expiry = ShelfExpiry.oneDay
    public var maxItems = 30

    public init() {}
}

public struct FocusSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var workMinutes = 25.0
    public var shortBreakMinutes = 5.0
    public var longBreakMinutes = 15.0
    public var sessionsBeforeLongBreak = 4
    public var autoStartNextPhase = false
    public var showLiveActivity = true

    public init() {}
}

public enum SystemIndicator: String, Codable, Sendable, CaseIterable {
    case none, cpu, memory, network, battery

    public var displayName: String {
        switch self {
        case .none: "None"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .battery: "Battery"
        }
    }
}

public struct SystemMonitorSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    /// Seconds between samples while metrics are visible.
    public var sampleInterval = 2.0
    public var showCPU = true
    public var showMemory = true
    public var showNetwork = true
    public var showDisk = true
    public var showBattery = true
    /// Reads GPU utilisation from IORegistry statistics; unavailable on some hardware.
    public var showGPU = false
    /// Metric shown in the compact island. Anything but `.none` samples continuously.
    public var compactIndicator = SystemIndicator.none

    public init() {}

    public static let sampleIntervalRange = 1.0...10.0
}

public struct PrivacyIndicatorSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var showCamera = true
    public var showMicrophone = true
    /// Show a camera/microphone light in the compact island while either is in use.
    public var showLiveActivity = true

    public init() {}
}

public struct MirrorSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    /// Flip the preview horizontally, like a mirror.
    public var mirrorImage = true
    /// Start the camera as soon as the Mirror page opens. Off by default so the camera never
    /// turns on just because the island expanded.
    public var startAutomatically = false
    /// `AVCaptureDevice.uniqueID` of the preferred camera; `nil` uses the system default.
    public var cameraID: String?

    public init() {}
}

public enum EqualizerPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case flat, bassBoost, bassReducer, vocal, trebleBoost, loudness, spokenWord, custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Boost"
        case .bassReducer: "Bass Reducer"
        case .vocal: "Vocal"
        case .trebleBoost: "Treble Boost"
        case .loudness: "Loudness"
        case .spokenWord: "Spoken Word"
        case .custom: "Custom"
        }
    }

    /// Gains in dB for the six bands (60 Hz, 170 Hz, 500 Hz, 1.5 kHz, 4.5 kHz, 12 kHz).
    /// `custom` has none of its own; the user's custom gains are used instead.
    public var gains: [Double] {
        switch self {
        case .flat, .custom: [0, 0, 0, 0, 0, 0]
        case .bassBoost: [6, 4, 1, 0, 0, 0]
        case .bassReducer: [-6, -4, -1, 0, 0, 0]
        case .vocal: [-2, -1, 2, 4, 3, 0]
        case .trebleBoost: [0, 0, 0, 1, 4, 6]
        case .loudness: [5, 3, 0, -1, 2, 4]
        case .spokenWord: [-4, -2, 1, 4, 3, -1]
        }
    }
}

public struct SoundMixerSettings: Codable, Sendable, Equatable {
    public static let bandCount = 6
    public static let gainRange = -12.0...12.0
    public static let volumeRange = 0.0...1.5

    /// Off by default: per-app volume needs the System Audio Recording permission.
    public var isEnabled = false
    /// Volume per app bundle ID (1 = unchanged). Only changed apps are stored.
    public var appVolumes: [String: Double] = [:]
    public var mutedApps: [String] = []
    public var equalizerEnabled = false
    public var equalizerPreset = EqualizerPreset.flat
    public var customGains = [Double](repeating: 0, count: SoundMixerSettings.bandCount)

    public init() {}

    public var activeGains: [Double] {
        let gains = equalizerPreset == .custom ? customGains : equalizerPreset.gains
        return (0..<Self.bandCount).map { index in
            index < gains.count ? min(max(gains[index], Self.gainRange.lowerBound), Self.gainRange.upperBound) : 0
        }
    }

    /// True when the equaliser would change the sound at all.
    public var equalizerIsActive: Bool {
        equalizerEnabled && activeGains.contains { $0 != 0 }
    }

    public func volume(for bundleID: String) -> Double {
        mutedApps.contains(bundleID) ? 0 : min(max(appVolumes[bundleID] ?? 1, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
    }

    public mutating func setVolume(_ volume: Double, for bundleID: String) {
        let clamped = min(max(volume, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
        appVolumes[bundleID] = abs(clamped - 1) < 0.005 ? nil : clamped
    }

    public mutating func setMuted(_ muted: Bool, for bundleID: String) {
        mutedApps.removeAll { $0 == bundleID }
        if muted { mutedApps.append(bundleID) }
    }

    public mutating func resetApps() {
        appVolumes.removeAll()
        mutedApps.removeAll()
    }
}

public struct BluetoothSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    public var announceConnections = true
    public var lowBatteryAlerts = true

    public init() {}
}

public struct CaffeinateSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    /// Keep the system awake but let the display sleep.
    public var allowDisplaySleep = false
    public var showLiveActivity = true

    public init() {}
}

public struct DeveloperSettings: Codable, Sendable, Equatable {
    public var isEnabled = true
    /// Absolute paths of Git repositories the user chose to follow.
    public var repositories: [String] = []
    /// Accept events written by local hooks into the IslandBar events folder. Off by default:
    /// when on, any program running as you can put text on the island.
    public var eventInboxEnabled = false
    /// Running activities with no update for this long are treated as abandoned.
    public var staleActivityMinutes = 30.0
    public var showLiveActivity = true

    public init() {}
}

import AppKit
import CoreAudio
import IslandCore
import IslandDesign
import IslandPlatform
import Observation
import SwiftUI

/// Per-app volume and a system-wide equaliser, built on Core Audio process taps (macOS 14.2+).
@MainActor
@Observable
public final class SoundMixerModule: IslandModule {
    public let id = FeatureID.soundMixer
    public let displayName = "Sound"
    public let symbolName = "slider.vertical.3"

    /// Apps shown in the mixer.
    public private(set) var apps: [AudioAppGroup] = []
    public private(set) var settings = SoundMixerSettings()
    public private(set) var errorMessage: String?
    public let isSupported = AudioProcess.all() != nil

    @ObservationIgnored private let settingsStore: SettingsStore?
    @ObservationIgnored private var engine: MixerEngine?
    @ObservationIgnored private var allGroups: [AudioAppGroup] = []
    @ObservationIgnored private var lastPlayed: [String: Date] = [:]
    @ObservationIgnored private let systemListeners = CoreAudioListeners()
    @ObservationIgnored private let processListeners = CoreAudioListeners()
    @ObservationIgnored private var listenedProcesses: Set<AudioObjectID> = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var failedPlan: [MixerTap]?
    @ObservationIgnored private var isActive = false

    public init(settings: SettingsStore?) {
        self.settingsStore = settings
    }

    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: IslandModule

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.soundMixer.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        guard settings.soundMixer != self.settings else { return }
        self.settings = settings.soundMixer
        failedPlan = nil
        if isActive {
            apps = MixerPlanner.visible(allGroups, settings: self.settings, lastPlayed: lastPlayed, now: .now)
            updateEngine()
        }
    }

    public func activate() {
        guard isSupported else {
            errorMessage = MixerError.unsupported.message
            return
        }
        isActive = true
        engine = engine ?? MixerEngine()
        systemListeners.add(CoreAudioQuery.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.scheduleRefresh() }
        systemListeners.add(CoreAudioQuery.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.scheduleRefresh() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            })
        }
        refresh()
    }

    public func deactivate() {
        isActive = false
        refreshTask?.cancel()
        systemListeners.removeAll()
        processListeners.removeAll()
        listenedProcesses.removeAll()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        // Tearing down unmutes every tapped app immediately.
        engine?.teardown()
        apps = []
        allGroups = []
    }

    public func makeExpandedView() -> AnyView { AnyView(SoundMixerView(module: self)) }

    // MARK: Controls

    public func volume(for app: AudioAppGroup) -> Double {
        settings.volume(for: app.id)
    }

    public func isMuted(_ app: AudioAppGroup) -> Bool {
        settings.mutedApps.contains(app.id)
    }

    public func setVolume(_ volume: Double, for app: AudioAppGroup) {
        settingsStore?.update { settings in
            settings.soundMixer.setMuted(false, for: app.id)
            settings.soundMixer.setVolume(volume, for: app.id)
        }
    }

    public func toggleMute(_ app: AudioAppGroup) {
        let muted = isMuted(app)
        settingsStore?.update { $0.soundMixer.setMuted(!muted, for: app.id) }
    }

    public func setEqualizerEnabled(_ enabled: Bool) {
        settingsStore?.update { $0.soundMixer.equalizerEnabled = enabled }
    }

    public func selectPreset(_ preset: EqualizerPreset) {
        settingsStore?.update { settings in
            if preset == .custom, settings.soundMixer.equalizerPreset != .custom {
                settings.soundMixer.customGains = settings.soundMixer.activeGains
            }
            settings.soundMixer.equalizerPreset = preset
            settings.soundMixer.equalizerEnabled = true
        }
    }

    /// Editing a band switches to the custom preset, starting from the current curve.
    public func setGain(_ gain: Double, band: Int) {
        settingsStore?.update { settings in
            if settings.soundMixer.equalizerPreset != .custom {
                settings.soundMixer.customGains = settings.soundMixer.activeGains
                settings.soundMixer.equalizerPreset = .custom
            }
            guard band < settings.soundMixer.customGains.count else { return }
            settings.soundMixer.customGains[band] = min(max(gain, SoundMixerSettings.gainRange.lowerBound), SoundMixerSettings.gainRange.upperBound)
            settings.soundMixer.equalizerEnabled = true
        }
    }

    public func resetApps() {
        settingsStore?.update { $0.soundMixer.resetApps() }
    }

    // MARK: Refresh

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        guard isActive else { return }
        let processes = AudioProcess.all() ?? []
        let regularApps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppInfo? in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return RunningAppInfo(bundleID: bundleID, name: name)
        }
        allGroups = MixerPlanner.groups(processes: processes, regularApps: regularApps, ownPID: ProcessInfo.processInfo.processIdentifier)
        let now = Date.now
        for group in allGroups where group.isPlaying {
            lastPlayed[group.id] = now
        }
        apps = MixerPlanner.visible(allGroups, settings: settings, lastPlayed: lastPlayed, now: now)
        listenToProcesses(Set(processes.map(\.objectID)))
        updateEngine()
    }

    /// Playback starting or stopping in a process changes its "running output" property.
    private func listenToProcesses(_ objects: Set<AudioObjectID>) {
        guard objects != listenedProcesses else { return }
        processListeners.removeAll()
        for object in objects {
            processListeners.add(object, kAudioProcessPropertyIsRunningOutput) { [weak self] in self?.scheduleRefresh() }
        }
        listenedProcesses = objects
    }

    private func updateEngine() {
        guard isActive, let engine else { return }
        let plan = MixerPlanner.taps(groups: allGroups, settings: settings, ownProcess: MixerEngine.ownProcessObject())
        // After a refusal, wait for a settings change instead of retrying on every refresh.
        if let failedPlan, failedPlan.map(\.source) == plan.map(\.source) { return }
        do {
            try engine.update(taps: plan, equalizerGains: settings.equalizerIsActive ? settings.activeGains : nil)
            errorMessage = nil
            failedPlan = nil
        } catch {
            errorMessage = error.message
            failedPlan = plan
        }
    }
}

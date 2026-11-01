import Foundation
import IslandCore
import IslandDesign
import Observation
import SwiftUI

@MainActor
@Observable
public final class SystemMonitorModule: IslandModule {
    public let id = FeatureID.systemMonitor
    public let displayName = "System"
    public let symbolName = "gauge.with.dots.needle.33percent"

    public private(set) var snapshot: SystemSnapshot?
    /// Recent values for sparklines (oldest first).
    public private(set) var cpuHistory: [Double] = []
    public private(set) var networkHistory: [Double] = []
    static let historyLength = 40
    public private(set) var settings = SystemMonitorSettings()
    public let hardware = SystemSampler.hardwareInfo()

    @ObservationIgnored private let sampler = SystemSampler()
    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var visibleViews = 0
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var lastBatteryPercent: Int?

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        settings.compactIndicator == .none || snapshot == nil ? nil : LiveActivityPriority.systemIndicator
    }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.systemMonitor.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        guard settings.systemMonitor != self.settings else { return }
        self.settings = settings.systemMonitor
        if isActive { updateSampling(restart: true) }
    }

    public func activate() {
        isActive = true
        updateSampling(restart: false)
    }

    public func deactivate() {
        isActive = false
        stopSampling()
        snapshot = nil
    }

    public func makeCompactLeading() -> AnyView { AnyView(SystemCompactLeading(module: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(SystemCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(SystemExpandedView(module: self)) }

    // MARK: Demand-driven sampling

    /// Expanded views call these so metrics are only sampled while someone can see them.
    func viewAppeared() {
        visibleViews += 1
        updateSampling(restart: false)
    }

    func viewDisappeared() {
        visibleViews = max(visibleViews - 1, 0)
        updateSampling(restart: false)
    }

    private var needsSampling: Bool {
        isActive && (visibleViews > 0 || settings.compactIndicator != .none)
    }

    private var selection: MetricSelection {
        var selection = MetricSelection()
        let indicator = settings.compactIndicator
        selection.cpu = settings.showCPU || indicator == .cpu
        selection.memory = settings.showMemory || indicator == .memory
        selection.network = settings.showNetwork || indicator == .network
        selection.battery = settings.showBattery || indicator == .battery
        selection.disk = settings.showDisk && visibleViews > 0
        selection.gpu = settings.showGPU && visibleViews > 0
        return selection
    }

    private func updateSampling(restart: Bool) {
        guard needsSampling else {
            stopSampling()
            return
        }
        if restart { stopSampling() }
        guard samplingTask == nil else { return }

        let interval = min(max(settings.sampleInterval, SystemMonitorSettings.sampleIntervalRange.lowerBound),
                           SystemMonitorSettings.sampleIntervalRange.upperBound)
        samplingTask = Task { [weak self, sampler] in
            await sampler.resetDeltas()
            // Rates need two readings; take a quick first pair so values appear immediately.
            if let selection = self?.selection {
                _ = await sampler.sample(selection)
                try? await Task.sleep(for: .milliseconds(350))
            }
            while !Task.isCancelled {
                guard let selection = self?.selection else { return }
                let snapshot = await sampler.sample(selection)
                guard !Task.isCancelled else { return }
                self?.received(snapshot)
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
            }
        }
    }

    static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLength {
            history.removeFirst(history.count - historyLength)
        }
    }

    private func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func received(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        if let cpu = snapshot.cpuUsage { Self.append(cpu, to: &cpuHistory) }
        if let incoming = snapshot.networkIn { Self.append(incoming + (snapshot.networkOut ?? 0), to: &networkHistory) }
        guard let battery = snapshot.battery else { return }
        if !battery.isOnACPower,
           let threshold = MetricMath.crossedThreshold(previous: lastBatteryPercent, current: battery.percent) {
            activity.post(ActivityEvent(
                source: .system, style: .warning, title: "Battery at \(threshold)%",
                subtitle: battery.minutesRemaining.map { "About \($0) minutes remaining" },
                symbolName: "battery.25percent"
            ))
        }
        lastBatteryPercent = battery.percent
    }
}

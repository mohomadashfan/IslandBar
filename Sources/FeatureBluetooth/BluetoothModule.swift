import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI

/// Announces Bluetooth audio and input devices connecting and disconnecting, and low batteries.
@MainActor
@Observable
public final class BluetoothModule: IslandModule {
    public let id = FeatureID.bluetooth
    public let displayName = "Devices"
    public let symbolName = "dot.radiowaves.left.and.right"

    public private(set) var devices: [BluetoothDevice] = []
    public private(set) var settings = BluetoothSettings()

    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private let hid = BluetoothHIDMonitor()
    @ObservationIgnored private let audio = BluetoothAudioMonitor()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Devices reconnect in a burst at launch and after wake; those are not news.
    @ObservationIgnored private var quietUntil = Date.distantPast
    @ObservationIgnored private var isActive = false

    static let quietPeriod: TimeInterval = 10
    static let batteryRefreshInterval: Duration = .seconds(300)

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    // MARK: IslandModule

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.bluetooth.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        self.settings = settings.bluetooth
    }

    public func activate() {
        isActive = true
        quietUntil = Date.now.addingTimeInterval(Self.quietPeriod)
        hid.onChange = { [weak self] in self?.scheduleRefresh() }
        audio.onChange = { [weak self] in self?.scheduleRefresh() }
        hid.start()
        audio.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.quietUntil = Date.now.addingTimeInterval(Self.quietPeriod)
                self?.scheduleRefresh()
            }
        }
        refresh()
        startBatteryRefresh()
    }

    public func deactivate() {
        isActive = false
        hid.stop()
        audio.stop()
        refreshTask?.cancel()
        batteryTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        devices = []
    }

    public func makeExpandedView() -> AnyView { AnyView(BluetoothExpandedView(module: self)) }

    func refresh() {
        guard isActive else { return }
        let current = BluetoothLogic.merged(BluetoothHIDMonitor.scan() + BluetoothAudioMonitor.scan())
        let previous = devices
        devices = current
        announce(from: previous, to: current)
    }

    // MARK: Private

    /// Device registration arrives in bursts; settle before reading.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func startBatteryRefresh() {
        batteryTask?.cancel()
        batteryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.batteryRefreshInterval)
                guard !Task.isCancelled, let self else { return }
                if self.devices.contains(where: { $0.batteryPercent != nil }) {
                    self.refresh()
                }
            }
        }
    }

    private func announce(from previous: [BluetoothDevice], to current: [BluetoothDevice]) {
        let quiet = Date.now < quietUntil
        if settings.announceConnections, !quiet {
            let changes = BluetoothLogic.changes(from: previous, to: current)
            for device in changes.connected {
                activity.post(ActivityEvent(
                    source: .devices, style: .success, title: "\(device.name) connected",
                    subtitle: device.batteryPercent.map { "Battery \($0)%" } ?? device.kind.displayName,
                    symbolName: device.symbolName
                ))
            }
            for device in changes.disconnected {
                activity.post(ActivityEvent(
                    source: .devices, title: "\(device.name) disconnected", subtitle: device.kind.displayName,
                    symbolName: device.symbolName
                ))
            }
        }
        guard settings.lowBatteryAlerts else { return }
        for device in current {
            let before = previous.first { $0.id == device.id }?.batteryPercent
            if let threshold = BluetoothLogic.lowBatteryThreshold(previous: before, current: device.batteryPercent) {
                activity.post(ActivityEvent(
                    source: .devices, style: .warning, title: "\(device.name) battery low",
                    subtitle: "\(threshold)% remaining", symbolName: "battery.25percent"
                ))
            }
        }
    }
}

struct BluetoothExpandedView: View {
    let module: BluetoothModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if module.devices.isEmpty {
            IslandEmptyState(
                symbol: "dot.radiowaves.left.and.right",
                title: "No Bluetooth devices",
                message: "Connected headphones, speakers, keyboards, mice and trackpads appear here."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(module.devices) { device in
                        DeviceTile(device: device)
                    }
                }
            }
            .onAppear { module.refresh() }
        }
    }
}

private struct DeviceTile: View {
    let device: BluetoothDevice
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.primary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                if let battery = device.batteryPercent {
                    HStack(spacing: 6) {
                        MeterBar(value: Double(battery) / 100, color: battery <= 20 ? .orange : .green)
                            .frame(width: 44)
                        Text("\(battery)%")
                            .font(theme.monospacedDigits(10))
                            .foregroundStyle(theme.secondary)
                    }
                } else {
                    Text(device.kind.displayName)
                        .font(theme.font(10))
                        .foregroundStyle(theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .islandCard()
        .accessibilityElement(children: .combine)
    }
}

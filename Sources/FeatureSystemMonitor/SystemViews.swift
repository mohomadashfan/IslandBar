import IslandCore
import IslandDesign
import SwiftUI

enum MetricFormat {
    static func percent(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    static func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "–"
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "–" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: Int64(value)) + "/s"
    }

    static func batterySymbol(_ battery: BatteryStatus) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        return switch battery.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

extension SystemMonitorModule {
    var indicatorSymbol: String {
        switch settings.compactIndicator {
        case .none: "gauge"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .battery: snapshot?.battery.map(MetricFormat.batterySymbol) ?? "battery.100percent"
        }
    }

    var indicatorValue: String {
        guard let snapshot else { return "–" }
        return switch settings.compactIndicator {
        case .none: ""
        case .cpu: MetricFormat.percent(snapshot.cpuUsage)
        case .memory: MetricFormat.percent(snapshot.memoryUsed.map { Double($0) / Double(max(snapshot.memoryTotal, 1)) })
        case .network: MetricFormat.rate(snapshot.networkIn)
        case .battery: snapshot.battery.map { "\($0.percent)%" } ?? "–"
        }
    }
}

struct SystemCompactLeading: View {
    let module: SystemMonitorModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Image(systemName: module.indicatorSymbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.secondary)
    }
}

struct SystemCompactTrailing: View {
    let module: SystemMonitorModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Text(module.indicatorValue)
            .font(theme.monospacedDigits(11, weight: .semibold))
            .foregroundStyle(theme.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct SystemExpandedView: View {
    let module: SystemMonitorModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                tiles
            }

        }
        .onAppear { module.viewAppeared() }
        .onDisappear { module.viewDisappeared() }
    }

    @ViewBuilder
    private var tiles: some View {
        let snapshot = module.snapshot
        let settings = module.settings
        if settings.showCPU {
            MetricTile(symbol: "cpu", title: "CPU", value: MetricFormat.percent(snapshot?.cpuUsage), fraction: nil,
                       history: module.cpuHistory, historyMax: 1)
        }
        if settings.showMemory {
            let fraction = snapshot?.memoryUsed.map { Double($0) / Double(max(snapshot?.memoryTotal ?? 1, 1)) }
            MetricTile(symbol: "memorychip", title: "Memory",
                       value: "\(MetricFormat.bytes(snapshot?.memoryUsed)) of \(MetricFormat.bytes(snapshot?.memoryTotal))",
                       fraction: fraction)
        }
        if settings.showNetwork {
            MetricTile(symbol: "arrow.up.arrow.down", title: "Network",
                       value: "↓ \(MetricFormat.rate(snapshot?.networkIn))  ↑ \(MetricFormat.rate(snapshot?.networkOut))",
                       fraction: nil, history: module.networkHistory)
        }
        if settings.showDisk {
            let fraction: Double? = {
                guard let available = snapshot?.diskAvailable, let total = snapshot?.diskTotal, total > 0 else { return nil }
                return 1 - Double(available) / Double(total)
            }()
            MetricTile(symbol: "internaldrive", title: "Disk",
                       value: snapshot?.diskAvailable.map { "\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) free" } ?? "–",
                       fraction: fraction)
        }
        if settings.showBattery, let battery = snapshot?.battery {
            MetricTile(symbol: MetricFormat.batterySymbol(battery), title: battery.isCharging ? "Charging" : (battery.isOnACPower ? "On Power" : "Battery"),
                       value: "\(battery.percent)%" + (battery.minutesRemaining.map { " · \($0 / 60)h \($0 % 60)m" } ?? ""),
                       fraction: Double(battery.percent) / 100)
        }
        if settings.showGPU {
            MetricTile(symbol: "cube.transparent", title: "GPU",
                       value: snapshot?.gpuUsage == nil ? "Unavailable" : MetricFormat.percent(snapshot?.gpuUsage),
                       fraction: snapshot?.gpuUsage)
        }
    }
}

private struct MetricTile: View {
    let symbol: String
    let title: String
    let value: String
    let fraction: Double?
    var history: [Double]? = nil
    var historyMax: Double? = nil

    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondary)
            Text(value)
                .font(theme.monospacedDigits(12, weight: .semibold))
                .foregroundStyle(theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if history == nil, let fraction {
                MeterBar(value: fraction, color: fraction > 0.85 ? .orange : nil)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68, alignment: .leading)
        .background(alignment: .bottom) {
            if let history {
                Sparkline(values: history, maxValue: historyMax)
                    .frame(height: 22)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .islandCard()
        .accessibilityElement(children: .combine)
    }
}

import Foundation

public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct BatteryStatus: Sendable, Equatable {
    public var percent: Int
    public var isCharging: Bool
    public var isOnACPower: Bool
    /// Minutes to empty, when macOS has an estimate.
    public var minutesRemaining: Int?

    public init(percent: Int, isCharging: Bool, isOnACPower: Bool, minutesRemaining: Int?) {
        self.percent = percent
        self.isCharging = isCharging
        self.isOnACPower = isOnACPower
        self.minutesRemaining = minutesRemaining
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    /// 0...1, `nil` for the very first sample (a delta is needed).
    public var cpuUsage: Double?
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64
    /// Bytes per second, `nil` until two samples exist.
    public var networkIn: Double?
    public var networkOut: Double?
    public var diskAvailable: Int64?
    public var diskTotal: Int64?
    public var battery: BatteryStatus?
    /// 0...1 when available and enabled.
    public var gpuUsage: Double?
    public var date: Date

    public init(date: Date = .now, memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.date = date
        self.memoryTotal = memoryTotal
    }
}

public struct HardwareInfo: Sendable, Equatable {
    public var model: String
    public var chip: String
    public var performanceCores: Int?
    public var efficiencyCores: Int?
    public var logicalCores: Int
    public var memory: UInt64
    public var osVersion: String

    public var summary: String {
        var parts = [model, chip]
        if let p = performanceCores, let e = efficiencyCores {
            parts.append("\(p)P + \(e)E cores")
        } else {
            parts.append("\(logicalCores) cores")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
        parts.append(osVersion)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Pure calculations, separated from the system calls so they can be tested.
public enum MetricMath {
    /// Fraction of non-idle ticks between two samples.
    public static func cpuUsage(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        let busy = delta(previous.user, current.user) + delta(previous.system, current.system) + delta(previous.nice, current.nice)
        let total = busy + delta(previous.idle, current.idle)
        guard total > 0 else { return nil }
        return min(max(Double(busy) / Double(total), 0), 1)
    }

    /// Difference between two monotonically increasing counters. If the counter went backwards
    /// (wrapped or reset, e.g. an interface was re-created) the new value is the best estimate.
    public static func delta(_ previous: UInt64, _ current: UInt64) -> UInt64 {
        current >= previous ? current - previous : current
    }

    public static func rate(bytes: UInt64, over interval: TimeInterval) -> Double? {
        guard interval > 0 else { return nil }
        return Double(bytes) / interval
    }

    /// Battery thresholds that were crossed going down, for low-battery activity.
    public static func crossedThreshold(previous: Int?, current: Int, thresholds: [Int] = [20, 10, 5]) -> Int? {
        guard let previous else { return nil }
        return thresholds.first { previous > $0 && current <= $0 }
    }
}

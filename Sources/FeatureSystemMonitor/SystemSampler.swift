import Darwin
import Foundation
import IOKit
import IOKit.ps

public struct MetricSelection: Sendable, Equatable {
    public var cpu = true
    public var memory = true
    public var network = true
    public var disk = true
    public var battery = true
    public var gpu = false

    public init() {}
}

/// Reads system statistics through public interfaces only: Mach host statistics, sysctl,
/// URL resource values and IOKit power sources/registry. Runs off the main actor.
actor SystemSampler {
    private let host = mach_host_self()
    private var previousTicks: CPUTicks?
    private var previousNetwork: (inBytes: UInt64, outBytes: UInt64, date: Date)?

    func sample(_ selection: MetricSelection) -> SystemSnapshot {
        let now = Date.now
        var snapshot = SystemSnapshot(date: now)

        if selection.cpu, let ticks = cpuTicks() {
            if let previousTicks {
                snapshot.cpuUsage = MetricMath.cpuUsage(from: previousTicks, to: ticks)
            }
            previousTicks = ticks
        }
        if selection.memory {
            snapshot.memoryUsed = memoryUsed()
        }
        if selection.network, let counters = Self.networkCounters() {
            if let previous = previousNetwork {
                let interval = now.timeIntervalSince(previous.date)
                snapshot.networkIn = MetricMath.rate(bytes: MetricMath.delta(previous.inBytes, counters.inBytes), over: interval)
                snapshot.networkOut = MetricMath.rate(bytes: MetricMath.delta(previous.outBytes, counters.outBytes), over: interval)
            }
            previousNetwork = (counters.inBytes, counters.outBytes, now)
        }
        if selection.disk {
            let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
            ])
            snapshot.diskAvailable = values?.volumeAvailableCapacityForImportantUsage
            snapshot.diskTotal = values?.volumeTotalCapacity.map(Int64.init)
        }
        if selection.battery {
            snapshot.battery = Self.battery()
        }
        if selection.gpu {
            snapshot.gpuUsage = Self.gpuUtilization()
        }
        return snapshot
    }

    /// Forget deltas, e.g. after sampling was paused, so the next rate is not averaged over the gap.
    func resetDeltas() {
        previousTicks = nil
        previousNetwork = nil
    }

    // MARK: CPU and memory

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(getpagesize())
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * pageSize
    }

    // MARK: Network

    /// Sums 64-bit byte counters of physical interfaces (`en*`) from the routing sysctl.
    private static func networkCounters() -> (inBytes: UInt64, outBytes: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = Self.string(fromCString: nameBuffer)
                        if name.hasPrefix("en") {
                            inBytes &+= message.ifm_data.ifi_ibytes
                            outBytes &+= message.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (inBytes, outBytes)
    }

    // MARK: Power

    private static func battery() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            return BatteryStatus(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isOnACPower: (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                minutesRemaining: minutes.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return nil
    }

    /// Reads the "Device Utilization %" statistic that GPU drivers publish in the IORegistry.
    /// Not every GPU/driver publishes it; `nil` means unavailable.
    private static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let utilization = property["Device Utilization %"] as? Int
            else { continue }
            best = max(best ?? 0, Double(utilization) / 100)
        }
        return best
    }

    // MARK: Hardware

    static func hardwareInfo() -> HardwareInfo {
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        return HardwareInfo(
            model: sysctlString("hw.model") ?? "Mac",
            chip: sysctlString("machdep.cpu.brand_string") ?? "",
            performanceCores: sysctlInt("hw.perflevel0.physicalcpu"),
            efficiencyCores: sysctlInt("hw.perflevel1.physicalcpu"),
            logicalCores: process.activeProcessorCount,
            memory: process.physicalMemory,
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion)"
                + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return string(fromCString: buffer)
    }

    private static func string(fromCString buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

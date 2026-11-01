import Foundation

public enum BluetoothDeviceKind: String, Sendable, Equatable {
    case headphones, speaker, keyboard, mouse, trackpad, gameController, other

    public var displayName: String {
        switch self {
        case .headphones: "Headphones"
        case .speaker: "Speaker"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        case .trackpad: "Trackpad"
        case .gameController: "Game Controller"
        case .other: "Accessory"
        }
    }
}

public struct BluetoothDevice: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var kind: BluetoothDeviceKind
    /// 0–100 when the device reports it (Apple keyboards, mice and trackpads do).
    public var batteryPercent: Int?

    public init(id: String, name: String, kind: BluetoothDeviceKind, batteryPercent: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.batteryPercent = batteryPercent
    }

    public var symbolName: String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        return switch kind {
        case .headphones: "headphones"
        case .speaker: "hifispeaker"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gameController: "gamecontroller"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

/// Pure logic for interpreting device lists.
public enum BluetoothLogic {
    public struct Changes: Equatable {
        public var connected: [BluetoothDevice] = []
        public var disconnected: [BluetoothDevice] = []
    }

    public static func changes(from old: [BluetoothDevice], to new: [BluetoothDevice]) -> Changes {
        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        return Changes(
            connected: new.filter { !oldIDs.contains($0.id) },
            disconnected: old.filter { !newIDs.contains($0.id) }
        )
    }

    /// Battery thresholds crossed going down since the last reading.
    public static func lowBatteryThreshold(previous: Int?, current: Int?, thresholds: [Int] = [20, 10, 5]) -> Int? {
        guard let previous, let current else { return nil }
        return thresholds.first { previous > $0 && current <= $0 }
    }

    /// Classifies a HID device from its usage page/usage and name.
    public static func hidKind(usagePage: Int?, usage: Int?, name: String) -> BluetoothDeviceKind {
        if name.lowercased().contains("trackpad") { return .trackpad }
        switch (usagePage, usage) {
        case (1, 6): return .keyboard
        case (1, 2): return .mouse
        case (1, 4), (1, 5): return .gameController
        case (13, _): return .trackpad
        default: return .other
        }
    }

    /// One HID device usually publishes several IOHIDDevice entries (one per interface).
    public static func merged(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        var result: [BluetoothDevice] = []
        for device in devices {
            if let index = result.firstIndex(where: { $0.id == device.id }) {
                if result[index].batteryPercent == nil { result[index].batteryPercent = device.batteryPercent }
                if result[index].kind == .other { result[index].kind = device.kind }
            } else {
                result.append(device)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

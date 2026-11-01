import CoreAudio
import Foundation
import IOKit
import IOKit.hid
import IslandPlatform

/// Bluetooth input devices (keyboards, mice, trackpads, controllers), read from the IORegistry.
///
/// Uses IOKit service matching notifications. Unlike IOBluetooth or IOHIDManager, this needs no
/// Bluetooth or Input Monitoring permission: it only reads device descriptions.
@MainActor
final class BluetoothHIDMonitor {
    var onChange: (() -> Void)?

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            BluetoothHIDMonitor.drain(iterator)
            guard let refcon else { return }
            // The notification port is scheduled on the main queue.
            MainActor.assumeIsolated {
                Unmanaged<BluetoothHIDMonitor>.fromOpaque(refcon).takeUnretainedValue().onChange?()
            }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, type, IOServiceMatching(kIOHIDDeviceKey), callback, refcon, &iterator) == KERN_SUCCESS {
                // Draining arms the notification.
                Self.drain(iterator)
                iterators.append(iterator)
            }
        }
    }

    func stop() {
        for iterator in iterators {
            IOObjectRelease(iterator)
        }
        iterators.removeAll()
        if let port {
            IONotificationPortDestroy(port)
        }
        port = nil
    }

    nonisolated private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    /// Currently connected Bluetooth HID devices.
    nonisolated static func scan() -> [BluetoothDevice] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [BluetoothDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let transport = string(service, kIOHIDTransportKey), transport.localizedCaseInsensitiveContains("bluetooth"),
                  let name = string(service, kIOHIDProductKey), !name.isEmpty
            else { continue }
            let vendor = int(service, kIOHIDVendorIDKey) ?? 0
            let product = int(service, kIOHIDProductIDKey) ?? 0
            let identity = string(service, kIOHIDSerialNumberKey) ?? string(service, "DeviceAddress") ?? "\(vendor):\(product)"
            devices.append(BluetoothDevice(
                id: "hid|\(name)|\(identity)",
                name: name,
                kind: BluetoothLogic.hidKind(
                    usagePage: int(service, kIOHIDPrimaryUsagePageKey),
                    usage: int(service, kIOHIDPrimaryUsageKey),
                    name: name
                ),
                batteryPercent: battery(service)
            ))
        }
        return BluetoothLogic.merged(devices)
    }

    /// Apple peripherals publish "BatteryPercent" on the device or a child service.
    nonisolated private static func battery(_ service: io_service_t) -> Int? {
        guard let value = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "BatteryPercent" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) as? Int, (0...100).contains(value) else { return nil }
        return value
    }

    nonisolated private static func string(_ service: io_service_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    nonisolated private static func int(_ service: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
}

/// Bluetooth headphones and speakers, from CoreAudio's device list. Needs no permission.
@MainActor
final class BluetoothAudioMonitor {
    var onChange: (() -> Void)?
    private let listeners = CoreAudioListeners()

    func start() {
        guard listeners.isEmpty else { return }
        listeners.add(CoreAudioQuery.system, kAudioHardwarePropertyDevices) { [weak self] in self?.onChange?() }
    }

    func stop() {
        listeners.removeAll()
    }

    nonisolated static func scan() -> [BluetoothDevice] {
        let bluetoothTransports: Set<UInt32> = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
        let devices = CoreAudioQuery.devices().compactMap { device -> BluetoothDevice? in
            guard let transport = CoreAudioQuery.uint32(device, kAudioDevicePropertyTransportType),
                  bluetoothTransports.contains(transport),
                  let name = CoreAudioQuery.string(device, kAudioObjectPropertyName)
            else { return nil }
            let hasOutput = CoreAudioQuery.streamCount(device, scope: kAudioObjectPropertyScopeOutput) > 0
            let hasInput = CoreAudioQuery.hasInputStreams(device)
            // A headset can appear as separate input and output devices; key on the name so
            // it is reported once.
            return BluetoothDevice(
                id: "audio|\(name)",
                name: name,
                kind: hasOutput && !hasInput && name.lowercased().contains("speaker") ? .speaker : .headphones
            )
        }
        return BluetoothLogic.merged(devices)
    }
}

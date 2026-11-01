import CoreAudio
import CoreMediaIO
import Foundation
import IslandPlatform

// MARK: - CoreAudio

/// Watches microphone use through CoreAudio property listeners: no polling and no permission.
///
/// On macOS 14.2+ it reads each client process's "is running input" state, which identifies the
/// app. Earlier systems only expose whether an input device is running at all.
@MainActor
final class AudioInputMonitor {
    var onChange: (() -> Void)?

    private typealias Registration = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)
    private var systemRegistrations: [Registration] = []
    private var objectRegistrations: [Registration] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)

    func start() {
        guard systemRegistrations.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyProcessObjectList] {
            if let registration = listen(system, selector, rebuild: true) {
                systemRegistrations.append(registration)
            }
        }
        rebuildObjectListeners()
    }

    func stop() {
        for registration in systemRegistrations + objectRegistrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
        systemRegistrations.removeAll()
        objectRegistrations.removeAll()
    }

    /// Per-process state, or `nil` when the system does not provide it.
    func clients() -> [AudioClient]? {
        AudioProcess.all()?.map { AudioClient(pid: $0.pid, bundleID: $0.bundleID, isRunningInput: $0.isRunningInput) }
    }

    /// Fallback: any device with input streams that is running. Devices that also play audio
    /// can make this report the microphone while only the speakers are in use.
    func anyInputDeviceRunning() -> Bool {
        inputDevices().contains { CoreAudioQuery.uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 }
    }

    private func inputDevices() -> [AudioObjectID] {
        (CoreAudioQuery.objectIDs(system, kAudioHardwarePropertyDevices) ?? []).filter(CoreAudioQuery.hasInputStreams)
    }

    private func rebuildObjectListeners() {
        for registration in objectRegistrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
        objectRegistrations.removeAll()

        for device in inputDevices() {
            if let registration = listen(device, kAudioDevicePropertyDeviceIsRunningSomewhere, rebuild: false) {
                objectRegistrations.append(registration)
            }
        }
        for process in CoreAudioQuery.objectIDs(system, kAudioHardwarePropertyProcessObjectList) ?? [] {
            if let registration = listen(process, kAudioProcessPropertyIsRunningInput, rebuild: false) {
                objectRegistrations.append(registration)
            }
        }
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, rebuild: Bool) -> Registration? {
        var address = CoreAudioQuery.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if rebuild { self.rebuildObjectListeners() }
                self.onChange?()
            }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
        return (object, address, block)
    }
}

// MARK: - CoreMediaIO

/// Watches whether any camera is running, through CoreMediaIO listeners. Needs no permission.
/// macOS does not expose which app is using a camera.
@MainActor
final class CameraMonitor {
    var onChange: (() -> Void)?

    private typealias Registration = (object: CMIOObjectID, address: CMIOObjectPropertyAddress, block: CMIOObjectPropertyListenerBlock)
    private var systemRegistration: Registration?
    private var deviceRegistrations: [Registration] = []
    private let system = CMIOObjectID(kCMIOObjectSystemObject)

    func start() {
        guard systemRegistration == nil else { return }
        systemRegistration = listen(system, CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), rebuild: true)
        rebuildDeviceListeners()
    }

    func stop() {
        for registration in deviceRegistrations + [systemRegistration].compactMap({ $0 }) {
            var address = registration.address
            CMIOObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
        deviceRegistrations.removeAll()
        systemRegistration = nil
    }

    /// Names of the cameras currently running.
    func activeCameraNames() -> [String] {
        devices().compactMap { device in
            isRunning(device) ? (name(of: device) ?? "Camera") : nil
        }
    }

    private func devices() -> [CMIOObjectID] {
        var address = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = Self.address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr else { return false }
        return value != 0
    }

    private func name(of device: CMIOObjectID) -> String? {
        var address = Self.address(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func rebuildDeviceListeners() {
        for registration in deviceRegistrations {
            var address = registration.address
            CMIOObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
        deviceRegistrations = devices().compactMap {
            listen($0, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), rebuild: false)
        }
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private func listen(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector, rebuild: Bool) -> Registration? {
        var address = Self.address(selector)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if rebuild { self.rebuildDeviceListeners() }
                self.onChange?()
            }
        }
        guard CMIOObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
        return (object, address, block)
    }
}

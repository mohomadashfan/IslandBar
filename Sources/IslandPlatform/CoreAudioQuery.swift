import CoreAudio
import Foundation

/// Thin, typed wrappers over the CoreAudio property API.
public enum CoreAudioQuery {
    public static let system = AudioObjectID(kAudioObjectSystemObject)

    public static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func objectIDs(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID]? {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids
    }

    public static func objectID(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = address(selector)
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              value != kAudioObjectUnknown else { return nil }
        return value
    }

    public static func uint32(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    public static func float64(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float64? {
        var address = address(selector)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    public static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    public static func pid(_ process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    public static func streamCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        objectIDs(device, kAudioDevicePropertyStreams, scope: scope)?.count ?? 0
    }

    public static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        streamCount(device, scope: kAudioObjectPropertyScopeInput) > 0
    }

    public static func devices() -> [AudioObjectID] {
        objectIDs(system, kAudioHardwarePropertyDevices) ?? []
    }

    public static func defaultOutputDevice() -> AudioObjectID? {
        objectID(system, kAudioHardwarePropertyDefaultOutputDevice)
    }
}

/// Registers CoreAudio property listeners on the main queue and removes them all on `removeAll()`.
@MainActor
public final class CoreAudioListeners {
    private var registrations: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    public init() {}

    @discardableResult
    public func add(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        handler: @escaping @MainActor () -> Void
    ) -> Bool {
        var address = CoreAudioQuery.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return false }
        registrations.append((object, address, block))
        return true
    }

    public func removeAll() {
        for registration in registrations {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
        registrations.removeAll()
    }

    public var isEmpty: Bool { registrations.isEmpty }
}

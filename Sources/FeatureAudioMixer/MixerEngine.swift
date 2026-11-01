import CoreAudio
import Foundation
import IslandAudioDSP
import IslandPlatform

/// One tap in the mix: either a specific app's processes, or "everything else".
struct MixerTap: Equatable {
    enum Source: Equatable {
        /// These processes only (an app and its helpers).
        case processes([AudioObjectID])
        /// Every process except these. Must always exclude IslandBar itself.
        case everythingExcept([AudioObjectID])
    }

    var id: String
    var source: Source
    var gain: Float
}

enum MixerError: Error, Equatable {
    case unsupported
    case noOutputDevice
    case tapFailed(OSStatus)
    case aggregateFailed(OSStatus)
    case ioFailed(OSStatus)

    var message: String {
        switch self {
        case .unsupported:
            "Per-app volume needs macOS 14.2 or later."
        case .noOutputDevice:
            "No audio output device is available."
        case .tapFailed:
            "macOS did not allow IslandBar to capture app audio. Allow IslandBar under System Settings › Privacy & Security › Screen & System Audio Recording › System Audio Recording Only."
        case .aggregateFailed(let status), .ioFailed(let status):
            "The audio engine could not start (error \(status))."
        }
    }
}

/// Builds and runs the Core Audio graph behind per-app volume and the equaliser.
///
/// For every adjusted app a private process tap is created with "muted when tapped", so the app's
/// own output is silenced while IslandBar plays a processed copy. All taps feed one private
/// aggregate device whose main sub-device is the current output device; the C mixer applies gains
/// and the equaliser on the real-time thread. Private taps and aggregates disappear automatically
/// if IslandBar quits or crashes, which restores normal audio.
@MainActor
final class MixerEngine {
    private let mixer: OpaquePointer
    private var tapIDs: [AudioObjectID] = []
    private var builtSources: [MixerTap.Source] = []
    private var builtOutputUID: String?
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private(set) var sampleRate: Double = 48_000

    init?() {
        guard let mixer = ib_mixer_create() else { return nil }
        self.mixer = mixer
    }

    var isRunning: Bool { procID != nil }

    /// Applies a mix. Rebuilds the graph only when the set of taps or the output device changed;
    /// gain and equaliser changes are published to the running mixer without interruption.
    func update(taps: [MixerTap], equalizerGains: [Double]?) throws(MixerError) {
        if taps.isEmpty {
            teardown()
            return
        }
        guard let output = CoreAudioQuery.defaultOutputDevice(),
              let outputUID = CoreAudioQuery.string(output, kAudioDevicePropertyDeviceUID)
        else {
            teardown()
            throw .noOutputDevice
        }

        let sources = taps.map(\.source)
        if sources != builtSources || outputUID != builtOutputUID || !isRunning {
            teardown()
            try build(sources: sources, outputUID: outputUID)
        }
        publish(gains: taps.map(\.gain), equalizerGains: equalizerGains)
    }

    func teardown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if #available(macOS 14.2, *) {
            for tap in tapIDs {
                AudioHardwareDestroyProcessTap(tap)
            }
        }
        tapIDs.removeAll()
        builtSources.removeAll()
        builtOutputUID = nil
    }

    /// IslandBar's own Core Audio process object, so a global tap can exclude it and never feed
    /// our output back into itself.
    static func ownProcessObject() -> AudioObjectID? {
        var address = CoreAudioQuery.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            CoreAudioQuery.system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    // MARK: Private

    private func build(sources: [MixerTap.Source], outputUID: String) throws(MixerError) {
        guard #available(macOS 14.2, *) else { throw .unsupported }

        var tapUIDs: [String] = []
        for (index, source) in sources.enumerated() {
            let description: CATapDescription = switch source {
            case .processes(let objects): CATapDescription(stereoMixdownOfProcesses: objects)
            case .everythingExcept(let objects): CATapDescription(stereoGlobalTapButExcludeProcesses: objects)
            }
            description.name = "IslandBar Mixer \(index)"
            description.muteBehavior = .mutedWhenTapped
            description.isPrivate = true

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr, tapID != kAudioObjectUnknown else {
                teardown()
                throw .tapFailed(status)
            }
            tapIDs.append(tapID)
            tapUIDs.append(CoreAudioQuery.string(tapID, kAudioTapPropertyUID) ?? description.uuid.uuidString)
        }

        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "IslandBar Mixer",
            kAudioAggregateDeviceUIDKey: "io.github.islandbar.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map { [kAudioSubTapUIDKey: $0, kAudioSubTapDriftCompensationKey: true] },
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate)
        guard aggregateStatus == noErr, aggregate != kAudioObjectUnknown else {
            teardown()
            throw .aggregateFailed(aggregateStatus)
        }
        aggregateID = aggregate

        // Taps follow the output device's own input streams (if any) in the input buffer list.
        let inputStreams = CoreAudioQuery.streamCount(aggregate, scope: kAudioObjectPropertyScopeInput)
        ib_mixer_set_layout(mixer, Int32(max(0, inputStreams - tapIDs.count)), Int32(tapIDs.count))
        ib_mixer_reset_state(mixer)
        sampleRate = CoreAudioQuery.float64(aggregate, kAudioDevicePropertyNominalSampleRate) ?? 48_000

        var proc: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcID(aggregate, ib_mixer_ioproc, UnsafeMutableRawPointer(mixer), &proc)
        guard createStatus == noErr, let proc else {
            teardown()
            throw .ioFailed(createStatus)
        }
        procID = proc
        let startStatus = AudioDeviceStart(aggregate, proc)
        guard startStatus == noErr else {
            teardown()
            throw .ioFailed(startStatus)
        }
        builtSources = sources
        builtOutputUID = outputUID
    }

    private func publish(gains: [Float], equalizerGains: [Double]?) {
        gains.withUnsafeBufferPointer { buffer in
            ib_mixer_set_gains(mixer, buffer.baseAddress, Int32(buffer.count))
        }
        if let equalizerGains {
            let table = Equalizer.coefficientTable(gains: equalizerGains, sampleRate: sampleRate)
            table.withUnsafeBufferPointer { buffer in
                ib_mixer_set_eq(mixer, 1, buffer.baseAddress, Equalizer.preamp(for: equalizerGains))
            }
        } else {
            ib_mixer_set_eq(mixer, 0, nil, 1)
        }
    }
}

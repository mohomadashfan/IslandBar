import CoreAudio
@testable import FeatureAudioMixer
import IslandAudioDSP
import IslandCore
import IslandPlatform
import XCTest

/// Owns float storage for an AudioBufferList so tests can build arbitrary layouts.
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    /// One buffer per entry: (channels, samples interleaved).
    init(_ buffers: [(channels: UInt32, samples: [Float])]) {
        list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for (index, buffer) in buffers.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(buffer.samples.count, 1))
            pointer.initialize(from: buffer.samples, count: buffer.samples.count)
            storage.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: buffer.channels,
                mDataByteSize: UInt32(buffer.samples.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(pointer)
            )
        }
    }

    func samples(_ index: Int) -> [Float] {
        let count = Int(list[index].mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: storage[index], count: count))
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

final class MixerRenderTests: XCTestCase {
    private var mixer: OpaquePointer!

    override func setUp() {
        mixer = ib_mixer_create()
    }

    override func tearDown() {
        ib_mixer_destroy(mixer)
    }

    private func render(input: Buffers, output: Buffers) {
        ib_mixer_render(mixer, input.list.unsafePointer, output.list.unsafeMutablePointer)
    }

    func testUnityGainPassesStereoThrough() {
        ib_mixer_set_layout(mixer, 0, 1)
        let input = Buffers([(2, [0.1, -0.2, 0.3, -0.4])])
        let output = Buffers([(2, [9, 9, 9, 9])])
        render(input: input, output: output)
        XCTAssertEqual(output.samples(0), [0.1, -0.2, 0.3, -0.4])
    }

    func testPerTapGainsAreMixed() {
        ib_mixer_set_layout(mixer, 0, 2)
        let gains: [Float] = [0.5, 2]
        ib_mixer_set_gains(mixer, gains, 2)
        let input = Buffers([(2, [0.2, 0.2]), (2, [0.1, -0.1])])
        let output = Buffers([(2, [0, 0])])
        render(input: input, output: output)
        XCTAssertEqual(output.samples(0)[0], 0.2 * 0.5 + 0.1 * 2, accuracy: 1e-6)
        XCTAssertEqual(output.samples(0)[1], 0.2 * 0.5 - 0.1 * 2, accuracy: 1e-6)
    }

    func testOutputDeviceInputStreamsAreSkipped() {
        // A headset's own microphone stream comes first in the aggregate's input list.
        ib_mixer_set_layout(mixer, 1, 1)
        let input = Buffers([(1, [0.9, 0.9]), (2, [0.25, 0.5, 0.25, 0.5])])
        let output = Buffers([(2, [0, 0, 0, 0])])
        render(input: input, output: output)
        XCTAssertEqual(output.samples(0), [0.25, 0.5, 0.25, 0.5])
    }

    func testMutedTapIsSilent() {
        ib_mixer_set_layout(mixer, 0, 1)
        let gains: [Float] = [0]
        ib_mixer_set_gains(mixer, gains, 1)
        let output = Buffers([(2, [1, 1])])
        render(input: Buffers([(2, [0.7, 0.7])]), output: output)
        XCTAssertEqual(output.samples(0), [0, 0])
    }

    func testBoostIsClampedToFullScale() {
        ib_mixer_set_layout(mixer, 0, 1)
        let gains: [Float] = [1.5]
        ib_mixer_set_gains(mixer, gains, 1)
        let output = Buffers([(2, [0, 0])])
        render(input: Buffers([(2, [0.9, -0.9])]), output: output)
        XCTAssertEqual(output.samples(0), [1, -1])
    }

    func testNonInterleavedAndMultichannelOutput() {
        ib_mixer_set_layout(mixer, 0, 1)
        let input = Buffers([(2, [0.1, 0.2, 0.3, 0.4])])

        let separate = Buffers([(1, [9, 9]), (1, [9, 9]), (1, [9, 9])])
        render(input: input, output: separate)
        XCTAssertEqual(separate.samples(0), [0.1, 0.3])
        XCTAssertEqual(separate.samples(1), [0.2, 0.4])
        XCTAssertEqual(separate.samples(2), [0, 0], "extra channels are silenced")

        let fourChannel = Buffers([(4, [9, 9, 9, 9, 9, 9, 9, 9])])
        render(input: input, output: fourChannel)
        XCTAssertEqual(fourChannel.samples(0), [0.1, 0.2, 0, 0, 0.3, 0.4, 0, 0])
    }

    func testMonoTapFeedsBothChannelsAndShortInputIsSafe() {
        ib_mixer_set_layout(mixer, 0, 1)
        let output = Buffers([(2, [0, 0, 0, 0])])
        render(input: Buffers([(1, [0.5])]), output: output)
        XCTAssertEqual(output.samples(0), [0.5, 0.5, 0, 0])
    }

    func testMissingInputBuffersProduceSilence() {
        ib_mixer_set_layout(mixer, 0, 3)
        let output = Buffers([(2, [1, 1])])
        ib_mixer_render(mixer, nil, output.list.unsafeMutablePointer)
        XCTAssertEqual(output.samples(0), [0, 0])
    }

    func testFlatEqualiserIsTransparent() {
        ib_mixer_set_layout(mixer, 0, 1)
        let table = Equalizer.coefficientTable(gains: [0, 0, 0, 0, 0, 0], sampleRate: 48_000)
        ib_mixer_set_eq(mixer, 1, table, 1)
        let samples: [Float] = (0..<64).flatMap { i -> [Float] in
            let value = Float(sin(Double(i) * 0.3) * 0.5)
            return [value, value]
        }
        let output = Buffers([(2, [Float](repeating: 0, count: samples.count))])
        render(input: Buffers([(2, samples)]), output: output)
        for (out, original) in zip(output.samples(0), samples) {
            XCTAssertEqual(out, original, accuracy: 1e-5)
        }
    }

    func testGainUpdatesApplyToNextBuffer() {
        ib_mixer_set_layout(mixer, 0, 1)
        let output = Buffers([(2, [0, 0])])
        render(input: Buffers([(2, [0.4, 0.4])]), output: output)
        XCTAssertEqual(output.samples(0), [0.4, 0.4])

        let gains: [Float] = [0.25]
        ib_mixer_set_gains(mixer, gains, 1)
        render(input: Buffers([(2, [0.4, 0.4])]), output: output)
        XCTAssertEqual(output.samples(0)[0], 0.1, accuracy: 1e-6)
    }
}

final class EqualizerTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testPeakingBandHitsTargetGainAtCentre() {
        for gain in [-12.0, -6, 3, 9] {
            let c = Equalizer.coefficients(kind: .peaking, frequency: 1500, gainDB: gain, sampleRate: sampleRate)
            XCTAssertEqual(Equalizer.responseDB(c, frequency: 1500, sampleRate: sampleRate), gain, accuracy: 0.05)
            // Far from the centre the filter is nearly flat.
            XCTAssertEqual(Equalizer.responseDB(c, frequency: 40, sampleRate: sampleRate), 0, accuracy: 0.5)
        }
    }

    func testShelvesBoostTheirEnd() {
        let low = Equalizer.coefficients(kind: .lowShelf, frequency: 60, gainDB: 6, sampleRate: sampleRate)
        XCTAssertEqual(Equalizer.responseDB(low, frequency: 10, sampleRate: sampleRate), 6, accuracy: 0.3)
        XCTAssertEqual(Equalizer.responseDB(low, frequency: 5000, sampleRate: sampleRate), 0, accuracy: 0.1)

        let high = Equalizer.coefficients(kind: .highShelf, frequency: 12_000, gainDB: -6, sampleRate: sampleRate)
        XCTAssertEqual(Equalizer.responseDB(high, frequency: 22_000, sampleRate: sampleRate), -6, accuracy: 0.6)
        XCTAssertEqual(Equalizer.responseDB(high, frequency: 200, sampleRate: sampleRate), 0, accuracy: 0.1)
    }

    func testZeroGainIsIdentity() {
        let c = Equalizer.coefficients(kind: .peaking, frequency: 500, gainDB: 0, sampleRate: sampleRate)
        XCTAssertEqual(c[0], 1, accuracy: 1e-9)
        XCTAssertEqual(c[1], c[3], accuracy: 1e-9)
        XCTAssertEqual(c[2], c[4], accuracy: 1e-9)
    }

    func testCoefficientTableLayoutAndPreamp() {
        let table = Equalizer.coefficientTable(gains: [6, 0, 0, 0, 0, 3], sampleRate: sampleRate)
        XCTAssertEqual(table.count, Int(IB_EQ_BANDS) * Int(IB_BIQUAD_COEFFICIENTS))
        XCTAssertEqual(Equalizer.preamp(for: [6, 0, -3]), Float(pow(10, -6.0 / 20)), accuracy: 1e-6)
        XCTAssertEqual(Equalizer.preamp(for: [-6, -3]), 1)
    }

    func testFrequenciesStayBelowNyquist() {
        let c = Equalizer.coefficients(kind: .highShelf, frequency: 12_000, gainDB: 6, sampleRate: 22_050)
        XCTAssertTrue(c.allSatisfy(\.isFinite))
    }
}

final class MixerPlannerTests: XCTestCase {
    private let apps = [
        RunningAppInfo(bundleID: "com.spotify.client", name: "Spotify"),
        RunningAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome"),
        RunningAppInfo(bundleID: "com.apple.Safari", name: "Safari"),
    ]

    private func process(_ object: AudioObjectID, _ bundleID: String?, pid: pid_t = 100, output: Bool = true) -> AudioProcess {
        AudioProcess(objectID: object, pid: pid, bundleID: bundleID, isRunningInput: false, isRunningOutput: output)
    }

    func testGroupsHelpersAndDropsDaemonsAndSelf() {
        let groups = MixerPlanner.groups(processes: [
            process(1, "com.google.Chrome.helper"),
            process(2, "com.google.Chrome.helper", output: false),
            process(3, "com.spotify.client"),
            process(4, "com.apple.audiomxd"),
            process(5, "io.github.islandbar.IslandBar", pid: 42),
            process(6, "com.apple.WebKit.GPU"),
        ], regularApps: apps + [RunningAppInfo(bundleID: "io.github.islandbar.IslandBar", name: "IslandBar")], ownPID: 42)

        XCTAssertEqual(groups.map(\.id), ["com.apple.Safari", "com.google.Chrome", "com.spotify.client"])
        XCTAssertEqual(groups.first { $0.id == "com.google.Chrome" }?.processObjectIDs, [1, 2])
        XCTAssertEqual(groups.first { $0.id == "com.google.Chrome" }?.isPlaying, true)
    }

    private let spotify = AudioAppGroup(id: "com.spotify.client", name: "Spotify", processObjectIDs: [3], isPlaying: true)
    private let chrome = AudioAppGroup(id: "com.google.Chrome", name: "Chrome", processObjectIDs: [2, 1], isPlaying: true)

    func testNoTapsWhenNothingChanged() {
        XCTAssertTrue(MixerPlanner.taps(groups: [spotify, chrome], settings: SoundMixerSettings(), ownProcess: 99).isEmpty)
    }

    func testAdjustedAppsGetTheirOwnTap() {
        var settings = SoundMixerSettings()
        settings.setVolume(0.4, for: chrome.id)
        let taps = MixerPlanner.taps(groups: [spotify, chrome], settings: settings, ownProcess: 99)
        XCTAssertEqual(taps, [MixerTap(id: chrome.id, source: .processes([1, 2]), gain: 0.4)])
    }

    func testMutedAppHasZeroGain() {
        var settings = SoundMixerSettings()
        settings.setMuted(true, for: spotify.id)
        XCTAssertEqual(MixerPlanner.taps(groups: [spotify], settings: settings, ownProcess: nil).first?.gain, 0)
    }

    func testEqualiserUsesGlobalTapThatExcludesAdjustedAppsAndSelf() {
        var settings = SoundMixerSettings()
        settings.equalizerEnabled = true
        settings.equalizerPreset = .bassBoost
        settings.setVolume(1.2, for: spotify.id)
        let taps = MixerPlanner.taps(groups: [spotify, chrome], settings: settings, ownProcess: 99)
        XCTAssertEqual(taps, [
            MixerTap(id: spotify.id, source: .processes([3]), gain: 1.2),
            MixerTap(id: "*", source: .everythingExcept([3, 99]), gain: 1),
        ])
    }

    func testWithoutOwnProcessNoGlobalTapIsBuilt() {
        var settings = SoundMixerSettings()
        settings.equalizerEnabled = true
        settings.equalizerPreset = .vocal
        let taps = MixerPlanner.taps(groups: [spotify, chrome], settings: settings, ownProcess: nil)
        XCTAssertFalse(taps.contains { if case .everythingExcept = $0.source { true } else { false } })
        XCTAssertEqual(Set(taps.map(\.id)), [spotify.id, chrome.id])
    }

    func testFlatOrDisabledEqualiserAddsNothing() {
        var settings = SoundMixerSettings()
        settings.equalizerEnabled = true
        XCTAssertTrue(MixerPlanner.taps(groups: [spotify], settings: settings, ownProcess: 99).isEmpty, "flat preset is a no-op")
        settings.equalizerPreset = .bassBoost
        settings.equalizerEnabled = false
        XCTAssertTrue(MixerPlanner.taps(groups: [spotify], settings: settings, ownProcess: 99).isEmpty)
    }

    func testVisibleAppsOrdering() {
        let now = Date(timeIntervalSince1970: 10_000)
        let idleRecent = AudioAppGroup(id: "a.recent", name: "Recent", processObjectIDs: [7], isPlaying: false)
        let idleOld = AudioAppGroup(id: "a.old", name: "Old", processObjectIDs: [8], isPlaying: false)
        let visible = MixerPlanner.visible(
            [idleOld, idleRecent, spotify],
            settings: SoundMixerSettings(),
            lastPlayed: ["a.recent": now.addingTimeInterval(-60), "a.old": now.addingTimeInterval(-3600)],
            now: now
        )
        XCTAssertEqual(visible.map(\.id), [spotify.id, "a.recent"])
    }
}

final class SoundMixerSettingsTests: XCTestCase {
    func testVolumeStorageOnlyKeepsChanges() {
        var settings = SoundMixerSettings()
        settings.setVolume(0.5, for: "x")
        XCTAssertEqual(settings.volume(for: "x"), 0.5)
        settings.setVolume(1.001, for: "x")
        XCTAssertNil(settings.appVolumes["x"], "unity volume is not stored")
        settings.setVolume(9, for: "y")
        XCTAssertEqual(settings.volume(for: "y"), SoundMixerSettings.volumeRange.upperBound)
    }

    func testMuteOverridesVolume() {
        var settings = SoundMixerSettings()
        settings.setVolume(0.8, for: "x")
        settings.setMuted(true, for: "x")
        XCTAssertEqual(settings.volume(for: "x"), 0)
        settings.setMuted(false, for: "x")
        XCTAssertEqual(settings.volume(for: "x"), 0.8)
    }

    func testCustomGainsAreClampedAndPadded() {
        var settings = SoundMixerSettings()
        settings.equalizerPreset = .custom
        settings.customGains = [40, -40]
        XCTAssertEqual(settings.activeGains, [12, -12, 0, 0, 0, 0])
        XCTAssertTrue(EqualizerPreset.allCases.allSatisfy { $0.gains.count == SoundMixerSettings.bandCount })
    }
}

import CoreAudio
import Foundation
import IslandCore
import IslandPlatform

/// One app's audio, possibly produced by several processes (e.g. browser helpers).
public struct AudioAppGroup: Identifiable, Sendable, Equatable {
    /// The owning app's bundle ID; also the key for its saved volume.
    public var id: String
    public var name: String
    public var processObjectIDs: [AudioObjectID]
    public var isPlaying: Bool

    public init(id: String, name: String, processObjectIDs: [AudioObjectID], isPlaying: Bool) {
        self.id = id
        self.name = name
        self.processObjectIDs = processObjectIDs
        self.isPlaying = isPlaying
    }
}

/// Pure planning logic for the mixer, separated from Core Audio for testing.
public enum MixerPlanner {
    static let safariBundleID = "com.apple.Safari"

    /// Groups audio processes by the regular (Dock) app that owns them. Background daemons and
    /// IslandBar itself are left out, so they are never tapped individually.
    public static func groups(processes: [AudioProcess], regularApps: [RunningAppInfo], ownPID: pid_t) -> [AudioAppGroup] {
        var groups: [String: AudioAppGroup] = [:]
        for process in processes where process.pid != ownPID {
            guard let bundleID = process.bundleID, !bundleID.isEmpty,
                  let owner = owner(of: bundleID, among: regularApps)
            else { continue }
            var group = groups[owner.bundleID] ?? AudioAppGroup(id: owner.bundleID, name: owner.name, processObjectIDs: [], isPlaying: false)
            group.processObjectIDs.append(process.objectID)
            group.isPlaying = group.isPlaying || process.isRunningOutput
            groups[owner.bundleID] = group
        }
        return groups.values.sorted { $0.id < $1.id }
    }

    /// WebKit plays Safari's audio from a shared "com.apple.WebKit.GPU" process.
    static func owner(of bundleID: String, among apps: [RunningAppInfo]) -> RunningAppInfo? {
        if bundleID.hasPrefix("com.apple.WebKit"), let safari = apps.first(where: { $0.bundleID == safariBundleID }) {
            return safari
        }
        return RunningAppInfo.owner(of: bundleID, among: apps)
    }

    /// The taps needed for `settings`.
    ///
    /// - Apps with a changed volume or mute get their own tap with that gain.
    /// - With the equaliser on, everything else goes through one global tap that excludes those
    ///   apps and IslandBar itself. If IslandBar's own process is unknown, a global tap could
    ///   capture its own output, so each playing app gets a unity-gain tap instead.
    static func taps(groups: [AudioAppGroup], settings: SoundMixerSettings, ownProcess: AudioObjectID?) -> [MixerTap] {
        let adjusted = groups.filter { settings.volume(for: $0.id) != 1 && !$0.processObjectIDs.isEmpty }
        var taps = adjusted.map {
            MixerTap(id: $0.id, source: .processes($0.processObjectIDs.sorted()), gain: Float(settings.volume(for: $0.id)))
        }
        guard settings.equalizerIsActive else { return taps }

        if let ownProcess {
            let excluded = (adjusted.flatMap(\.processObjectIDs) + [ownProcess]).sorted()
            taps.append(MixerTap(id: "*", source: .everythingExcept(excluded), gain: 1))
        } else {
            let adjustedIDs = Set(adjusted.map(\.id))
            taps += groups
                .filter { $0.isPlaying && !adjustedIDs.contains($0.id) }
                .map { MixerTap(id: $0.id, source: .processes($0.processObjectIDs.sorted()), gain: 1) }
        }
        return taps
    }

    /// Apps worth showing: playing now, played recently, or with a saved adjustment.
    public static func visible(_ groups: [AudioAppGroup], settings: SoundMixerSettings, lastPlayed: [String: Date], now: Date, recentWindow: TimeInterval = 300) -> [AudioAppGroup] {
        groups
            .filter { group in
                group.isPlaying
                    || settings.volume(for: group.id) != 1
                    || (lastPlayed[group.id].map { now.timeIntervalSince($0) < recentWindow } ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

import AppKit
import CoreAudio

/// A running app that may own helper processes.
public struct RunningAppInfo: Sendable, Equatable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    @MainActor
    public static func current() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
            return RunningAppInfo(bundleID: bundleID, name: name)
        }
    }

    /// Resolves a helper process (e.g. `com.google.Chrome.helper`) to the app that owns it: the
    /// running app whose bundle ID is the longest dotted prefix of the helper's.
    public static func owner(of bundleID: String, among apps: [RunningAppInfo]) -> RunningAppInfo? {
        if let exact = apps.first(where: { $0.bundleID == bundleID }) {
            return exact
        }
        return apps
            .filter { bundleID.hasPrefix($0.bundleID + ".") }
            .max { $0.bundleID.count < $1.bundleID.count }
    }
}

/// One CoreAudio client process (exposed publicly from macOS 14.2).
public struct AudioProcess: Sendable, Equatable {
    public var objectID: AudioObjectID
    public var pid: pid_t
    public var bundleID: String?
    public var isRunningInput: Bool
    public var isRunningOutput: Bool

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String?, isRunningInput: Bool, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
    }

    /// All audio client processes, or `nil` before macOS 14.2.
    public static func all() -> [AudioProcess]? {
        guard let objects = CoreAudioQuery.objectIDs(CoreAudioQuery.system, kAudioHardwarePropertyProcessObjectList) else { return nil }
        return objects.compactMap { object in
            guard let pid = CoreAudioQuery.pid(object) else { return nil }
            return AudioProcess(
                objectID: object,
                pid: pid,
                bundleID: CoreAudioQuery.string(object, kAudioProcessPropertyBundleID),
                isRunningInput: CoreAudioQuery.uint32(object, kAudioProcessPropertyIsRunningInput) == 1,
                isRunningOutput: CoreAudioQuery.uint32(object, kAudioProcessPropertyIsRunningOutput) == 1
            )
        }
    }
}

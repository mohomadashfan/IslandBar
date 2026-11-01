import Foundation
import IslandPlatform

/// One CoreAudio client process (macOS 14.2+ exposes these publicly).
public struct AudioClient: Sendable, Equatable {
    public var pid: pid_t
    public var bundleID: String?
    public var isRunningInput: Bool

    public init(pid: pid_t, bundleID: String?, isRunningInput: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
    }
}

public struct CaptureUsage: Sendable, Equatable {
    public var cameraInUse = false
    /// Names of the cameras that are running, e.g. "MacBook Pro Camera".
    public var activeCameras: [String] = []
    public var microphoneInUse = false
    /// Apps capturing audio, when macOS can tell us (14.2+).
    public var microphoneApps: [String] = []
    /// False on systems without per-process audio information; `microphoneApps` is then empty.
    public var canAttributeMicrophone = true

    public init() {}
}

/// Pure logic for deciding who is using the microphone.
public enum CaptureAttribution {
    /// Always-on system listeners that capture audio in a low-power path without the user
    /// recording anything (e.g. "Hey Siri" detection, Sound Recognition). macOS does not show its
    /// own microphone indicator for these, so neither do we.
    public static let ignoredBundleIDs: Set<String> = [
        "com.apple.CoreSpeech",
        "com.apple.accessibility.heard",
    ]

    /// System services that capture on behalf of an app, mapped to a name people recognise.
    static let serviceNames: [String: String] = [
        "com.apple.avconferenced": "FaceTime",
        "com.apple.cmio.ContinuityCaptureAgent": "Continuity Camera",
    ]

    /// Clients that are really capturing audio, excluding ourselves and ignored services.
    public static func microphoneClients(_ clients: [AudioClient], ownPID: pid_t) -> [AudioClient] {
        clients.filter { client in
            guard client.isRunningInput, client.pid != ownPID else { return false }
            guard let bundleID = client.bundleID else { return true }
            return !ignoredBundleIDs.contains(bundleID)
        }
    }

    /// Resolves a helper process (e.g. `com.google.Chrome.helper`) to the app that owns it.
    public static func owningApp(of bundleID: String, among apps: [RunningAppInfo]) -> RunningAppInfo? {
        RunningAppInfo.owner(of: bundleID, among: apps)
    }

    /// User-facing, de-duplicated names for the given clients, in a stable order.
    public static func displayNames(
        for clients: [AudioClient], apps: [RunningAppInfo], nameForPID: (pid_t) -> String?
    ) -> [String] {
        var names: [String] = []
        for client in clients {
            let name: String? = {
                if let bundleID = client.bundleID, !bundleID.isEmpty {
                    if let app = owningApp(of: bundleID, among: apps) { return app.name }
                    if let service = serviceNames[bundleID] { return service }
                }
                return nameForPID(client.pid) ?? client.bundleID
            }()
            if let name, !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names.sorted()
    }

    /// Short text for the compact island.
    public static func summary(_ usage: CaptureUsage, showCamera: Bool, showMicrophone: Bool) -> String {
        let camera = showCamera && usage.cameraInUse
        let microphone = showMicrophone && usage.microphoneInUse
        if microphone, let app = usage.microphoneApps.first {
            return usage.microphoneApps.count > 1 ? "\(app) +\(usage.microphoneApps.count - 1)" : app
        }
        switch (camera, microphone) {
        case (true, true): return "Cam + Mic"
        case (true, false): return "Camera"
        case (false, true): return "Mic"
        case (false, false): return ""
        }
    }
}

import AppKit

enum ScriptFailure: Error, Equatable {
    case notPermitted
    case notRunning
    case failed(String)
}

/// Runs and caches compiled AppleScripts. Only ever used for scripts defined in this file.
@MainActor
final class AppleScriptBridge {
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptFailure> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else if let created = NSAppleScript(source: source) {
            compiled[source] = created
            script = created
        } else {
            return .failure(.failed("Could not compile script"))
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -1743: return .failure(.notPermitted)
            case -600, -609: return .failure(.notRunning)
            default: return .failure(.failed(error[NSAppleScript.errorMessage] as? String ?? "Error \(code)"))
            }
        }
        return .success(result)
    }
}

public enum MediaCommand: Sendable {
    case playPause, next, previous
}

/// One source of playback state: a native player or a browser.
@MainActor
protocol MediaSourceAdapter: AnyObject {
    var kind: PlayerKind { get }
    var permission: AutomationPermission { get }
    /// What the user still needs to do, if anything, while the source is running.
    var setupHint: MediaSetupHint? { get }
    var isRunning: Bool { get }
    var onUpdate: ((PlayerKind, NowPlaying?) -> Void)? { get set }
    var onPermissionChange: (() -> Void)? { get set }

    func start()
    func stop()
    func refresh()
    func requestPermission() async
    func send(_ command: MediaCommand) async
    func artwork(for track: NowPlaying, allowNetwork: Bool) async -> NSImage?
}

extension MediaSourceAdapter {
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier).isEmpty
    }
}

enum ArtworkLoader {
    /// Downloads artwork only over HTTPS from known media image CDNs.
    static func download(_ url: URL?) async -> NSImage? {
        guard let url, NowPlayingParser.isTrustedArtworkURL(url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000
        else { return nil }
        return NSImage(data: data)
    }
}

/// Talks to a native player (Music, Spotify). Metadata arrives through the player's
/// distributed notifications; AppleScript is used only after Automation is granted.
@MainActor
final class PlayerAdapter: MediaSourceAdapter {
    let kind: PlayerKind
    var onUpdate: ((PlayerKind, NowPlaying?) -> Void)?
    var onPermissionChange: (() -> Void)?
    private(set) var permission: AutomationPermission = .targetNotRunning

    var setupHint: MediaSetupHint? {
        isRunning && permission != .granted ? .allowAutomation(kind) : nil
    }

    private let scripts: AppleScriptBridge
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(kind: PlayerKind, scripts: AppleScriptBridge) {
        self.kind = kind
        self.scripts = scripts
    }

    func start() {
        guard tokens.isEmpty, let notificationName = kind.notificationName else { return }

        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] note in
            let info = (note.userInfo ?? [:]).reduce(into: [String: Any]()) { result, pair in
                if let key = pair.key as? String { result[key] = pair.value }
            }
            nonisolated(unsafe) let userInfo = info
            MainActor.assumeIsolated {
                self?.handleNotification(userInfo)
            }
        }
        tokens.append((distributed, token))

        let workspace = NSWorkspace.shared.notificationCenter
        let terminated = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, bundleID == self.kind.bundleIdentifier else { return }
                self.onUpdate?(self.kind, nil)
            }
        }
        tokens.append((workspace, terminated))

        if isRunning {
            Task { await self.updatePermission(ask: false) }
        }
    }

    func stop() {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    /// Prompts for Automation permission if it has not been decided yet.
    func requestPermission() async {
        await updatePermission(ask: true)
    }

    func updatePermission(ask: Bool) async {
        let result = await AutomationPermission.determine(for: kind.bundleIdentifier, askUserIfNeeded: ask)
        guard result != permission else { return }
        permission = result
        onPermissionChange?()
        if result == .granted {
            refresh()
        }
    }

    /// Reads full state (including playback position) when permitted.
    func refresh() {
        guard isRunning, permission == .granted else { return }
        switch scripts.run(stateScript) {
        case .success(let descriptor):
            let parsed = NowPlayingParser.parseScriptOutput(descriptor.stringValue ?? "", player: kind, now: .now)
            onUpdate?(kind, parsed)
        case .failure(.notPermitted):
            permission = .denied
            onPermissionChange?()
        case .failure:
            break
        }
    }

    func send(_ command: MediaCommand) async {
        guard isRunning else { return }
        if permission != .granted {
            await requestPermission()
        }
        guard permission == .granted else { return }
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        if case .failure(.notPermitted) = scripts.run("tell application id \"\(kind.bundleIdentifier)\" to \(verb)") {
            permission = .denied
            onPermissionChange?()
        }
    }

    func artwork(for track: NowPlaying, allowNetwork: Bool) async -> NSImage? {
        guard isRunning, permission == .granted else { return nil }
        switch kind {
        case .music:
            let source = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            guard case .success(let descriptor) = scripts.run(source) else { return nil }
            return NSImage(data: descriptor.data)
        case .spotify:
            guard allowNetwork else { return nil }
            let source = "tell application id \"com.spotify.client\" to get artwork url of current track"
            guard case .success(let descriptor) = scripts.run(source) else { return nil }
            return await ArtworkLoader.download(descriptor.stringValue.flatMap(URL.init(string:)))
        case .chrome, .safari, .edge, .brave:
            return nil
        }
    }

    // MARK: Private

    private func handleNotification(_ info: [String: Any]) {
        let parsed = NowPlayingParser.parseNotification(info, player: kind, now: .now)
        onUpdate?(kind, parsed)
        if permission == .targetNotRunning {
            Task { await updatePermission(ask: false) }
        }
        // Music's notification carries no position; fetch it when we are allowed to.
        if kind == .music, parsed != nil, permission == .granted {
            refresh()
        }
    }

    private var stateScript: String {
        let id = kind.bundleIdentifier
        let duration = kind == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let identifier = kind == .spotify ? "(id of t)" : "(persistent ID of t)"
        return """
        tell application id "\(id)"
            set s to player state as string
            if s is "stopped" then return s
            set t to current track
            set d to character id 31
            return s & d & (name of t) & d & (artist of t) & d & (album of t) & d & (\(duration) as string) & d & ((player position) as string) & d & (\(identifier) as string)
        end tell
        """
    }
}

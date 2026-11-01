import AppKit

/// Reads playback from a browser's tabs through its AppleScript dictionary.
///
/// 1. One Apple Event lists the URL of every tab (needs only Automation permission).
/// 2. Only tabs on the user's media-site list are probed with a small read-only script
///    (needs the browser's "Allow JavaScript from Apple Events", which the user turns on).
///
/// Browsers send no change notifications, so this polls, but only while the browser is
/// running and the Media module is active: every 2 s while something plays, 4 s otherwise.
@MainActor
final class BrowserAdapter: MediaSourceAdapter {
    let kind: PlayerKind
    var onUpdate: ((PlayerKind, NowPlaying?) -> Void)?
    var onPermissionChange: (() -> Void)?
    var sites: [String]

    private(set) var permission: AutomationPermission = .targetNotRunning
    private(set) var javaScriptDisabled = false

    private let scripts: AppleScriptBridge
    private var tokens: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var current: NowPlaying?

    /// At most this many matching tabs are probed per poll.
    static let maxProbedTabs = 8

    init(kind: PlayerKind, sites: [String], scripts: AppleScriptBridge) {
        precondition(kind.isBrowser)
        self.kind = kind
        self.sites = sites
        self.scripts = scripts
    }

    var setupHint: MediaSetupHint? {
        guard isRunning else { return nil }
        if permission != .granted { return .allowAutomation(kind) }
        if javaScriptDisabled { return .enableJavaScript(kind) }
        return nil
    }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                let launched = note.name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    guard let self, bundleID == self.kind.bundleIdentifier else { return }
                    launched ? self.startPolling() : self.browserQuit()
                }
            })
        }
        if isRunning {
            startPolling()
        }
    }

    func stop() {
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
        stopPolling()
    }

    func refresh() {
        _ = poll()
    }

    func requestPermission() async {
        await updatePermission(ask: true)
    }

    func send(_ command: MediaCommand) async {
        if permission != .granted {
            await requestPermission()
        }
        guard permission == .granted, let url = current?.pageURL else { return }
        _ = runInTab(url: url, javaScript: BrowserMedia.commandScript(command))
        try? await Task.sleep(for: .milliseconds(200))
        refresh()
    }

    func artwork(for track: NowPlaying, allowNetwork: Bool) async -> NSImage? {
        guard allowNetwork else { return nil }
        return await ArtworkLoader.download(track.artworkURL)
    }

    // MARK: Polling

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.updatePermission(ask: false)
            while !Task.isCancelled {
                guard let self else { return }
                let delay: Duration
                if self.permission == .granted {
                    delay = self.poll()
                } else {
                    // Waiting for the user to allow Automation; re-check occasionally.
                    try? await Task.sleep(for: .seconds(10))
                    await self.updatePermission(ask: false)
                    continue
                }
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func browserQuit() {
        stopPolling()
        permission = .targetNotRunning
        javaScriptDisabled = false
        publish(nil)
        onPermissionChange?()
    }

    private func updatePermission(ask: Bool) async {
        let result = await AutomationPermission.determine(for: kind.bundleIdentifier, askUserIfNeeded: ask)
        guard result != permission else { return }
        permission = result
        onPermissionChange?()
    }

    /// One polling pass. Returns how long to wait before the next one.
    private func poll() -> Duration {
        guard isRunning, permission == .granted else { return .seconds(5) }

        let tabs: [TabLocation]
        switch scripts.run("tell application id \"\(kind.bundleIdentifier)\" to return URL of every tab of every window") {
        case .success(let descriptor):
            tabs = Self.tabLocations(from: descriptor)
        case .failure(.notPermitted):
            permission = .denied
            onPermissionChange?()
            publish(nil)
            return .seconds(5)
        case .failure:
            publish(nil)
            return .seconds(5)
        }

        let candidates = tabs.filter { BrowserMedia.isMediaSite($0.url, sites: sites) }.prefix(Self.maxProbedTabs)
        guard !candidates.isEmpty else {
            publish(nil)
            return .seconds(4)
        }

        var best: NowPlaying?
        for tab in candidates {
            guard case .success(let output) = probe(tab) else { break }
            guard let state = BrowserMedia.parseReport(output, player: kind, now: .now) else { continue }
            if state.isPlaying {
                best = state
                break
            }
            if best == nil { best = state }
        }
        publish(best)
        return best?.isPlaying == true ? .seconds(2) : .seconds(4)
    }

    private func probe(_ tab: TabLocation) -> Result<String, ScriptFailure> {
        let target = "tab \(tab.tab) of window \(tab.window)"
        let source = switch kind {
        case .safari:
            "tell application id \"\(kind.bundleIdentifier)\" to do JavaScript \"\(BrowserMedia.probeScript)\" in \(target)"
        default:
            "tell application id \"\(kind.bundleIdentifier)\" to execute \(target) javascript \"\(BrowserMedia.probeScript)\""
        }
        return handleJavaScriptResult(scripts.run(source))
    }

    /// Runs a control script in the tab currently showing `url`, wherever it has moved to.
    private func runInTab(url: String, javaScript: String) -> Result<String, ScriptFailure> {
        let action = kind == .safari
            ? "do JavaScript \"\(javaScript)\" in t"
            : "execute t javascript \"\(javaScript)\""
        let source = """
        tell application id "\(kind.bundleIdentifier)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (URL of t) is \(BrowserMedia.appleScriptLiteral(url)) then
                        return \(action)
                    end if
                end repeat
            end repeat
            return ""
        end tell
        """
        return handleJavaScriptResult(scripts.run(source))
    }

    private func handleJavaScriptResult(_ result: Result<NSAppleEventDescriptor, ScriptFailure>) -> Result<String, ScriptFailure> {
        switch result {
        case .success(let descriptor):
            if javaScriptDisabled {
                javaScriptDisabled = false
                onPermissionChange?()
            }
            return .success(descriptor.stringValue ?? "")
        case .failure(.failed(let message)) where message.localizedCaseInsensitiveContains("javascript"):
            // The browser's "Allow JavaScript from Apple Events" setting is off.
            if !javaScriptDisabled {
                javaScriptDisabled = true
                onPermissionChange?()
            }
            return .failure(.failed(message))
        case .failure(.notPermitted):
            permission = .denied
            onPermissionChange?()
            return .failure(.notPermitted)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func publish(_ state: NowPlaying?) {
        current = state
        onUpdate?(kind, state)
    }

    // MARK: Parsing

    struct TabLocation: Equatable {
        var window: Int
        var tab: Int
        var url: String
    }

    /// Flattens the `{{url, url}, {url}}` list-of-lists returned for `URL of every tab of every window`.
    static func tabLocations(from descriptor: NSAppleEventDescriptor) -> [TabLocation] {
        var locations: [TabLocation] = []
        guard descriptor.numberOfItems > 0 else { return locations }
        for windowIndex in 1...descriptor.numberOfItems {
            guard let window = descriptor.atIndex(windowIndex), window.numberOfItems > 0 else { continue }
            for tabIndex in 1...window.numberOfItems {
                if let url = window.atIndex(tabIndex)?.stringValue, !url.isEmpty {
                    locations.append(TabLocation(window: windowIndex, tab: tabIndex, url: url))
                }
            }
        }
        return locations
    }
}

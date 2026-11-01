import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI

@MainActor
@Observable
public final class MediaModule: IslandModule {
    public let id = FeatureID.media
    public let displayName = "Media"
    public let symbolName = "music.note"

    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: NSImage? {
        didSet { artworkAccent = artwork.flatMap(ArtworkPalette.accent(for:)) }
    }
    /// Colour sampled from the current artwork.
    public private(set) var artworkAccent: NSColor?
    /// Bumped whenever an adapter's permission or setup state changes, so views re-read it.
    public private(set) var permissionRevision = 0

    @ObservationIgnored private var states: [PlayerKind: NowPlaying] = [:]
    @ObservationIgnored private var changedAt: [PlayerKind: Date] = [:]
    @ObservationIgnored private var adapters: [PlayerKind: any MediaSourceAdapter] = [:]
    @ObservationIgnored private var enabledPlayers: Set<PlayerKind> = [.music, .spotify]
    @ObservationIgnored private var browserSites = MediaSettings.defaultBrowserSites
    @ObservationIgnored private var showLiveActivity = true
    @ObservationIgnored private var fetchRemoteArtwork = false
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let scripts = AppleScriptBridge()
    @ObservationIgnored private let activity: ActivityCenter

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        guard showLiveActivity, nowPlaying?.isPlaying == true else { return nil }
        return LiveActivityPriority.media
    }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.media.isEnabled && !Self.players(for: settings.media).isEmpty
    }

    public func apply(_ settings: AppSettings) {
        let media = settings.media
        showLiveActivity = media.showLiveActivity
        let artworkChanged = media.fetchRemoteArtwork != fetchRemoteArtwork
        fetchRemoteArtwork = media.fetchRemoteArtwork

        let sites = media.browserSites.map(BrowserMedia.normalizedSite).filter { !$0.isEmpty }
        if sites != browserSites {
            browserSites = sites
            for adapter in adapters.values {
                (adapter as? BrowserAdapter)?.sites = sites
            }
        }

        let players = Self.players(for: media)
        if players != enabledPlayers {
            enabledPlayers = players
            if isActive { syncAdapters() }
        }
        if artworkChanged, let track = nowPlaying {
            artworkTrackID = nil
            loadArtwork(for: track)
        }
    }

    nonisolated static func players(for media: MediaSettings) -> Set<PlayerKind> {
        var players: Set<PlayerKind> = []
        if media.useAppleMusic { players.insert(.music) }
        if media.useSpotify { players.insert(.spotify) }
        if media.useBrowsers {
            if media.browserChrome { players.insert(.chrome) }
            if media.browserSafari { players.insert(.safari) }
            if media.browserEdge { players.insert(.edge) }
            if media.browserBrave { players.insert(.brave) }
        }
        return players
    }

    public func activate() {
        isActive = true
        syncAdapters()
    }

    public func deactivate() {
        isActive = false
        for adapter in adapters.values { adapter.stop() }
        adapters.removeAll()
        states.removeAll()
        changedAt.removeAll()
        artworkTask?.cancel()
        nowPlaying = nil
        artwork = nil
        artworkTrackID = nil
    }

    public func makeCompactLeading() -> AnyView { AnyView(MediaCompactLeading(module: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(MediaCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(MediaExpandedView(module: self)) }

    // MARK: Controls

    public func send(_ command: MediaCommand) {
        guard let player = nowPlaying?.player ?? runningPlayer(), let adapter = adapters[player] else { return }
        Task {
            await adapter.send(command)
            try? await Task.sleep(for: .milliseconds(250))
            adapter.refresh()
        }
    }

    public func permission(for player: PlayerKind) -> AutomationPermission? {
        _ = permissionRevision
        return adapters[player]?.permission
    }

    /// What the user should do next for the source on screen, or for any running source.
    public var setupHint: MediaSetupHint? {
        _ = permissionRevision
        if let player = nowPlaying?.player, let hint = adapters[player]?.setupHint {
            return hint
        }
        return PlayerKind.allCases.lazy.compactMap { self.adapters[$0]?.setupHint }.first
    }

    public func setupHint(for player: PlayerKind) -> MediaSetupHint? {
        _ = permissionRevision
        return adapters[player]?.setupHint
    }

    public func requestPermission(for player: PlayerKind) {
        guard let adapter = adapters[player] else { return }
        Task { await adapter.requestPermission() }
    }

    // MARK: Private

    private func runningPlayer() -> PlayerKind? {
        PlayerKind.allCases.first { adapters[$0]?.isRunning == true }
    }

    private func syncAdapters() {
        for (kind, adapter) in adapters where !enabledPlayers.contains(kind) {
            adapter.stop()
            adapters[kind] = nil
            states[kind] = nil
            changedAt[kind] = nil
        }
        for kind in enabledPlayers where adapters[kind] == nil {
            let adapter: any MediaSourceAdapter = kind.isBrowser
                ? BrowserAdapter(kind: kind, sites: browserSites, scripts: scripts)
                : PlayerAdapter(kind: kind, scripts: scripts)
            adapter.onUpdate = { [weak self] kind, state in self?.update(kind, state) }
            adapter.onPermissionChange = { [weak self] in self?.permissionRevision += 1 }
            adapters[kind] = adapter
            adapter.start()
        }
        permissionRevision += 1
        recompute()
    }

    private func update(_ player: PlayerKind, _ state: NowPlaying?) {
        let previous = states[player]
        if previous?.trackID != state?.trackID || previous?.isPlaying != state?.isPlaying {
            changedAt[player] = .now
        }
        states[player] = state
        recompute()
    }

    private func recompute() {
        let chosen = MediaSelection.choose(states, changedAt: changedAt)
        let previous = nowPlaying
        guard chosen != previous else { return }
        nowPlaying = chosen

        if let chosen, chosen.trackID != previous?.trackID {
            if chosen.isPlaying {
                activity.post(ActivityEvent(
                    source: .media, title: chosen.title,
                    subtitle: chosen.artist.isEmpty ? chosen.sourceDescription : chosen.artist,
                    symbolName: chosen.player.isBrowser ? "play.rectangle" : "music.note"
                ))
            }
            loadArtwork(for: chosen)
        } else if chosen == nil {
            artwork = nil
            artworkTrackID = nil
        }
    }

    private func loadArtwork(for track: NowPlaying) {
        guard track.trackID != artworkTrackID else { return }
        artworkTrackID = track.trackID
        artworkTask?.cancel()
        artwork = nil
        guard let adapter = adapters[track.player] else { return }
        let allowNetwork = fetchRemoteArtwork
        artworkTask = Task { [weak self] in
            let image = await adapter.artwork(for: track, allowNetwork: allowNetwork)
            guard !Task.isCancelled, let self, self.artworkTrackID == track.trackID else { return }
            self.artwork = image
        }
    }
}

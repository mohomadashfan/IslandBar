import Foundation

/// Players IslandBar can talk to through documented, user-permissioned interfaces.
///
/// macOS has no public API for system-wide "Now Playing" metadata, so support is per player:
/// - Music and Spotify broadcast track changes as distributed notifications (no permission
///   needed) and expose AppleScript dictionaries for control and artwork (Automation permission).
/// - Browsers expose their tabs through AppleScript; with the user's opt-in setting
///   "Allow JavaScript from Apple Events", IslandBar reads media state from media-site tabs.
public enum PlayerKind: String, Sendable, CaseIterable, Identifiable {
    case music
    case spotify
    case chrome
    case safari
    case edge
    case brave

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .edge: "Edge"
        case .brave: "Brave"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .edge: "com.microsoft.edgemac"
        case .brave: "com.brave.Browser"
        }
    }

    public var isBrowser: Bool {
        switch self {
        case .music, .spotify: false
        case .chrome, .safari, .edge, .brave: true
        }
    }

    /// Where the user turns on "Allow JavaScript from Apple Events" in this browser.
    public var javaScriptSettingLocation: String? {
        switch self {
        case .music, .spotify: nil
        case .chrome, .edge, .brave: "View › Developer › Allow JavaScript from Apple Events"
        case .safari: "Settings › Advanced › “Show features for web developers”, then Develop › Allow JavaScript from Apple Events"
        }
    }

    var notificationName: Notification.Name? {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .chrome, .safari, .edge, .brave: nil
        }
    }
}

/// Something the user has to do before a player can be read or controlled.
public enum MediaSetupHint: Sendable, Equatable {
    case allowAutomation(PlayerKind)
    case enableJavaScript(PlayerKind)

    public var player: PlayerKind {
        switch self {
        case .allowAutomation(let player), .enableJavaScript(let player): player
        }
    }
}

public struct NowPlaying: Sendable, Equatable {
    public var player: PlayerKind
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var duration: TimeInterval?
    /// Playback position measured at `positionDate`.
    public var position: TimeInterval?
    public var positionDate: Date
    /// Identifies the track for artwork caching and change detection.
    public var trackID: String
    /// For browser playback: the site, e.g. "YouTube".
    public var site: String?
    /// For browser playback: the tab's address, used to target controls.
    public var pageURL: String?
    /// Artwork published by the page, if any (only downloaded when the user allows it).
    public var artworkURL: URL?

    public init(
        player: PlayerKind, title: String, artist: String, album: String, isPlaying: Bool,
        duration: TimeInterval?, position: TimeInterval?, positionDate: Date, trackID: String,
        site: String? = nil, pageURL: String? = nil, artworkURL: URL? = nil
    ) {
        self.player = player
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.positionDate = positionDate
        self.trackID = trackID
        self.site = site
        self.pageURL = pageURL
        self.artworkURL = artworkURL
    }

    /// "Spotify", or "YouTube · Chrome" for browser playback.
    public var sourceDescription: String {
        guard let site else { return player.displayName }
        return "\(site) · \(player.displayName)"
    }

    /// Extrapolated position, so the progress bar moves without polling the player.
    public func position(at now: Date) -> TimeInterval? {
        guard let position else { return nil }
        let current = isPlaying ? position + max(0, now.timeIntervalSince(positionDate)) : position
        if let duration { return min(current, duration) }
        return current
    }

    public func progress(at now: Date) -> Double? {
        guard let duration, duration > 0, let current = position(at: now) else { return nil }
        return current / duration
    }
}

/// Pure parsing of what the players send us.
public enum NowPlayingParser {
    static let fieldSeparator: Character = "\u{1F}"

    /// Parses a player's distributed notification `userInfo`. Returns `nil` when stopped.
    public static func parseNotification(_ info: [String: Any], player: PlayerKind, now: Date) -> NowPlaying? {
        let state = (info["Player State"] as? String)?.lowercased() ?? "stopped"
        guard state != "stopped", let title = info["Name"] as? String, !title.isEmpty else { return nil }

        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        switch player {
        case .music:
            let durationMS = (info["Total Time"] as? NSNumber)?.doubleValue
            let persistentID = (info["PersistentID"] as? NSNumber)?.stringValue
            return NowPlaying(
                player: player, title: title, artist: artist, album: album,
                isPlaying: state == "playing",
                duration: durationMS.map { $0 / 1000 },
                position: nil, positionDate: now,
                trackID: persistentID ?? "\(title)|\(artist)|\(album)"
            )
        case .chrome, .safari, .edge, .brave:
            return nil
        case .spotify:
            let durationMS = (info["Duration"] as? NSNumber)?.doubleValue
            let position = (info["Playback Position"] as? NSNumber)?.doubleValue
            return NowPlaying(
                player: player, title: title, artist: artist, album: album,
                isPlaying: state == "playing",
                duration: durationMS.map { $0 / 1000 },
                position: position, positionDate: now,
                trackID: info["Track ID"] as? String ?? "\(title)|\(artist)|\(album)"
            )
        }
    }

    /// Parses the output of the state script: `state␟title␟artist␟album␟duration␟position␟id`.
    public static func parseScriptOutput(_ output: String, player: PlayerKind, now: Date) -> NowPlaying? {
        let fields = output.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 7 else { return nil }
        let state = fields[0].lowercased()
        guard state == "playing" || state == "paused", !fields[1].isEmpty else { return nil }

        return NowPlaying(
            player: player, title: fields[1], artist: fields[2], album: fields[3],
            isPlaying: state == "playing",
            duration: number(fields[4]),
            position: number(fields[5]),
            positionDate: now,
            trackID: fields[6].isEmpty ? "\(fields[1])|\(fields[2])|\(fields[3])" : fields[6]
        )
    }

    /// AppleScript formats reals using the user's locale, so accept a decimal comma.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "missing value" else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// Image CDNs of the supported players and media sites.
    static let artworkHosts = [
        "scdn.co", "spotifycdn.com",            // Spotify
        "ytimg.com", "googleusercontent.com",   // YouTube, YouTube Music
        "sndcdn.com",                           // SoundCloud
        "mzstatic.com",                         // Apple Music
        "bcbits.com",                           // Bandcamp
        "dzcdn.net",                            // Deezer
        "tidal.com", "media-amazon.com", "mxcdn.net", "vimeocdn.com", "jtvnw.net",
    ]

    /// Artwork is only fetched over HTTPS from a known media image CDN.
    public static func isTrustedArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return artworkHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Pure helpers for reading media state out of browser tabs.
public enum BrowserMedia {
    /// True if `urlString` is on one of `sites` or a subdomain of it. Matching is on whole
    /// domain labels, so "evilyoutube.com" does not match "youtube.com".
    public static func isMediaSite(_ urlString: String, sites: [String]) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased(),
              let scheme = URL(string: urlString)?.scheme, scheme == "https" || scheme == "http"
        else { return false }
        return sites.contains { site in
            let site = normalizedSite(site)
            guard !site.isEmpty else { return false }
            return host == site || host.hasSuffix("." + site)
        }
    }

    /// Accepts "YouTube.com", "https://www.youtube.com/" etc. and returns "youtube.com".
    public static func normalizedSite(_ site: String) -> String {
        var text = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: text), let host = url.host { text = host }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    public static func siteName(forHost host: String) -> String {
        let host = host.lowercased()
        let known: [(String, String)] = [
            ("music.youtube.com", "YouTube Music"), ("youtube.com", "YouTube"),
            ("soundcloud.com", "SoundCloud"), ("open.spotify.com", "Spotify Web"),
            ("music.apple.com", "Apple Music"), ("bandcamp.com", "Bandcamp"), ("deezer.com", "Deezer"),
            ("tidal.com", "TIDAL"), ("music.amazon.com", "Amazon Music"), ("mixcloud.com", "Mixcloud"),
            ("vimeo.com", "Vimeo"), ("twitch.tv", "Twitch"),
        ]
        for (domain, name) in known where host == domain || host.hasSuffix("." + domain) {
            return name
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    struct Report: Decodable {
        var url: String
        var host: String
        var title: String
        var artist: String?
        var album: String?
        var playing: Bool
        var duration: Double?
        var position: Double?
        var artwork: String?
    }

    /// Parses the JSON produced by `probeScript`. Empty output means "no media in this tab".
    public static func parseReport(_ json: String, player: PlayerKind, now: Date) -> NowPlaying? {
        guard !json.isEmpty, let report = try? JSONDecoder().decode(Report.self, from: Data(json.utf8)) else {
            return nil
        }
        let title = clean(report.title)
        guard !title.isEmpty else { return nil }
        let duration = report.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return NowPlaying(
            player: player,
            title: title,
            artist: clean(report.artist ?? ""),
            album: clean(report.album ?? ""),
            isPlaying: report.playing,
            duration: duration,
            position: report.position.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            positionDate: now,
            trackID: "\(report.url)|\(title)",
            site: siteName(forHost: report.host),
            pageURL: report.url,
            artworkURL: report.artwork.flatMap(URL.init(string:))
        )
    }

    private static func clean(_ text: String) -> String {
        String(text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces).prefix(200))
    }

    /// Escapes text for use inside a double-quoted AppleScript string literal.
    public static func appleScriptLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Finds the audible media element. Muted elements (such as YouTube's hover previews) are
    /// ignored. Written without double quotes or backslashes so it embeds directly in AppleScript.
    static let findMediaJS = """
    var ms=Array.prototype.slice.call(document.querySelectorAll('video,audio'));\
    var m=null;\
    for(var i=0;i<ms.length;i++){var e=ms[i];if(!e.paused&&!e.ended&&!e.muted){m=e;break;}}\
    if(!m){for(var j=0;j<ms.length;j++){var f=ms[j];if(f.currentTime>0&&!f.ended&&!f.muted&&f.duration>0){m=f;break;}}}
    """

    /// Read-only probe: reports what is playing in the tab as JSON, or an empty string.
    static let probeScript = """
    (function(){\(findMediaJS)\
    if(!m){return '';}\
    var md=navigator.mediaSession?navigator.mediaSession.metadata:null;\
    var art='';if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src;}\
    return JSON.stringify({url:location.href,host:location.hostname,title:(md&&md.title)||document.title,\
    artist:(md&&md.artist)||'',album:(md&&md.album)||'',playing:!m.paused,\
    duration:isFinite(m.duration)?m.duration:null,position:m.currentTime,artwork:art});})()
    """

    /// Control scripts. Next/previous use the site's own buttons where known.
    static func commandScript(_ command: MediaCommand) -> String {
        switch command {
        case .playPause:
            return "(function(){\(findMediaJS)if(!m){return '';}if(m.paused){m.play();}else{m.pause();}return 'ok';})()"
        case .next:
            return """
            (function(){var b=document.querySelector('.ytp-next-button,ytmusic-player-bar .next-button,.skipControl__next,\
            [data-testid=control-button-skip-forward]');if(b){b.click();return 'ok';}return '';})()
            """
        case .previous:
            return """
            (function(){var b=document.querySelector('ytmusic-player-bar .previous-button,.skipControl__previous,\
            [data-testid=control-button-skip-back]');if(b){b.click();return 'ok';}\
            \(findMediaJS)if(m){m.currentTime=0;return 'ok';}return '';})()
            """
        }
    }
}

/// Chooses which player's state the island shows.
public enum MediaSelection {
    /// Prefers something playing; among equals, the one whose state changed most recently.
    /// (Polled browser sources refresh constantly, so freshness alone would always favour them.)
    public static func choose(_ states: [PlayerKind: NowPlaying], changedAt: [PlayerKind: Date]) -> NowPlaying? {
        states.values.max { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return !lhs.isPlaying }
            let l = changedAt[lhs.player] ?? .distantPast
            let r = changedAt[rhs.player] ?? .distantPast
            if l != r { return l < r }
            return lhs.player.rawValue > rhs.player.rawValue
        }
    }
}

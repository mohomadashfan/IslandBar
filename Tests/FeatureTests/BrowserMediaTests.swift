import AppKit
@testable import FeatureMedia
import IslandCore
import XCTest

final class BrowserMediaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 4_000_000)
    private let sites = MediaSettings.defaultBrowserSites

    func testSiteMatchingUsesWholeDomainLabels() {
        XCTAssertTrue(BrowserMedia.isMediaSite("https://www.youtube.com/watch?v=abc", sites: sites))
        XCTAssertTrue(BrowserMedia.isMediaSite("https://music.youtube.com/watch?v=abc", sites: sites))
        XCTAssertTrue(BrowserMedia.isMediaSite("https://soundcloud.com/artist/track", sites: sites))
        XCTAssertFalse(BrowserMedia.isMediaSite("https://evilyoutube.com/watch", sites: sites))
        XCTAssertFalse(BrowserMedia.isMediaSite("https://example.com/?u=youtube.com", sites: sites))
        XCTAssertFalse(BrowserMedia.isMediaSite("file:///Users/me/youtube.com.html", sites: sites))
        XCTAssertFalse(BrowserMedia.isMediaSite("not a url", sites: sites))
        // Only the listed Spotify subdomain, not all of spotify.com.
        XCTAssertFalse(BrowserMedia.isMediaSite("https://www.spotify.com/account", sites: sites))
    }

    func testSiteNormalisation() {
        XCTAssertEqual(BrowserMedia.normalizedSite("  https://www.YouTube.com/ "), "youtube.com")
        XCTAssertEqual(BrowserMedia.normalizedSite("Music.Example.com/"), "music.example.com")
        XCTAssertEqual(BrowserMedia.normalizedSite(""), "")
    }

    func testSiteNames() {
        XCTAssertEqual(BrowserMedia.siteName(forHost: "www.youtube.com"), "YouTube")
        XCTAssertEqual(BrowserMedia.siteName(forHost: "music.youtube.com"), "YouTube Music")
        XCTAssertEqual(BrowserMedia.siteName(forHost: "www.example.org"), "example.org")
    }

    func testParsesYouTubeReport() throws {
        let json = """
        {"url":"https://www.youtube.com/watch?v=abc","host":"www.youtube.com","title":"Great Song",
         "artist":"Some Channel","album":"","playing":true,"duration":245.3,"position":12.5,
         "artwork":"https://i.ytimg.com/vi/abc/hqdefault.jpg"}
        """
        let track = try XCTUnwrap(BrowserMedia.parseReport(json, player: .chrome, now: now))
        XCTAssertEqual(track.title, "Great Song")
        XCTAssertEqual(track.artist, "Some Channel")
        XCTAssertTrue(track.isPlaying)
        XCTAssertEqual(track.duration, 245.3)
        XCTAssertEqual(track.position, 12.5)
        XCTAssertEqual(track.site, "YouTube")
        XCTAssertEqual(track.sourceDescription, "YouTube · Chrome")
        XCTAssertEqual(track.pageURL, "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(track.artworkURL?.host, "i.ytimg.com")
    }

    func testLiveStreamsAndMissingFields() throws {
        let json = #"{"url":"https://twitch.tv/x","host":"twitch.tv","title":"Live","playing":false,"duration":null,"position":3}"#
        let track = try XCTUnwrap(BrowserMedia.parseReport(json, player: .safari, now: now))
        XCTAssertNil(track.duration)
        XCTAssertFalse(track.isPlaying)
        XCTAssertEqual(track.artist, "")
    }

    func testEmptyOrInvalidReportsAreNil() {
        XCTAssertNil(BrowserMedia.parseReport("", player: .chrome, now: now))
        XCTAssertNil(BrowserMedia.parseReport("missing value", player: .chrome, now: now))
        XCTAssertNil(BrowserMedia.parseReport(#"{"url":"u","host":"h","title":"  ","playing":true}"#, player: .chrome, now: now))
    }

    func testAppleScriptLiteralEscaping() {
        XCTAssertEqual(BrowserMedia.appleScriptLiteral(#"a"b\c"#), #""a\"b\\c""#)
    }

    func testScriptsEmbedSafelyInAppleScript() {
        for script in [BrowserMedia.probeScript] + [MediaCommand.playPause, .next, .previous].map(BrowserMedia.commandScript) {
            XCTAssertFalse(script.contains("\""), "JavaScript must not contain double quotes")
            XCTAssertFalse(script.contains("\\"), "JavaScript must not contain backslashes")
            XCTAssertFalse(script.contains("\n"), "JavaScript must be a single line")
        }
    }

    func testProbeScriptIsReadOnly() {
        for forbidden in ["cookie", "localStorage", "fetch(", "XMLHttpRequest", "innerHTML", ".value", "click("] {
            XCTAssertFalse(BrowserMedia.probeScript.contains(forbidden), forbidden)
        }
    }

    @MainActor
    func testTabLocationsFromNestedLists() {
        let window1 = NSAppleEventDescriptor.list()
        window1.insert(NSAppleEventDescriptor(string: "https://example.com"), at: 1)
        window1.insert(NSAppleEventDescriptor(string: "https://www.youtube.com/watch?v=1"), at: 2)
        let window2 = NSAppleEventDescriptor.list()
        window2.insert(NSAppleEventDescriptor(string: "https://soundcloud.com/x"), at: 1)
        let empty = NSAppleEventDescriptor.list()
        let all = NSAppleEventDescriptor.list()
        all.insert(window1, at: 1)
        all.insert(empty, at: 2)
        all.insert(window2, at: 3)

        let tabs = BrowserAdapter.tabLocations(from: all)

        XCTAssertEqual(tabs, [
            .init(window: 1, tab: 1, url: "https://example.com"),
            .init(window: 1, tab: 2, url: "https://www.youtube.com/watch?v=1"),
            .init(window: 3, tab: 1, url: "https://soundcloud.com/x"),
        ])
        XCTAssertTrue(BrowserAdapter.tabLocations(from: .list()).isEmpty)
    }

    func testArtworkAllowListCoversWebPlayers() {
        XCTAssertTrue(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://i.ytimg.com/vi/x/hq.jpg")!))
        XCTAssertTrue(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://lh3.googleusercontent.com/abc")!))
        XCTAssertTrue(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://i1.sndcdn.com/a.jpg")!))
        XCTAssertFalse(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://tracker.example/pixel.gif")!))
        XCTAssertFalse(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://notytimg.com/x.jpg")!))
    }
}

final class MediaSelectionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func track(_ player: PlayerKind, playing: Bool) -> NowPlaying {
        NowPlaying(player: player, title: player.rawValue, artist: "", album: "", isPlaying: playing,
                   duration: nil, position: nil, positionDate: t0, trackID: player.rawValue)
    }

    func testPlayingBeatsPaused() {
        let chosen = MediaSelection.choose(
            [.spotify: track(.spotify, playing: false), .chrome: track(.chrome, playing: true)],
            changedAt: [.spotify: t0.addingTimeInterval(100), .chrome: t0]
        )
        XCTAssertEqual(chosen?.player, .chrome)
    }

    func testMostRecentlyChangedWinsAmongEquals() {
        let states: [PlayerKind: NowPlaying] = [.music: track(.music, playing: true), .safari: track(.safari, playing: true)]
        XCTAssertEqual(MediaSelection.choose(states, changedAt: [.music: t0.addingTimeInterval(5), .safari: t0])?.player, .music)
        XCTAssertEqual(MediaSelection.choose(states, changedAt: [.music: t0, .safari: t0.addingTimeInterval(5)])?.player, .safari)
    }

    func testEmpty() {
        XCTAssertNil(MediaSelection.choose([:], changedAt: [:]))
    }

    func testBrowsersOnlyWhenEnabled() {
        var media = MediaSettings()
        XCTAssertEqual(MediaModule.players(for: media), [.music, .spotify])
        media.useBrowsers = true
        media.browserEdge = false
        XCTAssertEqual(MediaModule.players(for: media), [.music, .spotify, .chrome, .safari, .brave])
    }
}

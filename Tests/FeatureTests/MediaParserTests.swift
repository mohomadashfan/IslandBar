@testable import FeatureMedia
import XCTest

final class MediaParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    func testMusicNotification() throws {
        let info: [String: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "Record",
            "Total Time": NSNumber(value: 215_000), "PersistentID": NSNumber(value: 1234),
        ]
        let track = try XCTUnwrap(NowPlayingParser.parseNotification(info, player: .music, now: now))
        XCTAssertTrue(track.isPlaying)
        XCTAssertEqual(track.duration, 215)
        XCTAssertNil(track.position)
        XCTAssertEqual(track.trackID, "1234")
    }

    func testSpotifyNotification() throws {
        let info: [String: Any] = [
            "Player State": "Paused", "Name": "Tune", "Artist": "Artist", "Album": "Album",
            "Duration": NSNumber(value: 180_000), "Playback Position": NSNumber(value: 42.5),
            "Track ID": "spotify:track:abc",
        ]
        let track = try XCTUnwrap(NowPlayingParser.parseNotification(info, player: .spotify, now: now))
        XCTAssertFalse(track.isPlaying)
        XCTAssertEqual(track.position, 42.5)
        XCTAssertEqual(track.trackID, "spotify:track:abc")
        // Paused tracks do not advance.
        XCTAssertEqual(track.position(at: now.addingTimeInterval(30)), 42.5)
    }

    func testStoppedOrEmptyIsNil() {
        XCTAssertNil(NowPlayingParser.parseNotification(["Player State": "Stopped", "Name": "x"], player: .music, now: now))
        XCTAssertNil(NowPlayingParser.parseNotification(["Player State": "Playing", "Name": ""], player: .music, now: now))
        XCTAssertNil(NowPlayingParser.parseNotification([:], player: .spotify, now: now))
    }

    func testScriptOutputWithLocaleDecimalComma() throws {
        let output = ["playing", "Song", "Band", "Record", "215,5", "10,25", "ABCD"].joined(separator: "\u{1F}")
        let track = try XCTUnwrap(NowPlayingParser.parseScriptOutput(output, player: .music, now: now))
        XCTAssertEqual(track.duration, 215.5)
        XCTAssertEqual(track.position, 10.25)
        XCTAssertEqual(track.trackID, "ABCD")
    }

    func testScriptOutputStoppedOrMalformed() {
        XCTAssertNil(NowPlayingParser.parseScriptOutput("stopped", player: .music, now: now))
        XCTAssertNil(NowPlayingParser.parseScriptOutput("playing\u{1F}only", player: .music, now: now))
    }

    func testScriptOutputMissingValues() throws {
        let output = ["paused", "Song", "", "", "missing value", "", ""].joined(separator: "\u{1F}")
        let track = try XCTUnwrap(NowPlayingParser.parseScriptOutput(output, player: .spotify, now: now))
        XCTAssertNil(track.duration)
        XCTAssertNil(track.position)
        XCTAssertEqual(track.trackID, "Song||")
    }

    func testPositionExtrapolatesWhilePlayingAndClampsToDuration() {
        let track = NowPlaying(player: .spotify, title: "t", artist: "", album: "", isPlaying: true,
                               duration: 100, position: 90, positionDate: now, trackID: "t")
        XCTAssertEqual(track.position(at: now.addingTimeInterval(5)), 95)
        XCTAssertEqual(track.position(at: now.addingTimeInterval(50)), 100)
        XCTAssertEqual(track.progress(at: now.addingTimeInterval(5)) ?? 0, 0.95, accuracy: 0.0001)
    }

    func testArtworkURLAllowList() {
        XCTAssertTrue(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://i.scdn.co/image/abc")!))
        XCTAssertFalse(NowPlayingParser.isTrustedArtworkURL(URL(string: "http://i.scdn.co/image/abc")!))
        XCTAssertFalse(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://example.com/i.scdn.co")!))
        XCTAssertFalse(NowPlayingParser.isTrustedArtworkURL(URL(string: "https://evilscdn.co/x")!))
    }
}

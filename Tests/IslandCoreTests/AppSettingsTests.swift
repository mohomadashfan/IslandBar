import IslandCore
import XCTest

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchCurrentSchema() {
        let settings = AppSettings.defaults
        XCTAssertEqual(settings.schemaVersion, AppSettings.currentSchemaVersion)
        XCTAssertTrue(settings.general.isIslandEnabled)
        XCTAssertEqual(settings.appearance.preset, .midnightBlack)
    }

    func testRoundTripPreservesValues() throws {
        var settings = AppSettings()
        settings.general.isIslandEnabled = false
        settings.focus.workMinutes = 50
        settings.displays.overrides["ABC"] = false
        settings.developer.repositories = ["/tmp/repo"]

        let data = try JSONEncoder().encode(settings)

        XCTAssertEqual(try AppSettings.decode(from: data), settings)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try AppSettings.decode(from: Data("{}".utf8)), .defaults)
    }

    func testMissingNestedKeysKeepDefaults() throws {
        let json = #"{"general": {"isIslandEnabled": false}, "focus": {"workMinutes": 40}}"#

        let decoded = try AppSettings.decode(from: Data(json.utf8))

        XCTAssertFalse(decoded.general.isIslandEnabled)
        XCTAssertEqual(decoded.general.hoverDelay, GeneralSettings().hoverDelay)
        XCTAssertEqual(decoded.focus.workMinutes, 40)
        XCTAssertEqual(decoded.focus.shortBreakMinutes, FocusSettings().shortBreakMinutes)
        XCTAssertEqual(decoded.appearance, AppearanceSettings())
    }

    func testUnknownKeysAreIgnored() throws {
        let json = #"{"general": {"isIslandEnabled": false, "fromTheFuture": 42}, "newSection": {"x": 1}}"#
        let decoded = try AppSettings.decode(from: Data(json.utf8))
        XCTAssertFalse(decoded.general.isIslandEnabled)
    }

    func testStoredArraysReplaceDefaults() throws {
        let json = #"{"developer": {"repositories": ["/a", "/b"]}}"#
        let decoded = try AppSettings.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.developer.repositories, ["/a", "/b"])
    }

    func testWrongTypeIsAnError() {
        let json = #"{"general": {"isIslandEnabled": "yes"}}"#
        XCTAssertThrowsError(try AppSettings.decode(from: Data(json.utf8)))
    }

    func testVersion1LayoutIsMigrated() throws {
        let json = #"{"schemaVersion": 1, "appearance": {"layout": {"expandedHeight": 200}}}"#
        let decoded = try AppSettings.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.appearance.layout.expandedHeight, LayoutSettings().expandedHeight)
        XCTAssertEqual(decoded.schemaVersion, AppSettings.currentSchemaVersion)
    }

    func testEventInboxBecomesOptIn() throws {
        let json = #"{"schemaVersion": 2, "developer": {"eventInboxEnabled": true}}"#
        XCTAssertFalse(try AppSettings.decode(from: Data(json.utf8)).developer.eventInboxEnabled)
        let current = #"{"schemaVersion": 3, "developer": {"eventInboxEnabled": true}}"#
        XCTAssertTrue(try AppSettings.decode(from: Data(current.utf8)).developer.eventInboxEnabled, "a deliberate choice is kept")
    }

    func testPrivacyDefaults() {
        let settings = AppSettings.defaults
        XCTAssertFalse(settings.developer.eventInboxEnabled)
        XCTAssertFalse(settings.media.useBrowsers)
        XCTAssertFalse(settings.media.fetchRemoteArtwork)
        XCTAssertFalse(settings.soundMixer.isEnabled)
        XCTAssertFalse(settings.mirror.startAutomatically)
        XCTAssertFalse(settings.notifications.deliverSystemNotifications)
        XCTAssertFalse(settings.systemMonitor.showGPU)
        XCTAssertTrue(settings.general.hideFromScreenCapture)
    }

    func testCustomHeightSurvivesMigration() throws {
        let json = #"{"schemaVersion": 1, "appearance": {"layout": {"expandedHeight": 300}}}"#
        XCTAssertEqual(try AppSettings.decode(from: Data(json.utf8)).appearance.layout.expandedHeight, 300)
    }

    func testNotificationSourcesFollowToggles() {
        var settings = NotificationSettings()
        settings.mediaBanners = false
        settings.focusBanners = false
        XCTAssertFalse(settings.enabledSources.contains(.media))
        XCTAssertFalse(settings.enabledSources.contains(.focus))
        XCTAssertTrue(settings.enabledSources.contains(.app))
        XCTAssertTrue(settings.enabledSources.contains(.developer))
    }
}

final class ThemeConfigurationTests: XCTestCase {
    func testEveryPresetHasDistinctValuesExceptCustom() {
        let builtIn = ThemePreset.allCases.filter { $0 != .custom }
        let values = builtIn.map(\.values)
        for (index, value) in values.enumerated() {
            for other in values[(index + 1)...] {
                XCTAssertNotEqual(value, other)
            }
        }
    }

    func testActiveThemeUsesPresetUnlessCustom() {
        var appearance = AppearanceSettings()
        appearance.preset = .minimalLight
        appearance.custom.background = .white
        XCTAssertEqual(appearance.activeTheme, ThemePreset.minimalLight.values)

        appearance.preset = .custom
        XCTAssertEqual(appearance.activeTheme.background, .white)
    }

    func testBeginCustomizingSeedsFromCurrentPreset() {
        var appearance = AppearanceSettings()
        appearance.preset = .frostedGlass

        appearance.beginCustomizing()

        XCTAssertEqual(appearance.preset, .custom)
        XCTAssertEqual(appearance.custom, ThemePreset.frostedGlass.values)
    }

    func testBeginCustomizingKeepsExistingCustomValues() {
        var appearance = AppearanceSettings()
        appearance.preset = .custom
        appearance.custom.shadowRadius = 3

        appearance.beginCustomizing()

        XCTAssertEqual(appearance.custom.shadowRadius, 3)
    }

    func testLightPresetUsesDarkText() {
        XCTAssertEqual(ThemePreset.minimalLight.values.foreground, .dark)
        XCTAssertEqual(ThemePreset.midnightBlack.values.foreground, .light)
    }

    func testAnimationDurationScalesWithSpeedAndIsClamped() {
        var animation = AnimationSettings()
        animation.style = .spring
        animation.speed = 1
        let normal = animation.nominalDuration

        animation.speed = 2
        XCTAssertEqual(animation.nominalDuration, normal / 2, accuracy: 0.0001)

        animation.speed = 100
        XCTAssertEqual(animation.nominalDuration, normal / AnimationSettings.speedRange.upperBound, accuracy: 0.0001)
    }
}

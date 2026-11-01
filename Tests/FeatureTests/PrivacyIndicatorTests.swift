@testable import FeaturePrivacyIndicators
import IslandCore
import IslandPlatform
import XCTest

final class CaptureAttributionTests: XCTestCase {
    private let apps = [
        RunningAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome"),
        RunningAppInfo(bundleID: "us.zoom.xos", name: "zoom.us"),
        RunningAppInfo(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
    ]

    func testOnlyClientsRunningInputCount() {
        let clients = [
            AudioClient(pid: 10, bundleID: "us.zoom.xos", isRunningInput: true),
            AudioClient(pid: 11, bundleID: "com.google.Chrome", isRunningInput: false),
        ]
        XCTAssertEqual(CaptureAttribution.microphoneClients(clients, ownPID: 1).map(\.pid), [10])
    }

    func testAlwaysOnSystemListenersAndSelfAreIgnored() {
        let clients = [
            AudioClient(pid: 20, bundleID: "com.apple.CoreSpeech", isRunningInput: true),
            AudioClient(pid: 21, bundleID: "com.apple.accessibility.heard", isRunningInput: true),
            AudioClient(pid: 99, bundleID: "io.github.islandbar.IslandBar", isRunningInput: true),
        ]
        XCTAssertTrue(CaptureAttribution.microphoneClients(clients, ownPID: 99).isEmpty)
    }

    func testHelperProcessesResolveToTheirApp() {
        XCTAssertEqual(CaptureAttribution.owningApp(of: "com.google.Chrome.helper", among: apps)?.name, "Google Chrome")
        XCTAssertEqual(CaptureAttribution.owningApp(of: "us.zoom.xos", among: apps)?.name, "zoom.us")
        // Prefix must end at a dot: "com.google.ChromeX" is not Chrome.
        XCTAssertNil(CaptureAttribution.owningApp(of: "com.google.ChromeX", among: apps))
    }

    func testLongestPrefixWins() {
        let nested = apps + [RunningAppInfo(bundleID: "com.google.Chrome.canary", name: "Chrome Canary")]
        XCTAssertEqual(CaptureAttribution.owningApp(of: "com.google.Chrome.canary.helper", among: nested)?.name, "Chrome Canary")
    }

    func testDisplayNamesAreDeduplicatedAndUseFallbacks() {
        let clients = [
            AudioClient(pid: 1, bundleID: "com.google.Chrome.helper", isRunningInput: true),
            AudioClient(pid: 2, bundleID: "com.google.Chrome.helper", isRunningInput: true),
            AudioClient(pid: 3, bundleID: "com.apple.avconferenced", isRunningInput: true),
            AudioClient(pid: 4, bundleID: nil, isRunningInput: true),
            AudioClient(pid: 5, bundleID: "org.unknown.tool", isRunningInput: true),
        ]
        let names = CaptureAttribution.displayNames(for: clients, apps: apps) { pid in pid == 4 ? "recorder" : nil }
        XCTAssertEqual(names, ["FaceTime", "Google Chrome", "org.unknown.tool", "recorder"])
    }

    func testCompactSummary() {
        var usage = CaptureUsage()
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: true, showMicrophone: true), "")

        usage.cameraInUse = true
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: true, showMicrophone: true), "Camera")

        usage.microphoneInUse = true
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: true, showMicrophone: true), "Cam + Mic")
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: false, showMicrophone: true), "Mic")

        usage.microphoneApps = ["Zoom", "Chrome"]
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: true, showMicrophone: true), "Zoom +1")
        XCTAssertEqual(CaptureAttribution.summary(usage, showCamera: true, showMicrophone: false), "Camera")
    }
}

@MainActor
final class PrivacyIndicatorModuleTests: XCTestCase {
    func testLiveActivityFollowsSettings() {
        let module = PrivacyIndicatorModule(activity: ActivityCenter())
        var settings = AppSettings.defaults
        module.apply(settings)
        XCTAssertNil(module.liveActivityPriority, "nothing in use before activation")

        settings.privacyIndicators.showCamera = false
        settings.privacyIndicators.showMicrophone = false
        XCTAssertFalse(module.isEnabled(in: settings))
    }

    /// Exercises the real CoreAudio and CoreMediaIO queries; they need no permission.
    func testSystemQueriesAnswerWithoutPermission() {
        let audio = AudioInputMonitor()
        let clients = audio.clients()
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)) {
            XCTAssertNotNil(clients, "the audio process list is public on macOS 14.2+")
        }
        _ = audio.anyInputDeviceRunning()
        _ = CameraMonitor().activeCameraNames()

        let module = PrivacyIndicatorModule(activity: ActivityCenter())
        module.apply(.defaults)
        module.activate()
        module.deactivate()
        XCTAssertEqual(module.usage, CaptureUsage())
    }
}

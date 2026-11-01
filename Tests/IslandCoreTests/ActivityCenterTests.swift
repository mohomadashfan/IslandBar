import IslandCore
import XCTest

@MainActor
final class ActivityCenterTests: XCTestCase {
    /// Banners never auto-dismiss, so tests control timing explicitly.
    private func makeCenter() -> ActivityCenter {
        ActivityCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    private func event(_ title: String, source: ActivitySource = .focus) -> ActivityEvent {
        ActivityEvent(source: source, title: title, symbolName: "circle")
    }

    func testFirstEventShowsImmediatelyOthersQueue() {
        let center = makeCenter()
        center.post(event("a"))
        center.post(event("b"))
        center.post(event("c"))

        XCTAssertEqual(center.current?.title, "a")
        XCTAssertEqual(center.pendingCount, 2)

        center.dismissCurrent()
        XCTAssertEqual(center.current?.title, "b")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.title, "c")
        center.dismissCurrent()
        XCTAssertNil(center.current)
    }

    func testHistoryIsNewestFirstAndTrimmed() {
        let center = makeCenter()
        var configuration = ActivityCenter.Configuration()
        configuration.historyLimit = 2
        center.configuration = configuration

        center.post(event("a"))
        center.post(event("b"))
        center.post(event("c"))

        XCTAssertEqual(center.history.map(\.title), ["c", "b"])
    }

    func testDisabledSourceIsRecordedButNotShownOrForwarded() {
        let center = makeCenter()
        var configuration = ActivityCenter.Configuration()
        configuration.enabledSources = [.focus]
        center.configuration = configuration
        var forwarded: [String] = []
        center.onPost = { forwarded.append($0.title) }

        center.post(event("track", source: .media))

        XCTAssertNil(center.current)
        XCTAssertEqual(center.history.map(\.title), ["track"])
        XCTAssertTrue(forwarded.isEmpty)
    }

    func testBannersOffStillForwards() {
        let center = makeCenter()
        var configuration = ActivityCenter.Configuration()
        configuration.bannersEnabled = false
        center.configuration = configuration
        var forwarded = 0
        center.onPost = { _ in forwarded += 1 }

        center.post(event("a"))

        XCTAssertNil(center.current)
        XCTAssertEqual(forwarded, 1)
    }

    func testBannerAutoDismisses() async throws {
        let center = ActivityCenter(sleep: { _ in })
        center.post(event("a"))
        center.post(event("b"))

        for _ in 0..<200 where center.current != nil {
            await Task.yield()
        }
        XCTAssertNil(center.current)
        XCTAssertEqual(center.pendingCount, 0)
    }

    func testConfigurationFromSettings() {
        var settings = NotificationSettings()
        settings.bannerDuration = 2.5
        settings.showBanners = false
        let configuration = ActivityCenter.Configuration(settings)
        XCTAssertEqual(configuration.bannerDuration, .milliseconds(2500))
        XCTAssertFalse(configuration.bannersEnabled)
    }
}

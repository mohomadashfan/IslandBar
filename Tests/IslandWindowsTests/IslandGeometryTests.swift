import CoreGraphics
import IslandCore
@testable import IslandWindows
import XCTest

final class IslandGeometryTests: XCTestCase {
    // Values captured from a 14" MacBook Pro at default scaling.
    private let builtInFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let leftArea = CGRect(x: 0, y: 1085, width: 771.5, height: 32)
    private let rightArea = CGRect(x: 956.5, y: 1085, width: 771.5, height: 32)

    private func display(
        frame: CGRect, notch: CGRect? = nil, builtIn: Bool = false, menuBar: CGFloat = 24, id: String = "D"
    ) -> DisplayDescriptor {
        DisplayDescriptor(
            id: DisplayID(rawValue: id), directDisplayID: 1, name: id, isBuiltIn: builtIn,
            frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 0), notchRect: notch, menuBarHeight: menuBar
        )
    }

    // MARK: Notch detection

    func testNotchFromAuxiliaryAreas() throws {
        let notch = try XCTUnwrap(IslandGeometry.notchRect(
            screenFrame: builtInFrame, safeAreaTop: 32, leftArea: leftArea, rightArea: rightArea
        ))
        XCTAssertEqual(notch, CGRect(x: 771.5, y: 1085, width: 185, height: 32))
    }

    func testNoNotchWithoutSafeArea() {
        XCTAssertNil(IslandGeometry.notchRect(screenFrame: builtInFrame, safeAreaTop: 0, leftArea: leftArea, rightArea: rightArea))
        XCTAssertNil(IslandGeometry.notchRect(screenFrame: builtInFrame, safeAreaTop: 32, leftArea: .zero, rightArea: .zero))
    }

    func testNotchOnSecondaryScreenWithLocalCoordinates() throws {
        // The same panel arranged to the right of another display.
        let frame = builtInFrame.offsetBy(dx: 2560, dy: 0)
        let notch = try XCTUnwrap(IslandGeometry.notchRect(
            screenFrame: frame, safeAreaTop: 32, leftArea: leftArea, rightArea: rightArea
        ))
        XCTAssertEqual(notch.minX, 2560 + 771.5)
        XCTAssertEqual(notch.width, 185)
    }

    func testNotchOnSecondaryScreenWithGlobalCoordinates() throws {
        let frame = builtInFrame.offsetBy(dx: 2560, dy: 0)
        let notch = try XCTUnwrap(IslandGeometry.notchRect(
            screenFrame: frame, safeAreaTop: 32,
            leftArea: leftArea.offsetBy(dx: 2560, dy: 0), rightArea: rightArea.offsetBy(dx: 2560, dy: 0)
        ))
        XCTAssertEqual(notch.minX, 2560 + 771.5)
    }

    func testMenuBarHeightFallsBackWhenHidden() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(IslandGeometry.menuBarHeight(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415), safeAreaTop: 0), 25)
        XCTAssertEqual(IslandGeometry.menuBarHeight(frame: frame, visibleFrame: frame, safeAreaTop: 0), IslandGeometry.fallbackMenuBarHeight)
        XCTAssertEqual(IslandGeometry.menuBarHeight(frame: frame, visibleFrame: frame, safeAreaTop: 32), 32)
    }

    // MARK: Anchors

    func testAnchorCentersOnNotch() {
        let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let anchor = IslandGeometry.anchor(for: display(frame: builtInFrame, notch: notch), settings: DisplaySettings())
        XCTAssertEqual(anchor, IslandAnchor(topCenter: CGPoint(x: 864, y: 1117), isAttachedToTop: true))
    }

    func testNotchIgnoresVirtualOffsets() {
        var settings = DisplaySettings()
        settings.horizontalOffset = 300
        settings.virtualIslandStyle = .floating
        let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let anchor = IslandGeometry.anchor(for: display(frame: builtInFrame, notch: notch), settings: settings)
        XCTAssertEqual(anchor.topCenter.x, 864)
        XCTAssertTrue(anchor.isAttachedToTop)
    }

    func testVirtualAnchorAttachedAndOffset() {
        var settings = DisplaySettings()
        settings.horizontalOffset = -100
        let external = display(frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440))
        let anchor = IslandGeometry.anchor(for: external, settings: settings)
        XCTAssertEqual(anchor.topCenter, CGPoint(x: 1728 + 1280 - 100, y: 1440))
        XCTAssertTrue(anchor.isAttachedToTop)
    }

    func testFloatingAnchorSitsBelowMenuBar() {
        var settings = DisplaySettings()
        settings.virtualIslandStyle = .floating
        settings.verticalOffset = 10
        let external = display(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), menuBar: 25)
        let anchor = IslandGeometry.anchor(for: external, settings: settings)
        XCTAssertEqual(anchor.topCenter.y, 1080 - 25 - IslandGeometry.floatingGap - 10)
        XCTAssertFalse(anchor.isAttachedToTop)
    }

    // MARK: Window frames

    func testWindowFrameAttachedHasNoTopMargin() {
        let anchor = IslandAnchor(topCenter: CGPoint(x: 864, y: 1117), isAttachedToTop: true)
        let frame = IslandGeometry.windowFrame(anchor: anchor, islandSize: CGSize(width: 185, height: 32), margin: 4, screenFrame: builtInFrame)
        XCTAssertEqual(frame.maxY, 1117)
        XCTAssertEqual(frame.height, 36)
        XCTAssertEqual(frame.width, 193)
        XCTAssertEqual(frame.midX, 864, accuracy: 0.5)
    }

    func testWindowFrameFloatingHasTopMargin() {
        let anchor = IslandAnchor(topCenter: CGPoint(x: 500, y: 1000), isAttachedToTop: false)
        let frame = IslandGeometry.windowFrame(anchor: anchor, islandSize: CGSize(width: 200, height: 30), margin: 10, screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 1100))
        XCTAssertEqual(frame.maxY, 1010)
        XCTAssertEqual(frame.height, 50)
    }

    func testWindowFrameIsClampedInsideScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = IslandAnchor(topCenter: CGPoint(x: 950, y: 800), isAttachedToTop: true)
        let frame = IslandGeometry.windowFrame(anchor: anchor, islandSize: CGSize(width: 400, height: 200), margin: 20, screenFrame: screen)
        XCTAssertEqual(frame.maxX, 1000)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
    }

    func testWindowFrameWiderThanScreenCentres() {
        let screen = CGRect(x: 100, y: 0, width: 300, height: 800)
        let anchor = IslandAnchor(topCenter: CGPoint(x: 120, y: 800), isAttachedToTop: true)
        let frame = IslandGeometry.windowFrame(anchor: anchor, islandSize: CGSize(width: 400, height: 100), margin: 0, screenFrame: screen)
        XCTAssertEqual(frame.midX, screen.midX)
    }

    // MARK: Sizes

    func testIdleIslandMatchesNotchExactly() {
        let size = IslandGeometry.islandSize(mode: .idle, notchSize: CGSize(width: 185, height: 32), layout: LayoutSettings())
        XCTAssertEqual(size, CGSize(width: 185, height: 32))
    }

    func testLiveActivityAddsWings() {
        var layout = LayoutSettings()
        layout.wingWidth = 70
        let notched = IslandGeometry.islandSize(mode: .liveActivity, notchSize: CGSize(width: 185, height: 32), layout: layout)
        XCTAssertEqual(notched, CGSize(width: 325, height: 32))

        let virtual = IslandGeometry.islandSize(mode: .liveActivity, notchSize: nil, layout: layout)
        XCTAssertEqual(virtual.height, CGFloat(layout.virtualHeight))
        XCTAssertGreaterThanOrEqual(virtual.width, 180)
    }

    func testExpandedUsesConfiguredSizeButNeverNarrowerThanCompact() {
        var layout = LayoutSettings()
        layout.expandedWidth = 360
        layout.expandedHeight = 150
        layout.wingWidth = 120
        let size = IslandGeometry.islandSize(mode: .expanded, notchSize: CGSize(width: 185, height: 32), layout: layout)
        XCTAssertEqual(size.width, 185 + 240)
        XCTAssertEqual(size.height, 150)
    }

    func testModesGrowMonotonically() {
        let notch = CGSize(width: 185, height: 32)
        let layout = LayoutSettings()
        let idle = IslandGeometry.islandSize(mode: .idle, notchSize: notch, layout: layout)
        let live = IslandGeometry.islandSize(mode: .liveActivity, notchSize: notch, layout: layout)
        let banner = IslandGeometry.islandSize(mode: .banner, notchSize: notch, layout: layout)
        let expanded = IslandGeometry.islandSize(mode: .expanded, notchSize: notch, layout: layout)
        XCTAssertLessThanOrEqual(idle.width, live.width)
        XCTAssertLessThanOrEqual(live.height, banner.height)
        XCTAssertLessThanOrEqual(banner.height, expanded.height)
    }

    // MARK: Display selection

    func testDisplaySelectionDefaultsAndOverrides() {
        let builtIn = display(frame: builtInFrame, builtIn: true, id: "builtin")
        let externalA = display(frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440), id: "A")
        let externalB = display(frame: CGRect(x: 4288, y: 0, width: 1920, height: 1080), id: "B")
        let all = [builtIn, externalA, externalB]

        var settings = DisplaySettings()
        XCTAssertEqual(DisplaySelection.enabledDisplays(all, settings: settings).map(\.id.rawValue), ["builtin", "A", "B"])

        settings.showOnExternalDisplays = false
        XCTAssertEqual(DisplaySelection.enabledDisplays(all, settings: settings).map(\.id.rawValue), ["builtin"])

        settings.overrides["B"] = true
        settings.overrides["builtin"] = false
        XCTAssertEqual(DisplaySelection.enabledDisplays(all, settings: settings).map(\.id.rawValue), ["B"])
    }
}


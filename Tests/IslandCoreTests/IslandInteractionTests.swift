import IslandCore
import XCTest

final class IslandInteractionTests: XCTestCase {
    private let policy = IslandInteractionPolicy()

    private func reduce(_ state: IslandPresentation, _ events: IslandEvent..., policy: IslandInteractionPolicy? = nil) -> IslandPresentation {
        events.reduce(state) { IslandInteraction.reduce($0, $1, policy: policy ?? self.policy) }
    }

    func testHoverExpandsAndExitCollapses() {
        XCTAssertEqual(reduce(.compact, .pointerEntered), .expanded(.hover))
        XCTAssertEqual(reduce(.compact, .pointerEntered, .pointerExited), .compact)
    }

    func testHoverDisabledKeepsCompact() {
        let noHover = IslandInteractionPolicy(expandOnHover: false)
        XCTAssertEqual(reduce(.compact, .pointerEntered, policy: noHover), .compact)
        XCTAssertEqual(reduce(.compact, .clicked, policy: noHover), .expanded(.click))
    }

    func testClickPinsHoverExpansion() {
        let pinned = reduce(.compact, .pointerEntered, .clicked)
        XCTAssertEqual(pinned, .expanded(.click))
        XCTAssertEqual(reduce(pinned, .pointerExited), .expanded(.click))
    }

    func testEscapeAlwaysCollapses() {
        for reason in [ExpansionReason.hover, .click, .shortcut, .drag] {
            XCTAssertEqual(reduce(.expanded(reason), .escapePressed), .compact, "\(reason)")
        }
        XCTAssertEqual(reduce(.compact, .escapePressed), .compact)
    }

    func testShortcutToggles() {
        XCTAssertEqual(reduce(.compact, .shortcutPressed), .expanded(.shortcut))
        XCTAssertEqual(reduce(.compact, .shortcutPressed, .shortcutPressed), .compact)
        XCTAssertEqual(reduce(.expanded(.hover), .shortcutPressed), .compact)
    }

    func testClickOutsideRespectsPolicy() {
        XCTAssertEqual(reduce(.expanded(.click), .clickedOutside), .compact)
        let sticky = IslandInteractionPolicy(collapseOnClickOutside: false)
        XCTAssertEqual(reduce(.expanded(.click), .clickedOutside, policy: sticky), .expanded(.click))
        // Hover expansion always yields to a click elsewhere.
        XCTAssertEqual(reduce(.expanded(.hover), .clickedOutside, policy: sticky), .compact)
    }

    func testDragOpensAndDropKeepsOpenUntilExit() {
        XCTAssertEqual(reduce(.compact, .dragEntered), .expanded(.drag))
        XCTAssertEqual(reduce(.compact, .dragEntered, .dragExited), .compact)
        XCTAssertEqual(reduce(.compact, .dragEntered, .pointerExited), .expanded(.drag))
        let dropped = reduce(.compact, .dragEntered, .dropCompleted)
        XCTAssertEqual(dropped, .expanded(.hover))
        XCTAssertEqual(reduce(dropped, .pointerExited), .compact)
    }

    func testDragOverPinnedIslandKeepsReason() {
        XCTAssertEqual(reduce(.expanded(.click), .dragEntered, .dragExited), .expanded(.click))
    }

    func testCompactIgnoresStrayEvents() {
        for event in [IslandEvent.pointerExited, .clickedOutside, .dragExited, .dropCompleted] {
            XCTAssertEqual(reduce(.compact, event), .compact, "\(event)")
        }
    }

    func testKeyboardFocusOnlyForDeliberateExpansion() {
        XCTAssertTrue(IslandPresentation.expanded(.click).wantsKeyboardFocus)
        XCTAssertTrue(IslandPresentation.expanded(.shortcut).wantsKeyboardFocus)
        XCTAssertFalse(IslandPresentation.expanded(.hover).wantsKeyboardFocus)
        XCTAssertFalse(IslandPresentation.expanded(.drag).wantsKeyboardFocus)
        XCTAssertFalse(IslandPresentation.compact.wantsKeyboardFocus)
    }
}

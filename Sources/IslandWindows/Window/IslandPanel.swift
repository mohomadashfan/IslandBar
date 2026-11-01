import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel that floats above the menu bar.
///
/// It can become key (for Escape and text input) without activating IslandBar, so the user's
/// frontmost app keeps its active state.
final class IslandPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        setShowsInFullScreenApps(false)
    }

    func setShowsInFullScreenApps(_ show: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if show {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Reached when Escape is pressed while a text field has focus.
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Hosting view that reports hover with an always-active tracking area (SwiftUI's own hover
/// tracking only works while the app is active, which a menu-bar utility never is) and accepts
/// the first click without requiring activation.
final class IslandHostingView: NSHostingView<AnyView> {
    var onHoverChange: ((Bool) -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

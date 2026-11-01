import CoreGraphics
import IslandCore

/// What the island is currently showing; determines its size.
public enum IslandContentMode: Sendable, Equatable {
    case idle
    case liveActivity
    case banner
    case expanded
}

/// Where the island hangs from: the midpoint of its top edge, in global coordinates.
public struct IslandAnchor: Sendable, Equatable {
    public var topCenter: CGPoint
    /// True when the island is flush with the top of the screen (real or virtual notch).
    public var isAttachedToTop: Bool

    public init(topCenter: CGPoint, isAttachedToTop: Bool) {
        self.topCenter = topCenter
        self.isAttachedToTop = isAttachedToTop
    }
}

/// Pure layout maths. Nothing here touches AppKit, so it is fully unit-testable.
public enum IslandGeometry {
    public static let fallbackMenuBarHeight: CGFloat = 24
    public static let floatingGap: CGFloat = 6

    /// Derives the notch from the unobscured areas either side of it.
    ///
    /// `leftArea`/`rightArea` are `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. They are
    /// accepted in either global or screen-local coordinates and normalised here.
    public static func notchRect(
        screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect, rightArea: CGRect
    ) -> CGRect? {
        guard safeAreaTop > 0, !leftArea.isEmpty, !rightArea.isEmpty else { return nil }

        let isGlobal = leftArea.minX >= screenFrame.minX - 0.5
            && rightArea.maxX <= screenFrame.maxX + 0.5
            && leftArea.minY >= screenFrame.minY - 0.5
        let dx = isGlobal ? 0 : screenFrame.minX
        let minX = leftArea.maxX + dx
        let maxX = rightArea.minX + dx
        guard maxX > minX else { return nil }

        return CGRect(x: minX, y: screenFrame.maxY - safeAreaTop, width: maxX - minX, height: safeAreaTop)
    }

    /// Height of the menu bar strip, falling back sensibly when the menu bar auto-hides.
    public static func menuBarHeight(
        frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat
    ) -> CGFloat {
        let measured = frame.maxY - visibleFrame.maxY
        if measured > 0 { return measured }
        return max(safeAreaTop, fallbackMenuBarHeight)
    }

    public static func anchor(for display: DisplayDescriptor, settings: DisplaySettings) -> IslandAnchor {
        if let notch = display.notchRect {
            return IslandAnchor(topCenter: CGPoint(x: notch.midX, y: display.frame.maxY), isAttachedToTop: true)
        }
        let x = display.frame.midX + settings.horizontalOffset
        switch settings.virtualIslandStyle {
        case .attachedToTop:
            return IslandAnchor(topCenter: CGPoint(x: x, y: display.frame.maxY), isAttachedToTop: true)
        case .floating:
            let y = display.frame.maxY - display.menuBarHeight - floatingGap - max(settings.verticalOffset, 0)
            return IslandAnchor(topCenter: CGPoint(x: x, y: y), isAttachedToTop: false)
        }
    }

    /// The panel frame for an island of `islandSize`, with `margin` of transparent room for the
    /// shadow. The island is kept horizontally inside the screen.
    public static func windowFrame(
        anchor: IslandAnchor, islandSize: CGSize, margin: CGFloat, screenFrame: CGRect
    ) -> CGRect {
        let width = islandSize.width + margin * 2
        let topMargin = anchor.isAttachedToTop ? 0 : margin
        let height = islandSize.height + margin + topMargin

        let halfWidth = width / 2
        let lower = screenFrame.minX + halfWidth
        let upper = screenFrame.maxX - halfWidth
        let centerX = lower <= upper ? min(max(anchor.topCenter.x, lower), upper) : screenFrame.midX

        return CGRect(
            x: (centerX - halfWidth).rounded(),
            y: (anchor.topCenter.y + topMargin - height).rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// Island size for a content mode. On notched displays the compact island exactly covers the
    /// notch, so idle IslandBar is visually indistinguishable from the hardware.
    public static func islandSize(
        mode: IslandContentMode, notchSize: CGSize?, layout: LayoutSettings
    ) -> CGSize {
        let compactHeight = notchSize?.height ?? CGFloat(layout.virtualHeight)
        let baseWidth = notchSize?.width ?? CGFloat(layout.virtualWidth)
        let wing = CGFloat(max(layout.wingWidth, 0))
        let expandedWidth = CGFloat(layout.expandedWidth)
        let expandedHeight = CGFloat(layout.expandedHeight)

        switch mode {
        case .idle:
            return CGSize(width: baseWidth, height: compactHeight)
        case .liveActivity:
            let width = notchSize == nil ? max(baseWidth, wing * 2 + 40) : baseWidth + wing * 2
            return CGSize(width: width, height: compactHeight)
        case .banner:
            return CGSize(width: max(baseWidth + wing * 2, 360), height: compactHeight + 52)
        case .expanded:
            return CGSize(
                width: max(expandedWidth, baseWidth + wing * 2),
                height: max(expandedHeight, compactHeight + 110)
            )
        }
    }
}

public enum DisplaySelection {
    /// Displays the island should appear on. Per-display overrides win over the general flags.
    public static func enabledDisplays(
        _ displays: [DisplayDescriptor], settings: DisplaySettings
    ) -> [DisplayDescriptor] {
        displays.filter { isEnabled($0, settings: settings) }
    }

    public static func isEnabled(_ display: DisplayDescriptor, settings: DisplaySettings) -> Bool {
        if let override = settings.overrides[display.id.rawValue] {
            return override
        }
        return display.isBuiltIn ? settings.showOnBuiltInDisplay : settings.showOnExternalDisplays
    }
}

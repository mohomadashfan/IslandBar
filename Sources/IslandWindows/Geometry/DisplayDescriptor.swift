import CoreGraphics
import Foundation

/// Stable identifier for a display across reconnects and reboots (the CoreGraphics display UUID).
public struct DisplayID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A value snapshot of a screen. `NSScreen` objects are never retained, so a disconnected
/// display cannot be kept alive by IslandBar.
public struct DisplayDescriptor: Identifiable, Sendable, Equatable {
    public var id: DisplayID
    public var directDisplayID: CGDirectDisplayID
    public var name: String
    public var isBuiltIn: Bool
    /// Global AppKit coordinates (origin bottom-left of the primary display).
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// The physical camera housing, in global coordinates, if this display has one.
    public var notchRect: CGRect?
    public var menuBarHeight: CGFloat
    public var backingScale: CGFloat

    public init(
        id: DisplayID, directDisplayID: CGDirectDisplayID, name: String, isBuiltIn: Bool,
        frame: CGRect, visibleFrame: CGRect, notchRect: CGRect?, menuBarHeight: CGFloat,
        backingScale: CGFloat = 2
    ) {
        self.id = id
        self.directDisplayID = directDisplayID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.notchRect = notchRect
        self.menuBarHeight = menuBarHeight
        self.backingScale = backingScale
    }

    public var hasNotch: Bool { notchRect != nil }
}

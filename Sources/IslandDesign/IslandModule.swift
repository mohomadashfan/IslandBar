import IslandCore
import SwiftUI

/// A feature that contributes UI to the island.
///
/// Implementations are `@Observable`, so the island re-renders automatically whenever state read
/// by these members changes.
@MainActor
public protocol IslandModule: IslandFeature {
    /// SF Symbol shown in the expanded island's module switcher.
    var symbolName: String { get }

    /// When non-nil the module wants the compact island; the highest value wins.
    var liveActivityPriority: Int? { get }

    func isEnabled(in settings: AppSettings) -> Bool

    /// Called on launch and whenever settings change.
    func apply(_ settings: AppSettings)

    func makeCompactLeading() -> AnyView
    func makeCompactTrailing() -> AnyView
    func makeExpandedView() -> AnyView

    /// Whether the module has a page in the expanded island's switcher.
    var hasPage: Bool { get }

    /// A small control shown in the expanded island's header, next to Settings.
    func makeHeaderAccessory() -> AnyView?
}

extension IslandModule {
    public var liveActivityPriority: Int? { nil }

    public func makeCompactLeading() -> AnyView { AnyView(EmptyView()) }
    public func makeCompactTrailing() -> AnyView { AnyView(EmptyView()) }
    public var hasPage: Bool { true }
    public func makeHeaderAccessory() -> AnyView? { nil }
}

/// A module that accepts files dropped anywhere on the island.
@MainActor
public protocol IslandDropTarget: AnyObject {
    /// Returns `false` if none of the providers can be handled.
    func acceptDrop(of providers: [NSItemProvider]) -> Bool
}

extension EnvironmentValues {
    /// True while a drag is hovering over the island.
    @Entry public var islandIsDropTargeted = false
}

/// Conventional priorities so modules agree on who gets the compact island.
public enum LiveActivityPriority {
    /// Camera or microphone in use outranks everything else.
    public static let privacy = 50
    public static let focus = 40
    public static let developer = 30
    public static let media = 20
    public static let systemIndicator = 10
    public static let caffeinate = 5
}

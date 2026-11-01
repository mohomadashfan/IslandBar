import IslandCore
import IslandDesign
import IslandWindows
import Observation
import SwiftUI

/// Decides what every island shows and how big it is. Shared by all displays; per-display state
/// lives in `IslandViewModel`.
@MainActor
@Observable
final class IslandPresenter {
    let settings: SettingsStore
    let activity: ActivityCenter
    let registry: FeatureRegistry
    let modules: [any IslandModule]

    @ObservationIgnored var openSettings: () -> Void = {}

    /// Asks every island to show a particular page (e.g. from the menu bar or a debug hook).
    private(set) var pageRequest: (id: FeatureID, token: UUID)?

    func requestPage(_ id: FeatureID) {
        pageRequest = (id, UUID())
    }

    init(settings: SettingsStore, activity: ActivityCenter, registry: FeatureRegistry, modules: [any IslandModule]) {
        self.settings = settings
        self.activity = activity
        self.registry = registry
        self.modules = modules
    }

    /// Modules with a page in the expanded island.
    var visibleModules: [any IslandModule] {
        modules.filter { module in
            guard registry.isActive(module.id), module.hasPage else { return false }
            if module.id == .notifications {
                return settings.settings.notifications.showHistoryTab
            }
            return true
        }
    }

    /// The module that owns the compact island, if any.
    var liveModule: (any IslandModule)? {
        var best: (module: any IslandModule, priority: Int)?
        for module in modules where registry.isActive(module.id) {
            if let priority = module.liveActivityPriority, priority > (best?.priority ?? .min) {
                best = (module, priority)
            }
        }
        return best?.module
    }

    /// Header controls contributed by active modules (e.g. Keep Awake).
    var headerAccessories: [(id: FeatureID, view: AnyView)] {
        modules.compactMap { module in
            guard registry.isActive(module.id), let view = module.makeHeaderAccessory() else { return nil }
            return (module.id, view)
        }
    }

    var dropTarget: (any IslandDropTarget)? {
        for module in modules where registry.isActive(module.id) {
            if let target = module as? any IslandDropTarget { return target }
        }
        return nil
    }

    func contentMode(for model: IslandViewModel) -> IslandContentMode {
        if model.presentation.isExpanded { return .expanded }
        if activity.current != nil { return .banner }
        if liveModule != nil { return .liveActivity }
        return .idle
    }

    func frameRequest(for model: IslandViewModel) -> IslandFrameRequest {
        let mode = contentMode(for: model)
        let size = IslandGeometry.islandSize(
            mode: mode,
            notchSize: model.display.notchRect?.size,
            layout: settings.settings.appearance.layout
        )
        let shadow = CGFloat(settings.settings.appearance.activeTheme.shadowRadius)
        let margin: CGFloat = (mode == .expanded || mode == .banner) ? shadow + 10 : 4
        return IslandFrameRequest(size: size, shadowMargin: margin)
    }

    func featureID(for source: ActivitySource) -> FeatureID? {
        switch source {
        case .focus: .focus
        case .shelf: .shelf
        case .developer: .developer
        case .media: .media
        case .system: .systemMonitor
        case .privacy: .privacyIndicators
        case .devices: .bluetooth
        case .app: .notifications
        }
    }
}

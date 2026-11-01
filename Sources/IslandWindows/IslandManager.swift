import AppKit
import IslandCore
import Observation

/// Keeps one island window per enabled display, reacting to display changes and settings.
@MainActor
@Observable
public final class IslandManager {
    public let displayMonitor: DisplayMonitor
    public private(set) var models: [IslandViewModel] = []

    @ObservationIgnored private var controllers: [DisplayID: IslandWindowController] = [:]
    @ObservationIgnored private let makeRootView: IslandRootViewFactory
    @ObservationIgnored private let frameProvider: IslandFrameProvider
    @ObservationIgnored private var configuration: IslandWindowConfiguration
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private var isRunning = false

    public init(
        displayMonitor: DisplayMonitor = DisplayMonitor(),
        configuration: IslandWindowConfiguration,
        makeRootView: @escaping IslandRootViewFactory,
        frameProvider: @escaping IslandFrameProvider
    ) {
        self.displayMonitor = displayMonitor
        self.configuration = configuration
        self.makeRootView = makeRootView
        self.frameProvider = frameProvider
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        displayMonitor.start()
        observeDisplays()
        installClickOutsideMonitor()
        reconcile()
    }

    public func stop() {
        isRunning = false
        displayMonitor.stop()
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
        models.removeAll()
    }

    public func apply(_ configuration: IslandWindowConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        for controller in controllers.values {
            controller.apply(configuration)
        }
        reconcile()
    }

    /// Toggles the island on the display under the pointer, falling back to the first one.
    public func toggleOnActiveDisplay() {
        let pointer = NSEvent.mouseLocation
        let target = models.first { $0.display.frame.contains(pointer) } ?? models.first
        target?.toggle()
    }

    public func collapseAll() {
        for model in models {
            model.collapse()
        }
    }

    // MARK: - Private

    private func observeDisplays() {
        withObservationTracking {
            _ = displayMonitor.displays
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.reconcile()
                self.observeDisplays()
            }
        }
    }

    private func reconcile() {
        guard isRunning else { return }
        let wanted = configuration.isEnabled
            ? DisplaySelection.enabledDisplays(displayMonitor.displays, settings: configuration.displays)
            : []
        let wantedIDs = Set(wanted.map(\.id))

        for (id, controller) in controllers where !wantedIDs.contains(id) {
            controller.close()
            controllers[id] = nil
        }
        for display in wanted {
            if let controller = controllers[display.id] {
                controller.update(display: display)
            } else {
                controllers[display.id] = IslandWindowController(
                    display: display,
                    configuration: configuration,
                    makeRootView: makeRootView,
                    frameProvider: frameProvider
                )
            }
        }

        let ordered = wanted.compactMap { controllers[$0.id]?.model }
        if ordered.map(\.displayID) != models.map(\.displayID) {
            models = ordered
        }
    }

    /// Global mouse-down monitors only see clicks delivered to other applications, which is
    /// exactly "outside the island". Monitoring mouse clicks needs no special permission.
    private func installClickOutsideMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for model in self.models where model.presentation.isExpanded {
                    model.send(.clickedOutside)
                }
            }
        }
    }
}

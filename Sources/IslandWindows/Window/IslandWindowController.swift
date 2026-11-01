import AppKit
import IslandCore
import Observation
import SwiftUI

/// Window-level configuration derived from settings.
public struct IslandWindowConfiguration: Sendable, Equatable {
    public var isEnabled = true
    public var displays = DisplaySettings()
    public var policy = IslandInteractionPolicy()
    public var hoverDelay = 0.15
    public var collapseDelay = 0.35
    /// How long the SwiftUI collapse animation runs; the window shrinks once it finishes.
    public var animationDuration = 0.45
    public var hapticFeedback = true
    public var showInFullScreenApps = false
    public var hideFromScreenCapture = true

    public init() {}

    public init(settings: AppSettings) {
        isEnabled = settings.general.isIslandEnabled
        displays = settings.displays
        policy = IslandInteractionPolicy(settings.general)
        hoverDelay = settings.general.hoverDelay
        collapseDelay = settings.general.collapseDelay
        animationDuration = settings.animation.nominalDuration
        hapticFeedback = settings.general.hapticFeedback
        showInFullScreenApps = settings.general.showInFullScreenApps
        hideFromScreenCapture = settings.general.hideFromScreenCapture
    }
}

/// The size the content wants and how much transparent room its shadow needs.
public struct IslandFrameRequest: Sendable, Equatable {
    public var size: CGSize
    public var shadowMargin: CGFloat

    public init(size: CGSize, shadowMargin: CGFloat) {
        self.size = size
        self.shadowMargin = shadowMargin
    }
}

public typealias IslandRootViewFactory = @MainActor (IslandViewModel) -> AnyView
public typealias IslandFrameProvider = @MainActor (IslandViewModel) -> IslandFrameRequest

/// Owns one panel on one display and keeps its frame in sync with what the content needs.
///
/// Growing happens immediately, before SwiftUI animates the island outward; shrinking waits until
/// the collapse animation has finished. The panel is therefore only as large as necessary and
/// never blocks clicks on the menu bar while the island is compact.
@MainActor
final class IslandWindowController {
    let model: IslandViewModel
    private let panel = IslandPanel()
    private let frameProvider: IslandFrameProvider
    private var configuration: IslandWindowConfiguration
    private var resizeGeneration = 0
    private var isClosed = false

    init(
        display: DisplayDescriptor,
        configuration: IslandWindowConfiguration,
        makeRootView: IslandRootViewFactory,
        frameProvider: @escaping IslandFrameProvider
    ) {
        self.model = IslandViewModel(display: display)
        self.configuration = configuration
        self.frameProvider = frameProvider

        let hostingView = IslandHostingView(rootView: makeRootView(model))
        panel.contentView = hostingView

        hostingView.onHoverChange = { [weak model] inside in
            inside ? model?.pointerEntered() : model?.pointerExited()
        }
        panel.onEscape = { [weak model] in
            model?.send(.escapePressed)
        }
        model.onPresentationChange = { [weak self] old, new in
            self?.presentationChanged(from: old, to: new)
        }
        model.pointerLocator = { [weak panel] in
            guard let panel else { return false }
            return panel.frame.contains(NSEvent.mouseLocation)
        }

        apply(configuration)
        layout(animated: false)
        panel.orderFrontRegardless()
        observeFrameRequest()
    }

    var panelFrame: CGRect { panel.frame }

    func apply(_ configuration: IslandWindowConfiguration) {
        self.configuration = configuration
        model.policy = configuration.policy
        model.hoverDelay = .milliseconds(Int(configuration.hoverDelay * 1000))
        model.collapseDelay = .milliseconds(Int(configuration.collapseDelay * 1000))
        panel.setShowsInFullScreenApps(configuration.showInFullScreenApps)
        panel.sharingType = configuration.hideFromScreenCapture ? .none : .readOnly
        layout(animated: false)
    }

    func update(display: DisplayDescriptor) {
        guard display != model.display else { return }
        model.display = display
        layout(animated: false)
    }

    func close() {
        isClosed = true
        resizeGeneration += 1
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Layout

    private func observeFrameRequest() {
        withObservationTracking {
            _ = frameProvider(model)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                self.layout(animated: true)
                self.observeFrameRequest()
            }
        }
    }

    private func targetFrame() -> CGRect {
        let request = frameProvider(model)
        let anchor = IslandGeometry.anchor(for: model.display, settings: configuration.displays)
        return IslandGeometry.windowFrame(
            anchor: anchor,
            islandSize: request.size,
            margin: request.shadowMargin,
            screenFrame: model.display.frame
        )
    }

    private func layout(animated: Bool) {
        let target = targetFrame()
        resizeGeneration += 1
        let generation = resizeGeneration
        let current = panel.frame

        guard animated, !current.isEmpty, current != target else {
            panel.setFrame(target, display: true)
            return
        }

        let grown = current.union(target)
        if grown != current {
            panel.setFrame(grown, display: true)
        }
        guard grown != target else { return }

        let delay = configuration.animationDuration + 0.05
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard let self, !self.isClosed, generation == self.resizeGeneration else { return }
            self.panel.setFrame(self.targetFrame(), display: true)
        }
    }

    // MARK: - Focus and feedback

    private func presentationChanged(from old: IslandPresentation, to new: IslandPresentation) {
        if new.isExpanded, !old.isExpanded, configuration.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        if new.wantsKeyboardFocus {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Hand keyboard focus back to the app the user was in. Re-ordering the panel is the
            // supported way to give up key status without activating anything else.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}

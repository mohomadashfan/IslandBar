import Foundation
import IslandCore
import Observation

/// Per-display interaction state. Turns raw pointer/drag signals into `IslandEvent`s, applying
/// hover and collapse delays, and runs them through `IslandInteraction`.
@MainActor
@Observable
public final class IslandViewModel {
    public let displayID: DisplayID
    public internal(set) var display: DisplayDescriptor
    public private(set) var presentation: IslandPresentation = .compact
    public private(set) var isPointerInside = false
    public private(set) var isDragTargeted = false

    @ObservationIgnored public var policy = IslandInteractionPolicy()
    @ObservationIgnored public var hoverDelay: Duration = .milliseconds(150)
    @ObservationIgnored public var collapseDelay: Duration = .milliseconds(350)
    @ObservationIgnored var onPresentationChange: ((IslandPresentation, IslandPresentation) -> Void)?
    /// Asks the window whether the pointer is actually over it; used after drag-and-drop,
    /// when AppKit does not deliver enter/exit events.
    @ObservationIgnored var pointerLocator: (() -> Bool)?

    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    init(display: DisplayDescriptor) {
        self.displayID = display.id
        self.display = display
    }

    public func send(_ event: IslandEvent) {
        let next = IslandInteraction.reduce(presentation, event, policy: policy)
        guard next != presentation else { return }
        if !next.isExpanded {
            pendingTask?.cancel()
        }
        let previous = presentation
        presentation = next
        onPresentationChange?(previous, next)
        if event == .dropCompleted {
            watchPointerAfterDrop()
        }
    }

    public func toggle() {
        send(.shortcutPressed)
    }

    public func collapse() {
        send(.escapePressed)
    }

    func pointerEntered() {
        isPointerInside = true
        pendingTask?.cancel()
        guard presentation == .compact, policy.expandOnHover else { return }
        schedule(after: hoverDelay) { model in
            if model.isPointerInside { model.send(.pointerEntered) }
        }
    }

    func pointerExited() {
        isPointerInside = false
        pendingTask?.cancel()
        guard presentation == .expanded(.hover) else { return }
        schedule(after: collapseDelay) { model in
            if !model.isPointerInside { model.send(.pointerExited) }
        }
    }

    public func setDragTargeted(_ targeted: Bool) {
        guard targeted != isDragTargeted else { return }
        isDragTargeted = targeted
        pendingTask?.cancel()
        if targeted {
            send(.dragEntered)
        } else {
            schedule(after: collapseDelay) { model in
                if !model.isDragTargeted { model.send(.dragExited) }
            }
        }
    }

    private func watchPointerAfterDrop() {
        schedule(after: collapseDelay) { model in
            while model.presentation == .expanded(.hover) {
                if model.isPointerInside == false, model.pointerLocator?() == false {
                    model.send(.pointerExited)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
        }
    }

    private func schedule(after delay: Duration, _ work: @escaping @MainActor (IslandViewModel) async -> Void) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await work(self)
        }
    }
}

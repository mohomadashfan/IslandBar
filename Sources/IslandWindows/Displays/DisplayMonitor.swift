import AppKit
import Observation

extension DisplayDescriptor {
    @MainActor
    init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let directID = CGDirectDisplayID(number.uint32Value)
        let uuid = CGDisplayCreateUUIDFromDisplayID(directID)
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            ?? "display-\(directID)"

        let safeTop = screen.safeAreaInsets.top
        self.init(
            id: DisplayID(rawValue: uuid),
            directDisplayID: directID,
            name: screen.localizedName,
            isBuiltIn: CGDisplayIsBuiltin(directID) != 0,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notchRect: IslandGeometry.notchRect(
                screenFrame: screen.frame,
                safeAreaTop: safeTop,
                leftArea: screen.auxiliaryTopLeftArea ?? .zero,
                rightArea: screen.auxiliaryTopRightArea ?? .zero
            ),
            menuBarHeight: IslandGeometry.menuBarHeight(
                frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: safeTop
            ),
            backingScale: screen.backingScaleFactor
        )
    }
}

/// Tracks connected displays and system sleep/wake, publishing value snapshots.
@MainActor
@Observable
public final class DisplayMonitor {
    public private(set) var displays: [DisplayDescriptor] = []
    public private(set) var screensAsleep = false

    @ObservationIgnored private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    public init() {}

    public func start() {
        guard tokens.isEmpty else { return }
        refresh()

        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.displaysChanged() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.woke() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.woke() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.refresh() }
    }

    public func stop() {
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
        settleTask?.cancel()
    }

    public func refresh() {
        let current = NSScreen.screens.compactMap(DisplayDescriptor.init(screen:))
        if current != displays {
            displays = current
        }
    }

    private func woke() {
        screensAsleep = false
        displaysChanged()
    }

    /// Screen parameters can still be settling when the notification arrives (for example
    /// while a display is waking), so refresh now and once more shortly after.
    private func displaysChanged() {
        refresh()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ handler: @escaping @MainActor (DisplayMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        tokens.append((center, token))
    }
}

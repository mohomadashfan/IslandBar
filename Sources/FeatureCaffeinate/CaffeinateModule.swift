import AppKit
import IOKit.pwr_mgt
import IslandCore
import IslandDesign
import Observation
import SwiftUI

/// How long to keep the Mac awake.
public enum CaffeinateDuration: Hashable, Sendable, CaseIterable, Identifiable {
    case minutes15, hour1, hours2, hours4, indefinitely

    public var id: Self { self }

    public var interval: TimeInterval? {
        switch self {
        case .minutes15: 15 * 60
        case .hour1: 3600
        case .hours2: 2 * 3600
        case .hours4: 4 * 3600
        case .indefinitely: nil
        }
    }

    public var displayName: String {
        switch self {
        case .minutes15: "15 Minutes"
        case .hour1: "1 Hour"
        case .hours2: "2 Hours"
        case .hours4: "4 Hours"
        case .indefinitely: "Until Turned Off"
        }
    }
}

/// Pure state: whether keep-awake is on and until when.
public struct CaffeinateState: Sendable, Equatable {
    public var isActive = false
    public var endDate: Date?

    public init(isActive: Bool = false, endDate: Date? = nil) {
        self.isActive = isActive
        self.endDate = endDate
    }

    public static func started(_ duration: CaffeinateDuration, at now: Date) -> CaffeinateState {
        CaffeinateState(isActive: true, endDate: duration.interval.map { now.addingTimeInterval($0) })
    }

    public func hasExpired(at now: Date) -> Bool {
        guard isActive, let endDate else { return false }
        return now >= endDate
    }

    public func remaining(at now: Date) -> TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }
}

/// Keeps the Mac awake with a standard IOKit power assertion (the same mechanism as the
/// `caffeinate` command). The assertion is released automatically if IslandBar quits.
@MainActor
@Observable
public final class CaffeinateModule: IslandModule {
    public let id = FeatureID.caffeinate
    public let displayName = "Keep Awake"
    public let symbolName = "cup.and.saucer"
    public var hasPage: Bool { false }

    public private(set) var state = CaffeinateState()
    public private(set) var lastError: String?
    public private(set) var settings = CaffeinateSettings()

    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var assertionAllowsDisplaySleep = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        settings.showLiveActivity && state.isActive ? LiveActivityPriority.caffeinate : nil
    }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.caffeinate.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        let modeChanged = settings.caffeinate.allowDisplaySleep != self.settings.allowDisplaySleep
        self.settings = settings.caffeinate
        if modeChanged, state.isActive {
            // Swap the assertion type without interrupting keep-awake.
            releaseAssertion()
            createAssertion()
        }
    }

    public func activate() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
    }

    public func deactivate() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        stop(announce: false)
    }

    public func makeCompactLeading() -> AnyView { AnyView(CaffeinateCompactLeading()) }
    public func makeCompactTrailing() -> AnyView { AnyView(CaffeinateCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(EmptyView()) }
    public func makeHeaderAccessory() -> AnyView? { AnyView(CaffeinateHeaderButton(module: self)) }

    // MARK: Control

    public func start(_ duration: CaffeinateDuration) {
        guard createAssertion() else { return }
        state = .started(duration, at: .now)
        scheduleExpiry()
    }

    public func stop() {
        stop(announce: false)
    }

    public func toggle() {
        state.isActive ? stop() : start(.indefinitely)
    }

    // MARK: Private

    @discardableResult
    private func createAssertion() -> Bool {
        if assertionID != 0 {
            guard assertionAllowsDisplaySleep != settings.allowDisplaySleep else { return true }
            releaseAssertion()
        }
        let type = settings.allowDisplaySleep ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "IslandBar Keep Awake" as CFString, &id
        )
        guard result == kIOReturnSuccess else {
            lastError = "macOS refused the keep-awake request (error \(result))."
            return false
        }
        assertionID = id
        assertionAllowsDisplaySleep = settings.allowDisplaySleep
        lastError = nil
        return true
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func stop(announce: Bool) {
        expiryTask?.cancel()
        expiryTask = nil
        releaseAssertion()
        let wasActive = state.isActive
        state = CaffeinateState()
        if announce, wasActive {
            activity.post(ActivityEvent(source: .system, title: "Keep Awake ended", subtitle: "Your Mac can sleep normally again.", symbolName: "cup.and.saucer"))
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let remaining = state.remaining(at: .now) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(remaining * 1000) + 50))
            guard !Task.isCancelled else { return }
            self?.checkExpiry()
        }
    }

    private func checkExpiry() {
        if state.hasExpired(at: .now) {
            stop(announce: true)
        }
    }
}

// MARK: - Views

private func formatRemaining(_ interval: TimeInterval) -> String {
    let minutes = Int((interval / 60).rounded(.up))
    return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
}

struct CaffeinateCompactLeading: View {
    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.orange)
            .accessibilityLabel("Keeping your Mac awake")
    }
}

struct CaffeinateCompactTrailing: View {
    let module: CaffeinateModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if module.state.endDate != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(module.state.remaining(at: context.date).map(formatRemaining) ?? "")
            }
            .font(theme.monospacedDigits(11, weight: .semibold))
            .foregroundStyle(theme.primary)
        } else {
            Image(systemName: "infinity")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.primary)
        }
    }
}

/// Header button: click toggles; the menu offers durations.
struct CaffeinateHeaderButton: View {
    let module: CaffeinateModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Menu {
            ForEach(CaffeinateDuration.allCases) { duration in
                Button("Keep Awake for \(duration.displayName)") { module.start(duration) }
            }
            if module.state.isActive {
                Divider()
                Button("Turn Off") { module.stop() }
            }
        } label: {
            Image(systemName: module.state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(module.state.isActive ? Color.orange : theme.secondary)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        } primaryAction: {
            module.toggle()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(module.state.isActive ? "Keeping your Mac awake. Click to turn off." : "Keep your Mac awake. Click and hold for durations.")
        .accessibilityLabel(module.state.isActive ? "Turn off Keep Awake" : "Keep Mac awake")
    }
}

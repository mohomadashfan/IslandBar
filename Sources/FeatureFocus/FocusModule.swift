import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI

/// What the Focus module keeps on disk.
struct FocusPersistedState: Codable, Sendable, Equatable {
    var timer = FocusTimerState()
    var notes = ""
}

@MainActor
@Observable
public final class FocusModule: IslandModule {
    public let id = FeatureID.focus
    public let displayName = "Focus"
    public let symbolName = "timer"

    public private(set) var timer: FocusTimerState
    public private(set) var durations = FocusDurations(FocusSettings())
    public private(set) var lastSaveError: PersistenceError?
    public var notes: String {
        didSet { if notes != oldValue { scheduleSave() } }
    }

    @ObservationIgnored private var showLiveActivity = true
    @ObservationIgnored private var autoStart = false
    @ObservationIgnored private let store: JSONFileStore<FocusPersistedState>
    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public init(activity: ActivityCenter, fileURL: URL = AppPaths.file(named: "focus.json")) {
        self.activity = activity
        // No defaults merge: `FocusTimerState.Run` has associated values, which merge unsafely.
        self.store = JSONFileStore(fileURL: fileURL)
        var persisted = FocusPersistedState()
        var loadError: PersistenceError?
        do {
            persisted = try store.load() ?? FocusPersistedState()
        } catch {
            loadError = error
            if case .decodeFailed = error { store.quarantineFile() }
        }
        self.timer = persisted.timer
        self.notes = persisted.notes
        self.lastSaveError = loadError
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        guard showLiveActivity, !timer.isIdle else { return nil }
        return LiveActivityPriority.focus
    }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.focus.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        showLiveActivity = settings.focus.showLiveActivity
        autoStart = settings.focus.autoStartNextPhase
        let updated = FocusDurations(settings.focus)
        if updated != durations {
            durations = updated
            catchUp()
        }
    }

    public func activate() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        catchUp()
    }

    public func deactivate() {
        completionTask?.cancel()
        completionTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        flushSave()
    }

    public func makeCompactLeading() -> AnyView { AnyView(FocusCompactLeading(module: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(FocusCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(FocusExpandedView(module: self)) }

    // MARK: Controls

    public func startOrPause() {
        if timer.isRunning {
            timer.pause(at: .now)
        } else {
            timer.start(at: .now)
        }
        stateChanged()
    }

    public func resetPhase() {
        timer.resetPhase()
        stateChanged()
    }

    public func resetAll() {
        timer.resetAll()
        stateChanged()
    }

    public func skip() {
        timer.skip(durations: durations)
        stateChanged()
    }

    // MARK: Timing

    /// Applies any completions that happened while we were not looking (sleep, restart, a late
    /// timer) and schedules the next one.
    private func catchUp() {
        let now = Date.now
        var changed = false
        while let finished = timer.advanceIfFinished(at: now, durations: durations, autoStart: autoStart) {
            changed = true
            announce(finished)
        }
        if changed {
            scheduleSave()
        }
        scheduleCompletion()
    }

    private func stateChanged() {
        scheduleSave()
        scheduleCompletion()
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = nil
        guard let end = timer.endDate(durations: durations) else { return }
        let delay = max(end.timeIntervalSinceNow, 0)
        // ContinuousClock keeps counting during system sleep; the wake observer covers the
        // case where the task is late anyway.
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000) + 50))
            guard !Task.isCancelled else { return }
            self?.catchUp()
        }
    }

    private func announce(_ finished: FocusPhase) {
        let event: ActivityEvent = switch finished {
        case .work:
            ActivityEvent(
                source: .focus, style: .success, title: "Focus session complete",
                subtitle: "Session \(timer.completedWorkSessions) done — time for a \(timer.phase.displayName.lowercased()).",
                symbolName: "checkmark.circle.fill"
            )
        case .shortBreak, .longBreak:
            ActivityEvent(
                source: .focus, title: "Break is over",
                subtitle: timer.isRunning ? "Next focus session started." : "Ready for the next focus session.",
                symbolName: "brain.head.profile"
            )
        }
        activity.post(event)
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try store.save(FocusPersistedState(timer: timer, notes: notes))
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }
}

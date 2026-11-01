import Foundation
import IslandCore

public enum FocusPhase: String, Codable, Sendable, CaseIterable {
    case work, shortBreak, longBreak

    public var displayName: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    public var symbolName: String {
        switch self {
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }
}

public struct FocusDurations: Sendable, Equatable {
    public var work: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var sessionsBeforeLongBreak: Int

    public init(work: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, sessionsBeforeLongBreak: Int) {
        self.work = work
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.sessionsBeforeLongBreak = max(sessionsBeforeLongBreak, 1)
    }

    /// Minutes from settings, clamped to at least one minute per phase.
    public init(_ settings: FocusSettings) {
        self.init(
            work: max(settings.workMinutes, 1) * 60,
            shortBreak: max(settings.shortBreakMinutes, 1) * 60,
            longBreak: max(settings.longBreakMinutes, 1) * 60,
            sessionsBeforeLongBreak: settings.sessionsBeforeLongBreak
        )
    }

    public func duration(for phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// Pomodoro state that is computed from wall-clock timestamps, never from counting ticks.
///
/// Because only start times and accumulated durations are stored, the state survives app
/// restarts and system sleep: elapsed time is always `now - startedAt + elapsedBefore`.
public struct FocusTimerState: Codable, Sendable, Equatable {
    public enum Run: Codable, Sendable, Equatable {
        case idle
        case running(since: Date, elapsedBefore: TimeInterval)
        case paused(elapsed: TimeInterval)
    }

    /// Completions further in the past than this do not auto-start the next phase; after a long
    /// sleep or with the app quit, the user decides when to continue.
    public static let autoStartGrace: TimeInterval = 60

    public var phase = FocusPhase.work
    public var run = Run.idle
    /// Work sessions completed since the last full reset.
    public var completedWorkSessions = 0

    public init() {}

    public var isRunning: Bool {
        if case .running = run { true } else { false }
    }

    public var isPaused: Bool {
        if case .paused = run { true } else { false }
    }

    public var isIdle: Bool { run == .idle }

    public func elapsed(at now: Date) -> TimeInterval {
        switch run {
        case .idle: 0
        case .paused(let elapsed): elapsed
        case .running(let since, let before): before + max(0, now.timeIntervalSince(since))
        }
    }

    public func remaining(at now: Date, durations: FocusDurations) -> TimeInterval {
        max(0, durations.duration(for: phase) - elapsed(at: now))
    }

    public func progress(at now: Date, durations: FocusDurations) -> Double {
        let total = durations.duration(for: phase)
        guard total > 0 else { return 1 }
        return min(1, elapsed(at: now) / total)
    }

    /// When the running phase will finish, if it is running.
    public func endDate(durations: FocusDurations) -> Date? {
        guard case .running(let since, let before) = run else { return nil }
        return since.addingTimeInterval(durations.duration(for: phase) - before)
    }

    /// Position within the current cycle of work sessions, for progress dots.
    public func sessionInCycle(durations: FocusDurations) -> Int {
        completedWorkSessions % durations.sessionsBeforeLongBreak
    }

    public mutating func start(at now: Date) {
        switch run {
        case .idle: run = .running(since: now, elapsedBefore: 0)
        case .paused(let elapsed): run = .running(since: now, elapsedBefore: elapsed)
        case .running: break
        }
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        run = .paused(elapsed: elapsed(at: now))
    }

    /// Restarts the current phase from zero without changing the session count.
    public mutating func resetPhase() {
        run = .idle
    }

    /// Back to the first work session.
    public mutating func resetAll() {
        self = FocusTimerState()
    }

    /// Moves to the next phase without counting the current one as completed.
    public mutating func skip(durations: FocusDurations) {
        phase = phase == .work ? .shortBreak : .work
        run = .idle
    }

    public func nextPhase(afterCompleting finished: FocusPhase, durations: FocusDurations) -> FocusPhase {
        switch finished {
        case .work:
            completedWorkSessions > 0 && completedWorkSessions % durations.sessionsBeforeLongBreak == 0
                ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            .work
        }
    }

    /// If the running phase has finished by `now`, records it and moves to the next phase.
    /// Returns the phase that finished, or `nil` if nothing changed. Call repeatedly to catch up.
    public mutating func advanceIfFinished(at now: Date, durations: FocusDurations, autoStart: Bool) -> FocusPhase? {
        guard let end = endDate(durations: durations), now >= end else { return nil }

        let finished = phase
        if finished == .work {
            completedWorkSessions += 1
        }
        phase = nextPhase(afterCompleting: finished, durations: durations)

        if autoStart, now.timeIntervalSince(end) < Self.autoStartGrace {
            run = .running(since: end, elapsedBefore: 0)
        } else {
            run = .idle
        }
        return finished
    }
}

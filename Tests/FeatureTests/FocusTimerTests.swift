@testable import FeatureFocus
import IslandCore
import XCTest

final class FocusTimerTests: XCTestCase {
    private let durations = FocusDurations(work: 1500, shortBreak: 300, longBreak: 900, sessionsBeforeLongBreak: 4)
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testElapsedComesFromTimestamps() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(600)), 600)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(600), durations: durations), 900)
        XCTAssertEqual(timer.progress(at: t0.addingTimeInterval(750), durations: durations), 0.5, accuracy: 0.0001)
    }

    func testPauseFreezesAndResumeContinues() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        timer.pause(at: t0.addingTimeInterval(100))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(10_000)), 100)

        timer.start(at: t0.addingTimeInterval(5000))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(5050)), 150)
        XCTAssertEqual(timer.endDate(durations: durations), t0.addingTimeInterval(5000 + 1500 - 100))
    }

    func testClockGoingBackwardsNeverProducesNegativeElapsed() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(-60)), 0)
    }

    func testNotFinishedDoesNotAdvance() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        XCTAssertNil(timer.advanceIfFinished(at: t0.addingTimeInterval(1499), durations: durations, autoStart: true))
        XCTAssertEqual(timer.phase, .work)
    }

    func testWorkCompletionMovesToShortBreak() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        let finished = timer.advanceIfFinished(at: t0.addingTimeInterval(1500), durations: durations, autoStart: false)
        XCTAssertEqual(finished, .work)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.completedWorkSessions, 1)
        XCTAssertTrue(timer.isIdle)
    }

    func testFourthSessionEarnsLongBreak() {
        var timer = FocusTimerState()
        timer.completedWorkSessions = 3
        timer.start(at: t0)
        _ = timer.advanceIfFinished(at: t0.addingTimeInterval(1500), durations: durations, autoStart: false)
        XCTAssertEqual(timer.phase, .longBreak)
        XCTAssertEqual(timer.sessionInCycle(durations: durations), 0)
    }

    func testBreakReturnsToWorkWithoutCounting() {
        var timer = FocusTimerState()
        timer.phase = .shortBreak
        timer.completedWorkSessions = 2
        timer.start(at: t0)
        XCTAssertEqual(timer.advanceIfFinished(at: t0.addingTimeInterval(300), durations: durations, autoStart: false), .shortBreak)
        XCTAssertEqual(timer.phase, .work)
        XCTAssertEqual(timer.completedWorkSessions, 2)
    }

    func testAutoStartBeginsNextPhaseAtExactCompletionTime() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        let now = t0.addingTimeInterval(1510)
        _ = timer.advanceIfFinished(at: now, durations: durations, autoStart: true)
        XCTAssertEqual(timer.run, .running(since: t0.addingTimeInterval(1500), elapsedBefore: 0))
        XCTAssertEqual(timer.elapsed(at: now), 10)
    }

    func testAutoStartDoesNotChainAfterLongAbsence() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        // App quit or Mac asleep for hours.
        let now = t0.addingTimeInterval(4 * 3600)
        XCTAssertEqual(timer.advanceIfFinished(at: now, durations: durations, autoStart: true), .work)
        XCTAssertNil(timer.advanceIfFinished(at: now, durations: durations, autoStart: true))
        XCTAssertTrue(timer.isIdle)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.completedWorkSessions, 1)
    }

    func testSkipDoesNotCountAndResetsRun() {
        var timer = FocusTimerState()
        timer.start(at: t0)
        timer.skip(durations: durations)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.completedWorkSessions, 0)
        XCTAssertTrue(timer.isIdle)
    }

    func testDurationsClampToOneMinute() {
        var settings = FocusSettings()
        settings.workMinutes = 0
        settings.sessionsBeforeLongBreak = 0
        let clamped = FocusDurations(settings)
        XCTAssertEqual(clamped.work, 60)
        XCTAssertEqual(clamped.sessionsBeforeLongBreak, 1)
    }

    func testStateRoundTripsThroughJSON() throws {
        var timer = FocusTimerState()
        timer.completedWorkSessions = 5
        timer.start(at: t0)
        let data = try JSONEncoder().encode(timer)
        XCTAssertEqual(try JSONDecoder().decode(FocusTimerState.self, from: data), timer)
    }
}

@MainActor
final class FocusModuleTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appending(path: "focus-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testRunningTimerSurvivesRestart() {
        let first = FocusModule(activity: ActivityCenter(), fileURL: fileURL)
        first.activate()
        first.startOrPause()
        first.notes = "Write tests"
        first.deactivate()

        let second = FocusModule(activity: ActivityCenter(), fileURL: fileURL)
        XCTAssertTrue(second.timer.isRunning)
        XCTAssertEqual(second.notes, "Write tests")
        XCTAssertNotNil(second.liveActivityPriority, "a restored running timer shows immediately")
        second.deactivate()
    }

    func testCorruptStateIsSetAsideAndReported() throws {
        try Data("{".utf8).write(to: fileURL)
        let module = FocusModule(activity: ActivityCenter(), fileURL: fileURL)
        XCTAssertTrue(module.timer.isIdle)
        XCTAssertNotNil(module.lastSaveError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)
        for backup in siblings where backup.hasPrefix(fileURL.lastPathComponent + ".corrupt") {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent().appending(path: backup))
        }
    }

    func testLiveActivityOnlyWhileTimerIsNotIdle() {
        let module = FocusModule(activity: ActivityCenter(), fileURL: fileURL)
        module.apply(.defaults)
        XCTAssertNil(module.liveActivityPriority)
        module.startOrPause()
        XCTAssertNotNil(module.liveActivityPriority)
        module.resetPhase()
        XCTAssertNil(module.liveActivityPriority)
        module.deactivate()
    }
}

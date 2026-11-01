@testable import FeatureDeveloper
import IslandCore
import XCTest

final class DeveloperEventTests: XCTestCase {
    func testDecodesFullEvent() throws {
        let json = """
        {"source": "vscode", "kind": "build", "state": "running", "title": "swift build",
         "detail": "Compiling", "progress": 0.4, "session": "s1", "timestamp": "2026-01-01T10:00:00Z"}
        """
        let event = try DeveloperEvent.decode(Data(json.utf8))
        XCTAssertEqual(event.kind, .build)
        XCTAssertEqual(event.state, .running)
        XCTAssertEqual(event.progress, 0.4)
        XCTAssertEqual(event.activityKey, "vscode|s1")
        XCTAssertNotNil(event.timestamp)
    }

    func testUnknownKindAndStateAreTolerated() throws {
        let event = try DeveloperEvent.decode(Data(#"{"source": "x", "title": "t", "kind": "lint", "state": "exploded"}"#.utf8))
        XCTAssertEqual(event.kind, .custom)
        XCTAssertEqual(event.state, .info)
    }

    func testRequiredFieldsAndCleaning() throws {
        XCTAssertThrowsError(try DeveloperEvent.decode(Data(#"{"title": "t"}"#.utf8)))
        XCTAssertThrowsError(try DeveloperEvent.decode(Data(#"{"source": " ", "title": "t"}"#.utf8)))

        let long = String(repeating: "a", count: 500)
        let event = try DeveloperEvent.decode(Data(#"{"source": "x", "title": "line1\nline2", "detail": "\#(long)", "progress": 7}"#.utf8))
        XCTAssertEqual(event.title, "line1 line2")
        XCTAssertEqual(event.detail?.count, DeveloperEvent.maxTextLength)
        XCTAssertEqual(event.progress, 1)
    }

    func testBadTimestampIsIgnoredNotFatal() throws {
        let event = try DeveloperEvent.decode(Data(#"{"source": "x", "title": "t", "timestamp": "yesterday"}"#.utf8))
        XCTAssertNil(event.timestamp)
    }
}

final class DeveloperActivityLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 5_000_000)

    private func event(_ state: DeveloperEvent.State, session: String = "s", title: String = "build") -> DeveloperEvent {
        DeveloperEvent(source: "tool", kind: .build, state: state, title: title, session: session)
    }

    func testUpdatesSameActivityAndReportsFinishOnce() {
        var log = DeveloperActivityLog()
        XCTAssertNil(log.apply(event(.started), receivedAt: t0))
        XCTAssertNil(log.apply(event(.running), receivedAt: t0.addingTimeInterval(5)))
        XCTAssertEqual(log.activities.count, 1)
        XCTAssertTrue(log.activities[0].isActive)

        let finished = log.apply(event(.succeeded), receivedAt: t0.addingTimeInterval(10))
        XCTAssertEqual(finished?.event.state, .succeeded)
        XCTAssertNil(log.apply(event(.succeeded), receivedAt: t0.addingTimeInterval(11)))
    }

    func testSeparateSessionsAreSeparateActivities() {
        var log = DeveloperActivityLog()
        log.apply(event(.running, session: "a"), receivedAt: t0)
        log.apply(event(.running, session: "b"), receivedAt: t0.addingTimeInterval(1))
        XCTAssertEqual(log.activities.map(\.id), ["tool|b", "tool|a"])
    }

    func testLimitDropsOldest() {
        var log = DeveloperActivityLog()
        log.limit = 2
        for index in 0..<4 {
            log.apply(event(.running, session: "\(index)"), receivedAt: t0.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(log.activities.map(\.id), ["tool|3", "tool|2"])
    }

    func testStaleActivitiesAreCancelled() {
        var log = DeveloperActivityLog()
        log.apply(event(.running), receivedAt: t0)
        XCTAssertFalse(log.expireStale(now: t0.addingTimeInterval(60), staleAfter: 600))
        XCTAssertTrue(log.expireStale(now: t0.addingTimeInterval(601), staleAfter: 600))
        XCTAssertEqual(log.activities[0].event.state, .cancelled)
    }

    func testClearFinishedKeepsRunning() {
        var log = DeveloperActivityLog()
        log.apply(event(.running, session: "a"), receivedAt: t0)
        log.apply(event(.failed, session: "b"), receivedAt: t0)
        log.clearFinished()
        XCTAssertEqual(log.activities.map(\.id), ["tool|a"])
    }
}

final class GitParserTests: XCTestCase {
    func testStatusWithTrackingAndChanges() {
        let output = """
        ## main...origin/main [ahead 2, behind 1]
        M  staged.swift
         M modified.swift
        MM both.swift
        A  added.swift
        ?? new.txt
        UU conflict.swift
        """
        let summary = GitParser.parseStatus(output)
        XCTAssertEqual(summary.branch, "main")
        XCTAssertEqual(summary.upstream, "origin/main")
        XCTAssertEqual(summary.ahead, 2)
        XCTAssertEqual(summary.behind, 1)
        XCTAssertEqual(summary.staged, 3)
        XCTAssertEqual(summary.unstaged, 2)
        XCTAssertEqual(summary.untracked, 1)
        XCTAssertEqual(summary.conflicted, 1)
        XCTAssertFalse(summary.isClean)
    }

    func testBranchLineVariants() {
        XCTAssertEqual(GitParser.parseStatus("## feature/x").branch, "feature/x")
        XCTAssertEqual(GitParser.parseStatus("## No commits yet on main").branch, "main")
        XCTAssertNil(GitParser.parseStatus("## HEAD (no branch)").branch)
        let behindOnly = GitParser.parseStatus("## dev...origin/dev [behind 4]")
        XCTAssertEqual(behindOnly.behind, 4)
        XCTAssertEqual(behindOnly.ahead, 0)
        XCTAssertTrue(GitParser.parseStatus("## main").isClean)
    }

    func testLastCommit() throws {
        let commit = try XCTUnwrap(GitParser.parseLastCommit("Fix crash\u{1F}3 hours ago\n"))
        XCTAssertEqual(commit.subject, "Fix crash")
        XCTAssertEqual(commit.age, "3 hours ago")
        XCTAssertNil(GitParser.parseLastCommit(""))
    }

    func testNoisePathsAreIgnored() {
        XCTAssertTrue(DeveloperModule.isNoise("/r/.git/objects/ab/cdef"))
        XCTAssertTrue(DeveloperModule.isNoise("/r/.git/index.lock"))
        XCTAssertFalse(DeveloperModule.isNoise("/r/.git/HEAD"))
        XCTAssertFalse(DeveloperModule.isNoise("/r/Sources/main.swift"))
    }

    func testStatusOfRealRepository() async throws {
        guard FileManager.default.isExecutableFile(atPath: GitClient.executable),
              (try? await GitClient.run(["--version"], in: "/")) != nil else {
            throw XCTSkip("git is not available")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await GitClient.run(["init", "-q", "-b", "main"], in: directory.path)
        try Data("x".utf8).write(to: directory.appending(path: "file.txt"))

        let status = await GitClient.status(of: directory.path)

        XCTAssertNil(status.error)
        XCTAssertEqual(status.summary?.branch, "main")
        XCTAssertEqual(status.summary?.untracked, 1)
    }

    func testNonRepositoryReportsError() async {
        let status = await GitClient.status(of: FileManager.default.temporaryDirectory.path)
        XCTAssertNotNil(status.error)
        XCTAssertNil(status.summary)
    }
}

@MainActor
final class DeveloperModuleTests: XCTestCase {
    func testInboxEventsAreConsumedAndInvalidOnesRejected() async throws {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: inbox) }
        let activity = ActivityCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        let module = DeveloperModule(activity: activity, inboxURL: inbox)
        var settings = AppSettings.defaults
        settings.developer.eventInboxEnabled = true
        module.apply(settings)
        module.activate()
        defer { module.deactivate() }

        try Data(#"{"source": "ci", "kind": "test", "state": "failed", "title": "Unit tests"}"#.utf8)
            .write(to: inbox.appending(path: "1.json"))
        try Data("not json".utf8).write(to: inbox.appending(path: "2.json"))

        for _ in 0..<200 where module.log.activities.isEmpty || module.rejectedEventCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(module.log.activities.first?.event.title, "Unit tests")
        XCTAssertEqual(module.rejectedEventCount, 1)
        XCTAssertEqual(activity.history.first?.title, "Unit tests failed")
        XCTAssertEqual(activity.history.first?.style, .failure)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInboxIsOffByDefault() {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        let module = DeveloperModule(activity: ActivityCenter(), inboxURL: inbox)
        module.apply(.defaults)
        module.activate()
        defer { module.deactivate() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path), "no folder is created unless the user opts in")
    }

    func testRunningActivityBecomesLiveActivity() {
        let module = DeveloperModule(activity: ActivityCenter(), inboxURL: FileManager.default.temporaryDirectory.appending(path: "unused"))
        module.apply(.defaults)
        XCTAssertNil(module.liveActivityPriority)
        module.receive(DeveloperEvent(source: "agent", kind: .agent, state: .running, title: "Refactor"))
        XCTAssertNotNil(module.liveActivityPriority)
        module.receive(DeveloperEvent(source: "agent", kind: .agent, state: .succeeded, title: "Refactor"))
        XCTAssertNil(module.liveActivityPriority)
    }
}

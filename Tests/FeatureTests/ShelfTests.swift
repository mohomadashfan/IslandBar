@testable import FeatureFileShelf
import IslandCore
import XCTest

final class ShelfPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func item(_ name: String, ageHours: Double) -> ShelfItem {
        ShelfItem(bookmark: Data(), name: name, path: "/tmp/\(name)", addedAt: now.addingTimeInterval(-ageHours * 3600))
    }

    func testExpiredItemsAreRemoved() {
        let items = [item("new", ageHours: 0.5), item("old", ageHours: 2)]
        let kept = ShelfPolicy.pruned(items, now: now, expiry: .oneHour, maxItems: 10)
        XCTAssertEqual(kept.map(\.name), ["new"])
    }

    func testNeverExpiryKeepsEverything() {
        let items = [item("a", ageHours: 1000)]
        XCTAssertEqual(ShelfPolicy.pruned(items, now: now, expiry: .never, maxItems: 10).count, 1)
        XCTAssertNil(ShelfPolicy.nextExpiry(items, expiry: .never))
    }

    func testMaxItemsKeepsNewest() {
        let items = [item("c", ageHours: 3), item("a", ageHours: 1), item("b", ageHours: 2)]
        let kept = ShelfPolicy.pruned(items, now: now, expiry: .never, maxItems: 2)
        XCTAssertEqual(kept.map(\.name), ["a", "b"])
    }

    func testNextExpiryIsEarliest() {
        let items = [item("a", ageHours: 0.25), item("b", ageHours: 0.75)]
        XCTAssertEqual(ShelfPolicy.nextExpiry(items, expiry: .oneHour), now.addingTimeInterval(0.25 * 3600))
    }

    func testDuplicatePathsAreSkipped() {
        let existing = [item("a", ageHours: 0)]
        XCTAssertEqual(ShelfPolicy.newPaths(["/tmp/a", "/tmp/b", "/tmp/b", "/tmp/c"], existing: existing), ["/tmp/b", "/tmp/c"])
    }
}

@MainActor
final class FileShelfModuleTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeModule(activity: ActivityCenter = ActivityCenter()) -> FileShelfModule {
        let module = FileShelfModule(activity: activity, fileURL: directory.appending(path: "shelf.json"))
        module.apply(.defaults)
        module.activate()
        return module
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    func testAddingStoresReferencesNotCopiesAndPersists() throws {
        let file = try makeFile("report.txt")
        let activity = ActivityCenter(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        let module = makeModule(activity: activity)

        module.add([file, file])

        XCTAssertEqual(module.items.count, 1)
        XCTAssertEqual(module.items.first?.name, "report.txt")
        XCTAssertEqual(activity.history.first?.title, "Added to Shelf")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), ["report.txt", "shelf.json"])

        let restored = FileShelfModule(activity: ActivityCenter(), fileURL: directory.appending(path: "shelf.json"))
        XCTAssertEqual(restored.items.map(\.path), [ShelfPolicy.canonicalPath(file)])
        module.deactivate()
    }

    func testSymlinkedPathIsNotAddedTwice() throws {
        let file = try makeFile("same.txt")
        let module = makeModule()
        module.add([file])
        module.add([URL(fileURLWithPath: ShelfPolicy.canonicalPath(file))])
        XCTAssertEqual(module.items.count, 1)
        module.deactivate()
    }

    func testMissingFileIsReportedNotFatal() throws {
        let file = try makeFile("gone.txt")
        let module = makeModule()
        module.add([file])
        let item = try XCTUnwrap(module.items.first)

        try FileManager.default.removeItem(at: file)

        XCTAssertNil(module.url(for: item))
        XCTAssertTrue(module.unavailable.contains(item.id))
        module.open(item)  // must not crash
        module.remove(item)
        XCTAssertTrue(module.items.isEmpty)
        module.deactivate()
    }

    func testMovedFileIsFollowed() throws {
        let file = try makeFile("draft.txt")
        let module = makeModule()
        module.add([file])
        let item = try XCTUnwrap(module.items.first)

        let moved = directory.appending(path: "final.txt")
        try FileManager.default.moveItem(at: file, to: moved)

        let resolved = try XCTUnwrap(module.url(for: item))
        XCTAssertEqual(resolved.lastPathComponent, "final.txt")
        XCTAssertEqual(module.items.first?.name, "final.txt")
        module.deactivate()
    }

    func testCorruptShelfFileIsSetAside() throws {
        try Data("garbage".utf8).write(to: directory.appending(path: "shelf.json"))
        let module = FileShelfModule(activity: ActivityCenter(), fileURL: directory.appending(path: "shelf.json"))
        XCTAssertTrue(module.items.isEmpty)
        XCTAssertNotNil(module.lastError)
    }
}

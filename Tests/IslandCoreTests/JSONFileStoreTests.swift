import IslandCore
import XCTest

final class JSONFileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "IslandBarTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> JSONFileStore<AppSettings> {
        JSONFileStore(fileURL: directory.appending(path: "nested/settings.json"))
    }

    func testLoadReturnsNilWhenFileIsMissing() throws {
        XCTAssertNil(try makeStore().load())
    }

    func testSaveCreatesIntermediateDirectoriesAndRoundTrips() throws {
        let store = makeStore()
        var settings = AppSettings()
        settings.general.isIslandEnabled = false

        try store.save(settings)

        XCTAssertEqual(try store.load(), settings)
    }

    func testCorruptFileReportsDecodeFailure() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case PersistenceError.decodeFailed = error else {
                return XCTFail("Expected decodeFailed, got \(error)")
            }
        }
    }

    func testQuarantineMovesFileAside() throws {
        let store = makeStore()
        try store.save(.defaults)

        let backup = try XCTUnwrap(store.quarantineFile())

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertNil(try store.load())
    }

    func testFilesAreOwnerOnly() throws {
        let store = makeStore()
        try store.save(.defaults)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testQuarantineWithoutFileIsNoOp() {
        XCTAssertNil(makeStore().quarantineFile())
    }

    func testDefaultsMergeFillsMissingKeys() throws {
        let store = JSONFileStore<AppSettings>(fileURL: directory.appending(path: "settings.json"), defaults: .defaults)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"general": {"isIslandEnabled": false}}"#.utf8).write(to: store.fileURL)

        let loaded = try XCTUnwrap(store.load())

        XCTAssertFalse(loaded.general.isIslandEnabled)
        XCTAssertEqual(loaded.appearance, AppearanceSettings())
    }

    func testUnreadableFileReportsReadFailure() throws {
        let store = makeStore()
        // A directory where the file should be cannot be read as data.
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.load()) { error in
            guard case PersistenceError.readFailed = error else {
                return XCTFail("Expected readFailed, got \(error)")
            }
        }
    }
}

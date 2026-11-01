import Foundation
import IslandCore
import XCTest

/// In-memory persistence with switchable failure modes.
private final class FakePersistence: SettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _stored: AppSettings?
    private var _saveCount = 0
    private var _quarantineCount = 0

    let loadError: PersistenceError?
    var saveError: PersistenceError? {
        get { lock.withLock { _saveError } }
        set { lock.withLock { _saveError = newValue } }
    }
    private var _saveError: PersistenceError?

    init(stored: AppSettings? = nil, loadError: PersistenceError? = nil) {
        _stored = stored
        self.loadError = loadError
    }

    var stored: AppSettings? { lock.withLock { _stored } }
    var saveCount: Int { lock.withLock { _saveCount } }
    var quarantineCount: Int { lock.withLock { _quarantineCount } }

    func load() throws(PersistenceError) -> AppSettings? {
        if let loadError { throw loadError }
        return stored
    }

    func save(_ settings: AppSettings) throws(PersistenceError) {
        if let saveError { throw saveError }
        lock.withLock {
            _stored = settings
            _saveCount += 1
        }
    }

    func quarantineUnreadableData() {
        lock.withLock { _quarantineCount += 1 }
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testStartsWithDefaultsWhenNothingStored() {
        let store = SettingsStore(persistence: FakePersistence(), saveDelay: .zero)
        XCTAssertEqual(store.settings, .defaults)
        XCTAssertNil(store.lastError)
    }

    func testRestoresPreviouslyStoredSettings() {
        var saved = AppSettings()
        saved.general.isIslandEnabled = false

        let store = SettingsStore(persistence: FakePersistence(stored: saved), saveDelay: .zero)

        XCTAssertEqual(store.settings, saved)
    }

    func testCorruptDataIsQuarantinedAndDefaultsUsed() {
        let persistence = FakePersistence(loadError: .decodeFailed("bad"))

        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        XCTAssertEqual(store.settings, .defaults)
        XCTAssertEqual(store.lastError, .decodeFailed("bad"))
        XCTAssertEqual(persistence.quarantineCount, 1)
    }

    func testReadFailureDoesNotQuarantine() {
        let persistence = FakePersistence(loadError: .readFailed("permission denied"))

        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        XCTAssertEqual(store.settings, .defaults)
        XCTAssertEqual(persistence.quarantineCount, 0)
    }

    func testUpdatePersistsChange() {
        let persistence = FakePersistence()
        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        store.update { $0.general.isIslandEnabled = false }

        XCTAssertFalse(store.settings.general.isIslandEnabled)
        XCTAssertEqual(persistence.stored?.general.isIslandEnabled, false)
        XCTAssertEqual(persistence.saveCount, 1)
    }

    func testNoOpUpdateDoesNotWrite() {
        let persistence = FakePersistence()
        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        store.update { $0.general.isIslandEnabled = true }

        XCTAssertEqual(persistence.saveCount, 0)
    }

    func testSaveFailureKeepsInMemoryValueAndReportsError() {
        let persistence = FakePersistence()
        persistence.saveError = .writeFailed("disk full")
        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        store.update { $0.general.isIslandEnabled = false }

        XCTAssertFalse(store.settings.general.isIslandEnabled)
        XCTAssertEqual(store.lastError, .writeFailed("disk full"))

        persistence.saveError = nil
        store.update { $0.general.isIslandEnabled = true }
        XCTAssertNil(store.lastError)
    }

    func testRestoreDefaults() {
        var saved = AppSettings()
        saved.general.isIslandEnabled = false
        let persistence = FakePersistence(stored: saved)
        let store = SettingsStore(persistence: persistence, saveDelay: .zero)

        store.restoreDefaults()

        XCTAssertEqual(store.settings, .defaults)
        XCTAssertEqual(persistence.stored, .defaults)
    }

    func testDelayedSavesAreCoalescedAndFlushable() async throws {
        let persistence = FakePersistence()
        let store = SettingsStore(persistence: persistence, saveDelay: .seconds(60))

        store.update { $0.focus.workMinutes = 30 }
        store.update { $0.focus.workMinutes = 31 }
        store.update { $0.focus.workMinutes = 32 }
        XCTAssertEqual(persistence.saveCount, 0)

        store.flush()

        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(persistence.stored?.focus.workMinutes, 32)
    }

    func testFlushWithoutChangesDoesNotWrite() {
        let persistence = FakePersistence()
        let store = SettingsStore(persistence: persistence, saveDelay: .seconds(60))
        store.flush()
        XCTAssertEqual(persistence.saveCount, 0)
    }

    func testDelayedSaveEventuallyWrites() async throws {
        let persistence = FakePersistence()
        let store = SettingsStore(persistence: persistence, saveDelay: .milliseconds(20))

        store.update { $0.general.hapticFeedback = false }

        for _ in 0..<100 where persistence.saveCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(persistence.saveCount, 1)
    }
}

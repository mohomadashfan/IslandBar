import Foundation
import Observation

/// Abstraction over where settings live, so the store can be tested without touching disk.
public protocol SettingsPersisting: Sendable {
    func load() throws(PersistenceError) -> AppSettings?
    func save(_ settings: AppSettings) throws(PersistenceError)
    /// Called when stored data cannot be decoded, before defaults are written over it.
    func quarantineUnreadableData()
}

extension JSONFileStore: SettingsPersisting where Value == AppSettings {
    public func quarantineUnreadableData() {
        quarantineFile()
    }
}

/// Single source of truth for user preferences at runtime.
///
/// Every mutation goes through `update(_:)`. Writes are coalesced over `saveDelay` so dragging a
/// slider does not hit the disk on every frame; call `flush()` before termination. Failures never
/// crash the app: the in-memory value stays authoritative and the error is exposed as `lastError`.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public private(set) var lastError: PersistenceError?

    @ObservationIgnored private let persistence: any SettingsPersisting
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isDirty = false

    public init(persistence: any SettingsPersisting, saveDelay: Duration = .milliseconds(300)) {
        self.persistence = persistence
        self.saveDelay = saveDelay
        do {
            settings = try persistence.load()?.migrated() ?? .defaults
            lastError = nil
        } catch {
            if case .decodeFailed = error {
                persistence.quarantineUnreadableData()
            }
            settings = .defaults
            lastError = error
        }
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        guard updated != settings else { return }
        settings = updated
        scheduleSave()
    }

    public func restoreDefaults() {
        guard settings != .defaults else { return }
        settings = .defaults
        scheduleSave()
    }

    /// Writes any pending change immediately.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty else { return }
        persist()
    }

    private func scheduleSave() {
        isDirty = true
        guard saveDelay > .zero else {
            persist()
            return
        }
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func persist() {
        do {
            try persistence.save(settings)
            isDirty = false
            lastError = nil
        } catch {
            lastError = error
        }
    }
}

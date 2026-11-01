import Foundation
import IslandCore

/// A file the user parked on the shelf. Only a bookmark and display metadata are stored;
/// the file itself is never copied.
public struct ShelfItem: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var bookmark: Data
    public var name: String
    /// Last known path, for display and as a fallback if the bookmark cannot be resolved.
    public var path: String
    public var addedAt: Date

    public init(id: UUID = UUID(), bookmark: Data, name: String, path: String, addedAt: Date) {
        self.id = id
        self.bookmark = bookmark
        self.name = name
        self.path = path
        self.addedAt = addedAt
    }
}

public enum ShelfPolicy {
    /// Removes expired items, then keeps the newest `maxItems`.
    public static func pruned(_ items: [ShelfItem], now: Date, expiry: ShelfExpiry, maxItems: Int) -> [ShelfItem] {
        var kept = items
        if let interval = expiry.interval {
            kept.removeAll { now.timeIntervalSince($0.addedAt) >= interval }
        }
        kept.sort { $0.addedAt > $1.addedAt }
        if kept.count > max(maxItems, 1) {
            kept.removeLast(kept.count - max(maxItems, 1))
        }
        return kept
    }

    /// The next moment an item will expire, for scheduling a single wake-up.
    public static func nextExpiry(_ items: [ShelfItem], expiry: ShelfExpiry) -> Date? {
        guard let interval = expiry.interval else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(interval) }.min()
    }

    /// One spelling per file. `realpath` is used because `URL.resolvingSymlinksInPath()`
    /// deliberately maps `/private/var` back to `/var`, which would still allow duplicates.
    public static func canonicalPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        guard let resolved = realpath(standardized, nil) else { return standardized }
        defer { free(resolved) }
        return String(decoding: UnsafeRawBufferPointer(start: resolved, count: strlen(resolved)), as: UTF8.self)
    }

    /// Items to add, skipping paths already on the shelf or repeated within the batch.
    public static func newPaths(_ paths: [String], existing: [ShelfItem]) -> [String] {
        var seen = Set(existing.map(\.path))
        return paths.filter { seen.insert($0).inserted }
    }
}

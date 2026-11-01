import Foundation

public enum PersistenceError: Error, Equatable, Sendable {
    case readFailed(String)
    case decodeFailed(String)
    case writeFailed(String)
}

/// Stores a single `Codable` value as a pretty-printed JSON file.
///
/// Writes are atomic, so a crash mid-write never leaves a truncated file behind.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let fileURL: URL
    private let defaults: Value?

    /// - Parameter defaults: When given, stored JSON is merged over these values before decoding
    ///   so that missing keys are tolerated (see `JSONMerge`).
    public init(fileURL: URL, defaults: Value? = nil) {
        self.fileURL = fileURL
        self.defaults = defaults
    }

    /// Returns `nil` when nothing has been stored yet.
    public func load() throws(PersistenceError) -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .readFailed(error.localizedDescription)
        }

        do {
            if let defaults {
                return try JSONMerge.decode(Value.self, from: data, over: defaults)
            }
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw .decodeFailed(String(describing: error))
        }
    }

    public func save(_ value: Value) throws(PersistenceError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            // Owner-only: these files can hold notes, file paths and repository locations.
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    /// Moves an unreadable file aside (`<name>.corrupt-<timestamp>`) so it can be inspected
    /// instead of being silently overwritten. Returns the backup location, if one was made.
    @discardableResult
    public func quarantineFile() -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.appendingPathExtension("corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            return backup
        } catch {
            return nil
        }
    }
}

public enum AppPaths {
    /// `~/Library/Application Support/IslandBar`
    public static func applicationSupportDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "IslandBar", directoryHint: .isDirectory)
    }

    /// Makes the data folder and everything in it owner-only, including files written by
    /// versions that used default permissions.
    public static func secureDataDirectory() {
        let manager = FileManager.default
        let folder = applicationSupportDirectory()
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try? manager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: entry.path)
        }
    }

    public static func settingsFile() -> URL {
        file(named: "settings.json")
    }

    public static func file(named name: String) -> URL {
        applicationSupportDirectory().appending(path: name, directoryHint: .notDirectory)
    }

    /// Folder local hooks write developer events into. See docs/INTEGRATIONS.md.
    public static func eventInboxDirectory() -> URL {
        applicationSupportDirectory().appending(path: "events", directoryHint: .isDirectory)
    }
}

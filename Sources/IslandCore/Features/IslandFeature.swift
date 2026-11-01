import Foundation
import Observation

public struct FeatureID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension FeatureID {
    public static let media: FeatureID = "media"
    public static let shelf: FeatureID = "shelf"
    public static let focus: FeatureID = "focus"
    public static let systemMonitor: FeatureID = "systemMonitor"
    public static let developer: FeatureID = "developer"
    public static let notifications: FeatureID = "notifications"
    public static let privacyIndicators: FeatureID = "privacyIndicators"
    public static let mirror: FeatureID = "mirror"
    public static let soundMixer: FeatureID = "soundMixer"
    public static let bluetooth: FeatureID = "bluetooth"
    public static let caffeinate: FeatureID = "caffeinate"
}

/// Contract every feature module (Media, File Shelf, Focus, ...) implements.
///
/// `activate()` and `deactivate()` are synchronous: a feature that needs background work starts
/// its own `Task`s in `activate()` and cancels them in `deactivate()`. This keeps the registry
/// free of reentrancy problems when a feature is toggled rapidly.
@MainActor
public protocol IslandFeature: AnyObject {
    var id: FeatureID { get }
    var displayName: String { get }

    /// Start observing, polling or subscribing. Only called while inactive.
    func activate()
    /// Stop all work and release resources. Only called while active.
    func deactivate()
}

/// Owns the set of known features and drives their lifecycle.
@MainActor
@Observable
public final class FeatureRegistry {
    public enum RegistrationError: Error, Equatable {
        case duplicateID(FeatureID)
    }

    public private(set) var features: [any IslandFeature] = []
    public private(set) var activeIDs: Set<FeatureID> = []

    public init() {}

    public func register(_ feature: any IslandFeature) throws(RegistrationError) {
        guard !features.contains(where: { $0.id == feature.id }) else {
            throw .duplicateID(feature.id)
        }
        features.append(feature)
    }

    public func feature(for id: FeatureID) -> (any IslandFeature)? {
        features.first { $0.id == id }
    }

    public func isActive(_ id: FeatureID) -> Bool {
        activeIDs.contains(id)
    }

    /// Activates or deactivates a registered feature. Redundant calls are ignored.
    public func setEnabled(_ enabled: Bool, for id: FeatureID) {
        guard let feature = feature(for: id), enabled != isActive(id) else { return }
        if enabled {
            activeIDs.insert(id)
            feature.activate()
        } else {
            activeIDs.remove(id)
            feature.deactivate()
        }
    }

    /// Used on termination and before sleep.
    public func deactivateAll() {
        for feature in features where isActive(feature.id) {
            setEnabled(false, for: feature.id)
        }
    }
}

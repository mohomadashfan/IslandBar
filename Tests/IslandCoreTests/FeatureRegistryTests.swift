import IslandCore
import XCTest

@MainActor
private final class RecordingFeature: IslandFeature {
    let id: FeatureID
    let displayName: String
    private(set) var activations = 0
    private(set) var deactivations = 0

    init(_ id: FeatureID) {
        self.id = id
        self.displayName = id.rawValue
    }

    func activate() { activations += 1 }
    func deactivate() { deactivations += 1 }
}

@MainActor
final class FeatureRegistryTests: XCTestCase {
    func testRegistrationPreservesOrder() throws {
        let registry = FeatureRegistry()
        try registry.register(RecordingFeature("media"))
        try registry.register(RecordingFeature("focus"))

        XCTAssertEqual(registry.features.map(\.id), ["media", "focus"])
    }

    func testDuplicateRegistrationIsRejected() throws {
        let registry = FeatureRegistry()
        try registry.register(RecordingFeature("media"))

        XCTAssertThrowsError(try registry.register(RecordingFeature("media"))) { error in
            XCTAssertEqual(error as? FeatureRegistry.RegistrationError, .duplicateID("media"))
        }
        XCTAssertEqual(registry.features.count, 1)
    }

    func testRegistrationDoesNotActivate() throws {
        let registry = FeatureRegistry()
        let feature = RecordingFeature("media")
        try registry.register(feature)

        XCTAssertFalse(registry.isActive("media"))
        XCTAssertEqual(feature.activations, 0)
    }

    func testEnableAndDisableDriveLifecycleOnce() throws {
        let registry = FeatureRegistry()
        let feature = RecordingFeature("focus")
        try registry.register(feature)

        registry.setEnabled(true, for: "focus")
        registry.setEnabled(true, for: "focus")
        XCTAssertTrue(registry.isActive("focus"))
        XCTAssertEqual(feature.activations, 1)

        registry.setEnabled(false, for: "focus")
        registry.setEnabled(false, for: "focus")
        XCTAssertFalse(registry.isActive("focus"))
        XCTAssertEqual(feature.deactivations, 1)
    }

    func testUnknownFeatureIsIgnored() {
        let registry = FeatureRegistry()
        registry.setEnabled(true, for: "missing")
        XCTAssertTrue(registry.activeIDs.isEmpty)
    }

    func testDeactivateAllOnlyTouchesActiveFeatures() throws {
        let registry = FeatureRegistry()
        let active = RecordingFeature("media")
        let inactive = RecordingFeature("shelf")
        try registry.register(active)
        try registry.register(inactive)
        registry.setEnabled(true, for: "media")

        registry.deactivateAll()

        XCTAssertTrue(registry.activeIDs.isEmpty)
        XCTAssertEqual(active.deactivations, 1)
        XCTAssertEqual(inactive.deactivations, 0)
    }
}

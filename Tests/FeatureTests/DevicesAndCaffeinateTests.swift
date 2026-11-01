@testable import FeatureBluetooth
@testable import FeatureCaffeinate
import IslandCore
import XCTest

final class BluetoothLogicTests: XCTestCase {
    private let keyboard = BluetoothDevice(id: "hid|Magic Keyboard|1", name: "Magic Keyboard", kind: .keyboard, batteryPercent: 80)
    private let airpods = BluetoothDevice(id: "audio|AirPods Pro", name: "AirPods Pro", kind: .headphones)

    func testConnectAndDisconnectChanges() {
        let changes = BluetoothLogic.changes(from: [keyboard], to: [airpods])
        XCTAssertEqual(changes.connected, [airpods])
        XCTAssertEqual(changes.disconnected, [keyboard])
    }

    func testBatteryChangeIsNotAConnection() {
        var drained = keyboard
        drained.batteryPercent = 40
        XCTAssertEqual(BluetoothLogic.changes(from: [keyboard], to: [drained]), BluetoothLogic.Changes())
    }

    func testLowBatteryThresholds() {
        XCTAssertEqual(BluetoothLogic.lowBatteryThreshold(previous: 25, current: 19), 20)
        XCTAssertEqual(BluetoothLogic.lowBatteryThreshold(previous: 12, current: 4), 10)
        XCTAssertNil(BluetoothLogic.lowBatteryThreshold(previous: 19, current: 18))
        XCTAssertNil(BluetoothLogic.lowBatteryThreshold(previous: nil, current: 5))
        XCTAssertNil(BluetoothLogic.lowBatteryThreshold(previous: 5, current: nil))
    }

    func testHIDKinds() {
        XCTAssertEqual(BluetoothLogic.hidKind(usagePage: 1, usage: 6, name: "Keys"), .keyboard)
        XCTAssertEqual(BluetoothLogic.hidKind(usagePage: 1, usage: 2, name: "Logitech Pebble"), .mouse)
        XCTAssertEqual(BluetoothLogic.hidKind(usagePage: 1, usage: 5, name: "Controller"), .gameController)
        XCTAssertEqual(BluetoothLogic.hidKind(usagePage: 1, usage: 2, name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(BluetoothLogic.hidKind(usagePage: 12, usage: 1, name: "Remote"), .other)
    }

    func testMergingInterfacesKeepsBatteryAndKind() {
        let interfaceA = BluetoothDevice(id: "hid|Pebble|x", name: "Pebble", kind: .other)
        let interfaceB = BluetoothDevice(id: "hid|Pebble|x", name: "Pebble", kind: .mouse, batteryPercent: 55)
        XCTAssertEqual(BluetoothLogic.merged([interfaceA, interfaceB]), [BluetoothDevice(id: "hid|Pebble|x", name: "Pebble", kind: .mouse, batteryPercent: 55)])
    }

    func testSymbols() {
        XCTAssertEqual(airpods.symbolName, "airpodspro")
        XCTAssertEqual(keyboard.symbolName, "keyboard")
        XCTAssertEqual(BluetoothDevice(id: "a", name: "JBL Flip", kind: .speaker).symbolName, "hifispeaker")
    }

    func testLiveScanDoesNotRequirePermission() {
        // Reads the IORegistry and Core Audio device list; must not crash or prompt.
        _ = BluetoothHIDMonitor.scan()
        _ = BluetoothAudioMonitor.scan()
    }
}

final class CaffeinateStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testTimedSessionExpires() {
        let state = CaffeinateState.started(.hour1, at: t0)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.remaining(at: t0.addingTimeInterval(600)), 3000)
        XCTAssertFalse(state.hasExpired(at: t0.addingTimeInterval(3599)))
        XCTAssertTrue(state.hasExpired(at: t0.addingTimeInterval(3600)))
        XCTAssertEqual(state.remaining(at: t0.addingTimeInterval(9999)), 0)
    }

    func testIndefiniteNeverExpires() {
        let state = CaffeinateState.started(.indefinitely, at: t0)
        XCTAssertNil(state.endDate)
        XCTAssertFalse(state.hasExpired(at: t0.addingTimeInterval(1_000_000)))
    }

    @MainActor
    func testAssertionLifecycle() {
        let module = CaffeinateModule(activity: ActivityCenter())
        module.apply(.defaults)
        module.activate()
        module.start(.minutes15)
        XCTAssertTrue(module.state.isActive)
        XCTAssertNil(module.lastError)
        XCTAssertNotNil(module.liveActivityPriority)
        module.stop()
        XCTAssertFalse(module.state.isActive)
        XCTAssertNil(module.liveActivityPriority)
        module.deactivate()
    }
}

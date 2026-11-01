@testable import FeatureSystemMonitor
import XCTest

final class SystemMetricsTests: XCTestCase {
    func testCPUUsageFromTickDeltas() throws {
        let previous = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = CPUTicks(user: 160, system: 70, idle: 1020, nice: 0)
        // busy 80, idle 170 → 32%
        XCTAssertEqual(try XCTUnwrap(MetricMath.cpuUsage(from: previous, to: current)), 0.32, accuracy: 0.0001)
    }

    func testCPUUsageWithoutElapsedTicksIsNil() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertNil(MetricMath.cpuUsage(from: ticks, to: ticks))
    }

    func testCounterResetDoesNotUnderflow() {
        XCTAssertEqual(MetricMath.delta(1000, 1500), 500)
        XCTAssertEqual(MetricMath.delta(1000, 200), 200)
    }

    func testRate() {
        XCTAssertEqual(MetricMath.rate(bytes: 2000, over: 2), 1000)
        XCTAssertNil(MetricMath.rate(bytes: 2000, over: 0))
    }

    func testBatteryThresholdCrossing() {
        XCTAssertNil(MetricMath.crossedThreshold(previous: nil, current: 9))
        XCTAssertEqual(MetricMath.crossedThreshold(previous: 21, current: 20), 20)
        XCTAssertNil(MetricMath.crossedThreshold(previous: 20, current: 19))
        XCTAssertEqual(MetricMath.crossedThreshold(previous: 11, current: 9), 10)
        XCTAssertNil(MetricMath.crossedThreshold(previous: 9, current: 15))
    }

    func testSamplerReturnsPlausibleValues() async throws {
        let sampler = SystemSampler()
        var selection = MetricSelection()
        selection.battery = false
        _ = await sampler.sample(selection)
        try await Task.sleep(for: .milliseconds(200))
        let snapshot = await sampler.sample(selection)

        let cpu = try XCTUnwrap(snapshot.cpuUsage)
        XCTAssertTrue((0...1).contains(cpu))
        let used = try XCTUnwrap(snapshot.memoryUsed)
        XCTAssertGreaterThan(used, 0)
        XCTAssertLessThanOrEqual(used, snapshot.memoryTotal)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.diskTotal), 0)
        XCTAssertNotNil(snapshot.networkIn)
    }

    func testHardwareSummaryIsNotEmpty() {
        let info = SystemSampler.hardwareInfo()
        XCTAssertFalse(info.model.isEmpty)
        XCTAssertGreaterThan(info.logicalCores, 0)
        XCTAssertTrue(info.summary.contains("macOS"))
    }
}

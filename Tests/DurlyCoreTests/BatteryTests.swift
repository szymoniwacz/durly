import Foundation
import XCTest
@testable import DurlyCore

final class BatteryTests: XCTestCase {
    func testSeparatesDisplayedAndRawPercentagesAndDecodesSignedCurrent() {
        let snapshot = BatteryDecoder.decode(registry: [
            "CurrentCapacity": 3494, "MaxCapacity": 4552, "DesignCapacity": 8600,
            "CycleCount": 42, "Temperature": 3035,
            "Amperage": NSNumber(value: UInt64.max - 582),
            "ExternalConnected": true, "IsCharging": false, "Voltage": 11891
        ], powerSource: ["Current Capacity": 81, "Max Capacity": 100,
                         "Power Source State": "AC Power", "BatteryHealth": "Poor"])
        XCTAssertEqual(snapshot.percentage, 81)
        XCTAssertEqual(snapshot.rawChargePercentage ?? 0, 76.76, accuracy: 0.01)
        XCTAssertEqual(snapshot.capacityRetention ?? 0, 52.93, accuracy: 0.01)
        XCTAssertEqual(snapshot.currentMilliamps, -583)
        XCTAssertEqual(snapshot.temperatureCelsius, 30.35)
        XCTAssertEqual(snapshot.cycles, 42)
        XCTAssertEqual(snapshot.externalPower, true)
        XCTAssertEqual(snapshot.isCharging, false)
        XCTAssertEqual(snapshot.condition, "Poor")
    }

    func testMissingAndInvalidValuesAreNotInvented() {
        let snapshot = BatteryDecoder.decode(registry: [
            "CycleCount": -1, "Temperature": 999999, "MaxCapacity": 0,
            "Amperage": "bad", "ExternalConnected": 2, "DesignCapacity": true
        ], powerSource: ["Current Capacity": 101, "Max Capacity": 100])
        XCTAssertNil(snapshot.percentage)
        XCTAssertNil(snapshot.cycles)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.capacityRetention)
        XCTAssertNil(snapshot.rawChargePercentage)
        XCTAssertNil(snapshot.currentMilliamps)
        XCTAssertNil(snapshot.externalPower)
        XCTAssertNil(snapshot.condition)
    }

    func testMockProviderAndStaleness() {
        let now = Date(timeIntervalSince1970: 1000)
        let value = BatteryDecoder.decode(registry: [:], powerSource: [:], capturedAt: now)
        let provider = MockProvider(value: value)
        let monitor = BatteryMonitor(provider: provider)
        monitor.refresh()
        XCTAssertEqual(monitor.freshSnapshot(at: now), value)
        XCTAssertNil(monitor.freshSnapshot(at: now.addingTimeInterval(31)))
        provider.shouldFail = true
        monitor.refresh()
        XCTAssertTrue(monitor.failed)
        XCTAssertNil(monitor.snapshot)
    }

    private final class MockProvider: BatteryProvider {
        let value: BatterySnapshot
        var shouldFail = false
        init(value: BatterySnapshot) { self.value = value }
        func read() throws -> BatterySnapshot {
            if shouldFail { throw BatteryReadError.unavailable }
            return value
        }
    }
}

import Foundation
import Dispatch
#if !MANUAL_TESTS
import XCTest
#endif
import DurlyCore

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

    func testCapacityPairsNeverMixKeyFamilies() {
        let complete = BatteryDecoder.decode(registry: [
            "AppleRawCurrentCapacity": 3000, "AppleRawMaxCapacity": 4000,
            "CurrentCapacity": 80, "MaxCapacity": 100
        ], powerSource: [:])
        XCTAssertEqual(complete.currentCapacity, 3000)
        XCTAssertEqual(complete.maxCapacity, 4000)
        XCTAssertEqual(complete.rawChargePercentage, 75)

        let fallback = BatteryDecoder.decode(registry: [
            "AppleRawCurrentCapacity": 3000, "CurrentCapacity": 80, "MaxCapacity": 100
        ], powerSource: [:])
        XCTAssertEqual(fallback.currentCapacity, 80)
        XCTAssertEqual(fallback.maxCapacity, 100)

        let partial = BatteryDecoder.decode(registry: [
            "AppleRawMaxCapacity": 4000, "CurrentCapacity": 80
        ], powerSource: [:])
        XCTAssertNil(partial.currentCapacity)
        XCTAssertEqual(partial.maxCapacity, 4000)
        XCTAssertNil(partial.rawChargePercentage)

        let invalid = BatteryDecoder.decode(registry: [
            "AppleRawCurrentCapacity": 5000, "AppleRawMaxCapacity": 4000
        ], powerSource: [:])
        XCTAssertNil(invalid.rawChargePercentage)
    }

    func testDisplaySettingsPersistAndValidate() {
        let suite = "durly.tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplaySettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), DisplaySettings())
        let changed = DisplaySettings(showPercentage: false, showDetails: true, refreshSeconds: 60)
        store.save(changed)
        XCTAssertEqual(DisplaySettingsStore(defaults: defaults).load(), changed)
        XCTAssertEqual(DisplaySettings(refreshSeconds: 0).refreshSeconds, 10)
        defaults.set(["showPercentage": "invalid", "showDetails": 1, "refreshSeconds": 999],
                     forKey: "durly.display.v1")
        XCTAssertEqual(store.load(), DisplaySettings())
        defaults.set(["showPercentage": false, "showDetails": true, "refreshSeconds": true],
                     forKey: "durly.display.v1")
        XCTAssertEqual(store.load(), DisplaySettings(showPercentage: false, showDetails: true))
    }

    func testBatteryHealthPresentationSeverity() {
        XCTAssertEqual(BatteryHealthSeverity.classify(" Normal "), .normal)
        XCTAssertEqual(BatteryHealthSeverity.classify("Good"), .normal)
        XCTAssertEqual(BatteryHealthSeverity.classify("Check Battery"), .warning)
        XCTAssertEqual(BatteryHealthSeverity.classify("Replace Soon"), .warning)
        XCTAssertEqual(BatteryHealthSeverity.classify("Service Recommended"), .service)
        XCTAssertEqual(BatteryHealthSeverity.classify("Poor"), .service)
        XCTAssertEqual(BatteryHealthSeverity.classify("Replace Now"), .service)
        XCTAssertEqual(BatteryHealthSeverity.classify("unrecognized"), .unknown)
        XCTAssertEqual(BatteryHealthSeverity.classify(" "), .unknown)
        XCTAssertEqual(BatteryHealthSeverity.classify(nil), .unknown)
    }

    func testBatteryPresentationSymbolsAndPowerStates() {
        for (value, symbol) in [(0, "battery.0"), (12, "battery.0"), (13, "battery.25"),
                                (37, "battery.25"), (38, "battery.50"), (62, "battery.50"),
                                (63, "battery.75"), (87, "battery.75"), (88, "battery.100"), (100, "battery.100")] {
            XCTAssertEqual(BatteryPresentation.symbol(for: value), symbol)
        }
        XCTAssertEqual(BatteryPresentation.symbol(for: nil), "questionmark.circle")
        XCTAssertEqual(BatteryPresentation.symbol(for: -1), "questionmark.circle")
        XCTAssertEqual(BatteryPresentation.symbol(for: 101), "questionmark.circle")
        func state(_ ac: Bool, _ charging: Bool) -> String {
            BatteryPresentation.chargeState(for: BatteryDecoder.decode(
                registry: ["ExternalConnected": ac, "IsCharging": charging], powerSource: [:]))
        }
        XCTAssertEqual(state(true, true), "Charging")
        XCTAssertEqual(state(true, false), "On AC · Not charging")
        XCTAssertEqual(state(false, false), "On battery")
        XCTAssertEqual(state(false, true), "Power state unavailable")
        XCTAssertEqual(BatteryPresentation.chargeState(for: nil), "Battery data unavailable")
        XCTAssertEqual(BatteryPresentation.chargeState(for: BatteryDecoder.decode(registry: [:], powerSource: [:])), "Power state unavailable")
    }

    func testPresentationFreshnessTracksInterval() {
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = BatteryDecoder.decode(registry: [:], powerSource: [:], capturedAt: now)
        let later = now.addingTimeInterval(20)
        XCTAssertNil(BatteryPresentation.fresh(snapshot, settings: DisplaySettings(refreshSeconds: 10), at: later))
        XCTAssertEqual(BatteryPresentation.fresh(snapshot, settings: DisplaySettings(refreshSeconds: 30), at: later), snapshot)
        XCTAssertNil(BatteryPresentation.fresh(snapshot, settings: DisplaySettings(), at: now.addingTimeInterval(-1)))
        XCTAssertNil(BatteryPresentation.fresh(nil, settings: DisplaySettings(), at: now))
    }

    func testPowerControlAlwaysReadOnly() {
        let target = ControlCapabilityDetector.detect(model: "MacBookPro11,5", os: "12.7.6", architecture: "x86_64")
        XCTAssertEqual(target.reason, .unverifiedBackend)
        XCTAssertEqual(target.canWrite, false)
        XCTAssertEqual(ControlCapabilityDetector.detect(model: "other", os: "12.7.6", architecture: "x86_64").reason, .unsupportedDevice)
        XCTAssertEqual(ControlCapabilityDetector.detect(model: "MacBookPro11,5", os: "12.7.5", architecture: "x86_64").canWrite, false)
        XCTAssertEqual(ControlCapabilityDetector.detect(model: "MacBookPro11,5", os: "12.7.6", architecture: "arm64").canWrite, false)
        let backend = ReadOnlyBackend()
        expectControlError(.unverifiedBackend) { try backend.apply(limit: 80, snapshot: nil, at: Date()) }
        expectControlError(.unverifiedBackend) { try backend.pause(snapshot: nil, at: Date()) }
    }

    func testTransactionRejectsUnsafeInputs() {
        let context = controlContext()
        expectControlError(.permissionDenied) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(authorized: false)) }
        expectControlError(.competingController) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(competitorAbsent: false)) }
        expectControlError(.staleTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(age: 16)) }
        expectControlError(.staleTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(age: -1)) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(health: "Check Battery")) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(ac: false)) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(temperature: 4500)) }
        expectControlError(.invalidLimit) { _ = try ControlTransaction.prepare(limit: 49, live: 76, existing: nil, context: context) }
        expectControlError(.unknownBaseline) { _ = try ControlTransaction.prepare(limit: 80, live: 15, existing: nil, context: context) }
    }

    func testSimulatedControlAndPauseRestoreBaseline() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        do {
            try coordinator.apply(limit: 82, context: controlContext())
            XCTAssertEqual(transport.value, 82)
            XCTAssertEqual(journal.record, RecoveryRecord(baseline: 76, expected: 82, phase: .applied))
            try coordinator.pause(context: controlContext())
            XCTAssertEqual(transport.value, 76)
            XCTAssertNil(journal.record)
            XCTAssertEqual(transport.writes, [82, 76])
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
    }

    func testSimulatedControlFailureRetainsRecoveryRecord() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        transport.failWrite = true
        expectControlError(.writeFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(journal.record, RecoveryRecord(baseline: 76, expected: 82))
        transport.failWrite = false
        expectControlError(.recoveryRequired) { try coordinator.apply(limit: 80, context: self.controlContext()) }
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testSimulatedDriftAndReadbackMismatch() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        transport.ignoreWrite = true
        expectControlError(.readbackMismatch) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(journal.record, RecoveryRecord(baseline: 76, expected: 82))
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testSimulatedJournalFailurePreventsWrite() {
        let transport = TestTransport()
        let journal = TestJournal()
        journal.failSave = true
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        expectControlError(.journalFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [])
    }

    func testRestartCannotRestoreUncertainOrPreviouslyAppliedTransaction() {
        for uncertain in [true, false] {
            let transport = TestTransport()
            let journal = TestJournal()
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
            transport.failAfterWrite = uncertain
            if uncertain {
                expectControlError(.writeFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
            } else {
                do { try coordinator.apply(limit: 82, context: controlContext()) }
                catch { XCTAssertEqual(String(describing: error), "unexpected error") }
            }
            XCTAssertEqual(transport.value, 82)
            XCTAssertEqual(journal.record?.phase, uncertain ? .prepared : .applied)
            transport.failAfterWrite = false
            let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal)
            expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
            expectControlError(.recoveryRequired) { try restarted.apply(limit: 80, context: self.controlContext()) }
            XCTAssertEqual(transport.writes, [82])
        }
    }

    func testJournalLoadFailureLatchesApplyAndPause() {
        for pause in [true, false] {
            let transport = TestTransport()
            let journal = TestJournal()
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
            journal.failLoad = true
            if pause {
                expectControlError(.journalFailed) { try coordinator.pause(context: self.controlContext()) }
            } else {
                expectControlError(.journalFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
            }
            journal.failLoad = false
            expectControlError(.recoveryRequired) { try coordinator.apply(limit: 82, context: self.controlContext()) }
            expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
            XCTAssertEqual(transport.writes, [])
        }
    }

    func testFailedRollbackRetainsRestoringPhase() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        transport.failWrite = true
        expectControlError(.writeFailed) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(journal.record?.phase, .restoring)
        transport.failWrite = false
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82, 76])
    }

    func testFailedJournalClearDoesNotRepeatRollback() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        journal.failClear = true
        expectControlError(.journalFailed) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.value, 76)
        XCTAssertEqual(journal.record?.phase, .restoring)
        journal.failClear = false
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82, 76])
    }

    func testConcurrentCoordinatorsCannotReplaceBaseline() {
        let transport = TestTransport()
        let journal = TestJournal()
        let first = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        let second = SimulatedTransactionCoordinator(transport: transport, journal: journal)
        let context = controlContext()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            let coordinator = index % 2 == 0 ? first : second
            do { try coordinator.apply(limit: 82, context: context) }
            catch ControlBlock.recoveryRequired { }
            catch { /* Unexpected errors are detected by the final state assertions. */ }
        }
        XCTAssertEqual(transport.writes, [82])
        XCTAssertEqual(journal.record, RecoveryRecord(baseline: 76, expected: 82, phase: .applied))
    }

    private func controlContext(authorized: Bool = true, competitorAbsent: Bool = true, age: TimeInterval = 0,
                                health: String = "Normal", ac: Bool = true, temperature: Int = 3000) -> ControlContext {
        let now = Date(timeIntervalSince1970: 1000)
        let sample = BatteryDecoder.decode(registry: ["ExternalConnected": ac, "IsCharging": false,
            "Temperature": temperature, "BatteryHealth": health], powerSource: ["Current Capacity": 79, "Max Capacity": 100],
            capturedAt: now.addingTimeInterval(-age))
        return ControlContext(authorized: authorized, competitorAbsent: competitorAbsent, snapshot: sample, now: now)
    }

    private func expectControlError(_ expected: ControlBlock, _ operation: () throws -> Void) {
        do {
            try operation()
            XCTAssertEqual("no error", expected.rawValue)
        } catch {
            XCTAssertEqual(error as? ControlBlock, expected)
        }
    }

    private final class TestTransport: LimitTransport {
        var value = 76
        var writes: [Int] = []
        var failWrite = false
        var ignoreWrite = false
        var failAfterWrite = false
        func read() throws -> Int { value }
        func write(_ value: Int) throws {
            writes.append(value)
            if failWrite { throw ControlBlock.writeFailed }
            if !ignoreWrite { self.value = value }
            if failAfterWrite { throw ControlBlock.writeFailed }
        }
    }

    private final class TestJournal: RecoveryJournal {
        var record: RecoveryRecord?
        var failSave = false
        var failLoad = false
        var failClear = false
        func load() throws -> RecoveryRecord? {
            if failLoad { throw ControlBlock.journalFailed }
            return record
        }
        func save(_ record: RecoveryRecord) throws {
            if failSave { throw ControlBlock.journalFailed }
            self.record = record
        }
        func clear() throws {
            if failClear { throw ControlBlock.journalFailed }
            record = nil
        }
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

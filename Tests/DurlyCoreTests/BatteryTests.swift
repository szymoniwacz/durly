import Foundation
import Dispatch
#if !MANUAL_TESTS
import XCTest
#endif
import DurlyCore
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

final class BatteryTests: XCTestCase {
    func testHistoryMigratesExistingDatabaseAndExportsArchive() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("history.sqlite")
            let old = UUID()
            let date = Date(timeIntervalSince1970: 1234.125)
            let sample = BatteryDecoder.decode(registry: ["MaxCapacity": 4552], powerSource: [:], capturedAt: date)
            let payload = String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)
            var raw: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
            let sql = "CREATE TABLE battery_epoch(id TEXT PRIMARY KEY, created_at REAL NOT NULL);" +
                "CREATE TABLE sample(id INTEGER PRIMARY KEY, epoch TEXT NOT NULL REFERENCES battery_epoch(id), captured_at REAL NOT NULL, payload TEXT NOT NULL, UNIQUE(epoch,captured_at));" +
                "INSERT INTO battery_epoch VALUES ('" + old.uuidString + "',1234.125);" +
                "INSERT INTO sample(epoch,captured_at,payload) VALUES ('" + old.uuidString + "',1234.125,'" + payload + "');" +
                "PRAGMA user_version=1;"
            XCTAssertEqual(sqlite3_exec(raw, sql, nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_close(raw), SQLITE_OK)
            let store = try BatteryHistory(url: url)
            let migrated = try store.samples(epoch: old)
            XCTAssertEqual(migrated, [sample])
            let current = try store.createEpoch(at: date.addingTimeInterval(60))
            let session = UUID()
            try store.appendEvent(epoch: current, at: date, kind: .recordingStarted, session: session)
            try store.append(sample, epoch: current, session: session)
            try store.appendEvent(epoch: old, at: date, kind: .recordingStopped)
            let output = folder.appendingPathComponent("archive.jsonl")
            try store.export(epoch: old, to: output)
            let lines = try String(contentsOf: output, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(lines.count, 3)
            let legacy = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
            XCTAssertNil(legacy?["session"])
            let currentOutput = folder.appendingPathComponent("current.jsonl")
            let reopened = try BatteryHistory(url: url)
            try reopened.export(epoch: current, to: currentOutput)
            let currentLines = try String(contentsOf: currentOutput, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(currentLines.count, 3)
            for line in currentLines.dropFirst() {
                let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                XCTAssertEqual(record?["session"] as? String, session.uuidString)
            }
            XCTAssertTrue(lines.allSatisfy { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) != nil })
            do {
                try store.export(epoch: old, to: output)
                XCTAssertTrue(false)
            } catch {}
            do {
                try store.deleteArchivedEpoch(current)
                XCTAssertTrue(false)
            } catch {}
            try store.deleteArchivedEpoch(old)
            let remaining = try store.epochs()
            XCTAssertEqual(remaining.map { $0.id }, [current])
            let removed = try store.samples(epoch: old)
            let events = try store.events(epoch: old)
            let preserved = try store.samples(epoch: current)
            XCTAssertTrue(removed.isEmpty)
            XCTAssertTrue(events.isEmpty)
            XCTAssertEqual(preserved, [sample])
        } catch { XCTAssertTrue(false) }
    }

    func testHistoryRejectsFutureSchemaAndInvalidPath() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(raw, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(raw), SQLITE_OK)
        do {
            _ = try BatteryHistory(url: url)
            XCTAssertTrue(false)
        } catch {}
        do {
            _ = try BatteryHistory(url: url.appendingPathComponent("invalid.sqlite"))
            XCTAssertTrue(false)
        } catch {}
    }

    func testHistoryEventsPersistAndRemainSeparated() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try BatteryHistory(url: url)
            let date = Date(timeIntervalSince1970: 1000.125)
            let old = try store.createEpoch(at: date)
            let new = try store.createEpoch(at: date.addingTimeInterval(100))
            let session = UUID()
            try store.appendEvent(epoch: old, at: date, kind: .recordingStarted, session: session)
            try store.appendEvent(epoch: old, at: date.addingTimeInterval(1), kind: .manualSMC, detail: "BCLM: 76", session: session)
            try store.appendEvent(epoch: old, at: date.addingTimeInterval(2), kind: .sleep, session: session)
            let reopened = try BatteryHistory(url: url)
            let events = try reopened.events(epoch: old)
            let newEvents = try reopened.events(epoch: new)
            XCTAssertEqual(events.map { $0.kind }, [.sleep, .manualSMC, .recordingStarted])
            XCTAssertEqual(events.map { $0.session }, [session, session, session])
            XCTAssertEqual(events.last?.capturedAt, date)
            XCTAssertEqual(events[1].detail, "BCLM: 76")
            XCTAssertTrue(newEvents.isEmpty)
            do {
                try reopened.appendEvent(epoch: UUID(), at: date, kind: .sleep)
                XCTAssertTrue(false)
            } catch {}
        } catch { XCTAssertTrue(false) }
    }

    func testHistoryCaptureRequiresConfirmationAndBoundsSampling() {
        var gate = HistoryCapture()
        let t = Date(timeIntervalSince1970: 1000)
        func sample(_ offset: Double, _ ac: Bool) -> BatterySnapshot {
            BatteryDecoder.decode(registry: ["ExternalConnected": ac],
                powerSource: ["Current Capacity": 80, "Max Capacity": 100],
                capturedAt: t.addingTimeInterval(offset))
        }
        let first = sample(0, true)
        XCTAssertTrue(!gate.shouldCapture(first, uptime: 100, now: t))
        gate.select(UUID())
        XCTAssertTrue(gate.shouldCapture(first, uptime: 100, now: t))
        gate.recorded(first, uptime: 100)
        XCTAssertTrue(!gate.shouldCapture(sample(10, true), uptime: 110, now: t.addingTimeInterval(10)))
        XCTAssertTrue(gate.shouldCapture(sample(10, false), uptime: 110, now: t.addingTimeInterval(10)))
        XCTAssertTrue(!gate.shouldCapture(sample(60, true), uptime: 160, now: t.addingTimeInterval(60)))
        XCTAssertTrue(!gate.shouldCapture(sample(3600, true), uptime: 3700, now: t.addingTimeInterval(3600)))
        XCTAssertTrue(!gate.shouldCapture(first, uptime: 161, now: t.addingTimeInterval(61)))
        let changed = BatteryDecoder.decode(registry: ["ExternalConnected": true, "Voltage": 11800],
            powerSource: ["Current Capacity": 80, "Max Capacity": 100], capturedAt: t.addingTimeInterval(5))
        XCTAssertTrue(gate.shouldCapture(changed, uptime: 105, now: t.addingTimeInterval(5)))
        gate.suspend()
        XCTAssertTrue(!gate.shouldCapture(sample(60, true), uptime: 160, now: t.addingTimeInterval(60)))
    }

    func testHistoryPersistenceAndEpochSeparation() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let date = Date(timeIntervalSince1970: 1000)
            let old = BatteryDecoder.decode(registry: ["MaxCapacity": 4552], powerSource: [:], capturedAt: date)
            let new = BatteryDecoder.decode(registry: ["MaxCapacity": 8600], powerSource: [:], capturedAt: date)
            let store = try BatteryHistory(url: url)
            let a = try store.createEpoch(at: date)
            let b = try store.createEpoch(at: date)
            try store.append(old, epoch: a)
            try store.append(new, epoch: b)
            let reopened = try BatteryHistory(url: url)
            let latest = try reopened.latestEpoch()
            XCTAssertEqual(latest, b)
            let oldSamples = try reopened.samples(epoch: a)
            let newSamples = try reopened.samples(epoch: b)
            XCTAssertEqual(oldSamples, [old])
            XCTAssertEqual(newSamples, [new])
            XCTAssertNil(newSamples.first?.temperatureCelsius)
            do {
                try reopened.append(new, epoch: a)
                XCTAssertTrue(false)
            } catch {}
            do {
                try reopened.append(new, epoch: UUID())
                XCTAssertTrue(false)
            } catch {}
            let epochs = try reopened.epochs()
            XCTAssertEqual(epochs.map { $0.id }, [b, a])
            XCTAssertEqual(epochs.map { $0.sampleCount }, [1, 1])
            let baseline = try reopened.observedBaseline(epoch: a)
            XCTAssertEqual(baseline, old)
            let unchanged = try reopened.samples(epoch: a)
            XCTAssertEqual(unchanged, [old])
        } catch {
            XCTAssertTrue(false)
        }
    }

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
        expectControlError(.permissionDenied) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(authorized: false), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.competingController) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(competitorAbsent: false), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.staleTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(age: 16), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.staleTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(age: -1), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(health: "Check Battery"), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(ac: false), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.unsafeTelemetry) { _ = try ControlTransaction.prepare(limit: 80, live: 76, existing: nil, context: self.controlContext(temperature: 4500), transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.invalidLimit) { _ = try ControlTransaction.prepare(limit: 49, live: 76, existing: nil, context: context, transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        expectControlError(.unknownBaseline) { _ = try ControlTransaction.prepare(limit: 80, live: 15, existing: nil, context: context, transactionID: UUID(), at: Date(timeIntervalSince1970: 1000)) }
    }

    func testSimulatedControlAndPauseRestoreBaseline() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do {
            try coordinator.apply(limit: 82, context: controlContext())
            XCTAssertEqual(transport.value, 82)
            assertRecord(journal.record, phase: .applied)
            try coordinator.pause(context: controlContext())
            XCTAssertEqual(transport.value, 76)
            XCTAssertNil(journal.record)
            XCTAssertEqual(transport.writes, [82, 76])
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
    }

    func testSimulatedControlFailureRetainsRecoveryRecord() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        transport.failWrite = true
        expectControlError(.writeFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        assertRecord(journal.record, phase: .prepared)
        transport.failWrite = false
        expectControlError(.recoveryRequired) { try coordinator.apply(limit: 80, context: self.controlContext()) }
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testSimulatedDriftAndReadbackMismatch() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        transport.ignoreWrite = true
        expectControlError(.readbackMismatch) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        assertRecord(journal.record, phase: .prepared)
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testSimulatedJournalFailurePreventsWrite() {
        let transport = TestTransport()
        let journal = TestJournal()
        journal.failSave = true
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.journalFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [])
    }

    func testRestartCannotRestoreUncertainOrPreviouslyAppliedTransaction() {
        for uncertain in [true, false] {
            let transport = TestTransport()
            let journal = TestJournal()
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
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
            let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
            expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
            expectControlError(.recoveryRequired) { try restarted.apply(limit: 80, context: self.controlContext()) }
            XCTAssertEqual(transport.writes, [82])
        }
    }

    func testJournalLoadFailureLatchesApplyAndPause() {
        for pause in [true, false] {
            let transport = TestTransport()
            let journal = TestJournal()
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
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
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        transport.failWrite = true
        expectControlError(.writeFailed) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(journal.record?.phase, .restoring)
        transport.failWrite = false
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82, 76])
    }

    func testFailedJournalClearDoesNotRepeatRollback() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
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
        let first = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        let second = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        let context = controlContext()
        let outcomes = ConcurrentOutcomes()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            let coordinator = index % 2 == 0 ? first : second
            outcomes.record { try coordinator.apply(limit: 82, context: context) }
        }
        XCTAssertEqual(outcomes.values.sorted(), (Array(repeating: "recoveryRequired", count: 31) + ["success"]).sorted())
        XCTAssertEqual(transport.writes, [82])
        assertRecord(journal.record, phase: .applied)
    }

    func testReplacementRecordWithSameValuesCannotAuthorizeRestore() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        let original = journal.record
        let replacement = RecoveryRecord(baseline: 76, expected: 82, phase: .applied)
        XCTAssertTrue(original?.transactionID != replacement.transactionID)
        journal.record = replacement
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(journal.record, replacement)
        XCTAssertEqual(transport.writes, [82])
    }

    func testTransactionIdentitySurvivesPhaseTransitions() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do {
            try coordinator.apply(limit: 82, context: controlContext())
            try coordinator.pause(context: controlContext())
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        XCTAssertEqual(journal.saved.map { $0.phase }, [.prepared, .applied, .restoring])
        XCTAssertEqual(Set(journal.saved.map { $0.transactionID }).count, 1)
        XCTAssertNil(journal.record)
    }

    func testTelemetryExpiresBeforeApplyOrRestoreWrite() {
        for pause in [false, true] {
            let transport = TestTransport()
            let journal = TestJournal()
            var now = Date(timeIntervalSince1970: 1000)
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { now })
            if pause {
                do { try coordinator.apply(limit: 82, context: controlContext()) }
                catch { XCTAssertEqual(String(describing: error), "unexpected error") }
            }
            journal.onSave = { now = Date(timeIntervalSince1970: 1016) }
            if pause {
                expectControlError(.staleTelemetry) { try coordinator.pause(context: self.controlContext()) }
            } else {
                expectControlError(.staleTelemetry) { try coordinator.apply(limit: 82, context: self.controlContext()) }
            }
            XCTAssertEqual(transport.writes, pause ? [82] : [])
            XCTAssertEqual(journal.record?.phase, pause ? .restoring : .prepared)
            now = Date(timeIntervalSince1970: 1000)
            expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        }
    }

    func testUnexpectedJournalStateLatchesEvenAfterRecordDisappears() {
        for missing in [false, true] {
            let transport = TestTransport()
            let journal = TestJournal()
            let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
            if missing {
                do { try coordinator.apply(limit: 82, context: controlContext()) }
                catch { XCTAssertEqual(String(describing: error), "unexpected error") }
            } else {
                journal.record = RecoveryRecord(baseline: 76, expected: 82, phase: .applied)
            }
            let original = journal.record
            if missing { journal.record = nil }
            expectControlError(.recoveryRequired) { try coordinator.apply(limit: 80, context: self.controlContext()) }
            journal.record = missing ? original : nil
            expectControlError(.recoveryRequired) { try coordinator.apply(limit: 80, context: self.controlContext()) }
            expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
            XCTAssertEqual(transport.writes, missing ? [82] : [])
        }
    }

    func testConcurrentApplyAndPausePreserveOwnerAndBaseline() {
        let transport = TestTransport()
        let journal = TestJournal()
        let context = controlContext()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: context) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        let outcomes = ConcurrentOutcomes()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            outcomes.record {
                if index == 0 { try coordinator.apply(limit: 80, context: context) }
                else { try coordinator.pause(context: context) }
            }
        }
        // Either legal serialization is accepted, but no partial interleaving.
        if outcomes.values.contains("recoveryRequired") {
            XCTAssertEqual(outcomes.values.sorted(), ["recoveryRequired", "success"])
            XCTAssertEqual(transport.writes, [82, 76])
            XCTAssertNil(journal.record)
        } else {
            XCTAssertEqual(outcomes.values.sorted(), ["success", "success"])
            XCTAssertEqual(transport.writes, [82, 76, 80])
            XCTAssertEqual(journal.record?.baseline, 76)
            XCTAssertEqual(journal.record?.expected, 80)
            XCTAssertEqual(journal.record?.phase, .applied)
        }
    }

    func testAuthoritativeClockValidatesSnapshotAtActualOperationTime() {
        let transport = TestTransport()
        let journal = TestJournal()
        var now = Date(timeIntervalSince1970: 1000)
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { now })
        // The snapshot is one second ahead of the original fixture time,
        // but is valid when the coordinator actually handles the operation.
        let context = controlContext(age: -1)
        now = Date(timeIntervalSince1970: 1001)
        do {
            try coordinator.apply(limit: 82, context: context)
            try coordinator.pause(context: context)
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        XCTAssertEqual(transport.writes, [82, 76])
        XCTAssertNil(journal.record)
    }

    func testExternalDriftImmediatelyBeforeApplyPreventsWrite() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        journal.onSave = { transport.value = 79 }
        expectControlError(.recoveryRequired) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [])
        XCTAssertEqual(transport.value, 79)
        assertRecord(journal.record, phase: .prepared)
        journal.onSave = nil
        expectControlError(.recoveryRequired) { try coordinator.apply(limit: 80, context: self.controlContext()) }
    }

    func testExternalDriftImmediatelyBeforeRestorePreventsWrite() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        journal.onSave = { transport.value = 79 }
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
        XCTAssertEqual(transport.value, 79)
        assertRecord(journal.record, phase: .restoring)
        journal.onSave = nil
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
    }

    func testFailureSavingAppliedPhaseRetainsPreparedRecordAndBlocksRecovery() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        journal.failPhase = .applied
        expectControlError(.journalFailed) { try coordinator.apply(limit: 82, context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
        XCTAssertEqual(transport.value, 82)
        assertRecord(journal.record, phase: .prepared)
        journal.failPhase = nil
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testFailureSavingRestoringPhasePreventsRollbackWrite() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        journal.failPhase = .restoring
        expectControlError(.journalFailed) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
        XCTAssertEqual(transport.value, 82)
        assertRecord(journal.record, phase: .applied)
        journal.failPhase = nil
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82])
    }

    func testRollbackReadbackMismatchRetainsRecoveryRecord() {
        let transport = TestTransport()
        let journal = TestJournal()
        let coordinator = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        do { try coordinator.apply(limit: 82, context: controlContext()) }
        catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        transport.ignoreWrite = true
        expectControlError(.readbackMismatch) { try coordinator.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82, 76])
        XCTAssertEqual(transport.value, 82)
        assertRecord(journal.record, phase: .restoring)
        transport.ignoreWrite = false
        expectControlError(.recoveryRequired) { try coordinator.pause(context: self.controlContext()) }
        let restarted = SimulatedTransactionCoordinator(transport: transport, journal: journal, clock: { Date(timeIntervalSince1970: 1000) })
        expectControlError(.recoveryRequired) { try restarted.pause(context: self.controlContext()) }
        XCTAssertEqual(transport.writes, [82, 76])
    }

    func testSMCReadOnlyExactFramesForBothKeys() {
        for key in SMCChargeKey.allCases {
            var requests: [[UInt8]] = []
            let reader = SMCChargeReader { request in
                requests.append(request)
                var reply = self.smcMetadata()
                if requests.count == 2 { reply[48] = 76 }
                return reply
            }
            do { let actual = try reader.read(key); XCTAssertEqual(actual, 76) }
            catch { XCTAssertEqual(String(describing: error), "unexpected error") }
            var expected = [UInt8](repeating: 0, count: 80)
            expected.replaceSubrange(0..<4, with: key == .bclm ? [0x4D, 0x4C, 0x43, 0x42] : [0x4C, 0x43, 0x46, 0x42])
            expected[42] = 9
            var read = expected
            read[28] = 1
            read[42] = 5
            XCTAssertEqual(requests, [expected, read])
        }
    }

    func testSMCInvalidMetadataNeverRequestsData() {
        for (size, type) in [(0, 0x75693820), (2, 0x75693820), (255, 0x75693820), (1, 0x666C6167)] {
            var calls = 0
            let reader = SMCChargeReader { _ in
                calls += 1
                var reply = self.smcMetadata()
                reply[28] = UInt8(size)
                for i in 0..<4 { reply[32 + i] = UInt8(truncatingIfNeeded: type >> (8 * i)) }
                return reply
            }
            expectSMCError(.unexpectedMetadata(size: UInt32(size), type: UInt32(type))) { _ = try reader.read(.bclm) }
            XCTAssertEqual(calls, 1)
        }
    }

    func testSMCRejectsMalformedFramesAtBothStages() {
        for stage in [1, 2] {
            for length in [0, 40, 79, 81] {
                var calls = 0
                let reader = SMCChargeReader { _ in
                    calls += 1
                    return calls == stage ? [UInt8](repeating: 0, count: length) : self.smcMetadata()
                }
                expectSMCError(.malformedResponse) { _ = try reader.read(.bfcl) }
                XCTAssertEqual(calls, stage)
            }
        }
    }

    func testSMCRejectsControllerErrorsAtBothStages() {
        for stage in [1, 2] {
            for status in [UInt8(1), 132, 255] {
                var calls = 0
                let reader = SMCChargeReader { _ in
                    calls += 1
                    var reply = self.smcMetadata()
                    if calls == stage { reply[40] = status }
                    return reply
                }
                expectSMCError(status == 132 ? .keyNotFound : .controllerFailed(status)) { _ = try reader.read(.bclm) }
                XCTAssertEqual(calls, stage)
            }
        }
    }

    func testSMCPropagatesTransportErrorsWithoutRetry() {
        for stage in [1, 2] {
            var calls = 0
            let reader = SMCChargeReader { _ in
                calls += 1
                if calls == stage { throw SMCReadError.driverFailed(-1) }
                return self.smcMetadata()
            }
            expectSMCError(.driverFailed(-1)) { _ = try reader.read(.bfcl) }
            XCTAssertEqual(calls, stage)
        }
    }

    func testSMCPreservesRawBytesWithoutAssumingValidLimit() {
        for value in [UInt8(0), 15, 76, 100, 255] {
            var calls = 0
            let reader = SMCChargeReader { _ in
                calls += 1
                var reply = self.smcMetadata()
                if calls == 2 { reply[48] = value }
                return reply
            }
            do { let actual = try reader.read(.bclm); XCTAssertEqual(actual, value) }
            catch { XCTAssertEqual(String(describing: error), "unexpected error") }
            XCTAssertEqual(calls, 2)
        }
    }

    func testSMCProbeTargetRequiresExactIdentity() {
        XCTAssertTrue(SMCProbeTarget.supports(model: "MacBookPro11,5", os: "12.7.6", architecture: "x86_64"))
        XCTAssertTrue(!SMCProbeTarget.supports(model: "MacBookPro11,4", os: "12.7.6", architecture: "x86_64"))
        XCTAssertTrue(!SMCProbeTarget.supports(model: "MacBookPro11,5", os: "12.7.5", architecture: "x86_64"))
        XCTAssertTrue(!SMCProbeTarget.supports(model: "MacBookPro11,5", os: "12.7.6", architecture: "arm64"))
        XCTAssertTrue(!SMCProbeTarget.supports(model: "", os: "12.7.6", architecture: "x86_64"))
    }

    func testSMCProbeCloseFailurePreservesResultsAndBlocksFutureOpen() {
        let session = SMCProbeSession()
        var opens = 0
        var closes = 0
        var reads = 0
        var time = Date(timeIntervalSince1970: 1000)
        let open: () throws -> SMCChargeReader = {
            opens += 1
            return SMCChargeReader { request in
                reads += 1
                var reply = self.smcMetadata()
                if request[0] == 0x4C { reply[40] = 132 }
                if request[42] == 5 { reply[48] = 76 }
                return reply
            }
        }
        let close: () throws -> Void = {
            closes += 1
            time = Date(timeIntervalSince1970: 1002)
            throw SMCReadError.closeFailed(-1)
        }
        do {
            let report = try session.run(open: open, close: close, clock: { time })
            let value = try report.values[.bclm]?.get()
            XCTAssertEqual(value, 76)
            if case .failure(let error)? = report.values[.bfcl] {
                XCTAssertEqual(error as? SMCReadError, .keyNotFound)
            } else { XCTAssertTrue(false) }
            XCTAssertEqual(report.closeError, .closeFailed(-1))
            XCTAssertEqual(report.startedAt, Date(timeIntervalSince1970: 1000))
            XCTAssertEqual(report.completedAt, Date(timeIntervalSince1970: 1002))
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        expectSMCError(.sessionBlocked) { _ = try session.run(open: open, close: close) }
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(reads, 3)
    }

    func testSMCProbeSuccessfulCloseAllowsRepeatEvenWhenReadsFail() {
        let session = SMCProbeSession()
        var opens = 0
        var closes = 0
        for _ in 0..<2 {
            do {
                let report = try session.run(open: {
                    opens += 1
                    return SMCChargeReader { _ in throw SMCReadError.driverFailed(-1) }
                }, close: { closes += 1 })
                XCTAssertNil(report.closeError)
                XCTAssertEqual(report.values.count, 2)
                for key in SMCChargeKey.allCases {
                    if case .failure(let error)? = report.values[key] {
                        XCTAssertEqual(error as? SMCReadError, .driverFailed(-1))
                    } else { XCTAssertTrue(false) }
                }
            } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        }
        XCTAssertEqual(opens, 2)
        XCTAssertEqual(closes, 2)
    }

    func testSMCProbeOpenFailureDoesNotCloseOrLatch() {
        let session = SMCProbeSession()
        var closes = 0
        expectSMCError(.serviceUnavailable) {
            _ = try session.run(open: { throw SMCReadError.serviceUnavailable }, close: { closes += 1 })
        }
        XCTAssertEqual(closes, 0)
        do {
            let report = try session.run(open: { SMCChargeReader { _ in self.smcMetadata() } },
                                         close: { closes += 1 })
            XCTAssertNil(report.closeError)
        } catch { XCTAssertEqual(String(describing: error), "unexpected error") }
        XCTAssertEqual(closes, 1)
    }

    private func smcMetadata() -> [UInt8] {
        var reply = [UInt8](repeating: 0, count: 80)
        reply[28] = 1
        reply.replaceSubrange(32..<36, with: [0x20, 0x38, 0x69, 0x75])
        return reply
    }

    private func expectSMCError(_ expected: SMCReadError, _ operation: () throws -> Void) {
        do { try operation(); XCTAssertEqual("no error", String(describing: expected)) }
        catch { XCTAssertEqual(error as? SMCReadError, expected) }
    }

    private func assertRecord(_ record: RecoveryRecord?, phase: RecoveryPhase) {
        XCTAssertEqual(record?.baseline, 76)
        XCTAssertEqual(record?.expected, 82)
        XCTAssertEqual(record?.phase, phase)
    }

    private final class ConcurrentOutcomes {
        private let lock = NSLock()
        private var storage: [String] = []
        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        func record(_ operation: () throws -> Void) {
            let outcome: String
            do { try operation(); outcome = "success" }
            catch let error as ControlBlock { outcome = error.rawValue }
            catch { outcome = "unexpected: " + String(describing: error) }
            lock.lock()
            storage.append(outcome)
            lock.unlock()
        }
    }

    private func controlContext(authorized: Bool = true, competitorAbsent: Bool = true, age: TimeInterval = 0,
                                health: String = "Normal", ac: Bool = true, temperature: Int = 3000) -> ControlContext {
        let now = Date(timeIntervalSince1970: 1000)
        let sample = BatteryDecoder.decode(registry: ["ExternalConnected": ac, "IsCharging": false,
            "Temperature": temperature, "BatteryHealth": health], powerSource: ["Current Capacity": 79, "Max Capacity": 100],
            capturedAt: now.addingTimeInterval(-age))
        return ControlContext(authorized: authorized, competitorAbsent: competitorAbsent, snapshot: sample)
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
        var failPhase: RecoveryPhase?
        var failLoad = false
        var failClear = false
        var saved: [RecoveryRecord] = []
        var onSave: (() -> Void)?
        func load() throws -> RecoveryRecord? {
            if failLoad { throw ControlBlock.journalFailed }
            return record
        }
        func save(_ record: RecoveryRecord) throws {
            if failSave || failPhase == record.phase { throw ControlBlock.journalFailed }
            self.record = record
            saved.append(record)
            onSave?()
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

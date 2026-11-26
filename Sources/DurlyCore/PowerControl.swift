import Foundation

public enum ControlBlock: String, Error, Equatable {
    case unsupportedDevice, unverifiedBackend, permissionDenied, competingController
    case staleTelemetry, unsafeTelemetry, invalidLimit, unknownBaseline, recoveryRequired
    case writeFailed, readbackMismatch, journalFailed
}

public struct ControlCapability: Equatable {
    public let reason: ControlBlock?
    public var canWrite: Bool { reason == nil }
    public init(reason: ControlBlock?) { self.reason = reason }
}

public enum ControlCapabilityDetector {
    // Research evidence is not production authorization.
    public static func detect(model: String, os: String, architecture: String) -> ControlCapability {
        guard model == "MacBookPro11,5", os == "12.7.6", architecture == "x86_64" else {
            return ControlCapability(reason: .unsupportedDevice)
        }
        return ControlCapability(reason: .unverifiedBackend)
    }
}

public protocol PowerControl {
    var capability: ControlCapability { get }
    func apply(limit: Int, snapshot: BatterySnapshot?, at now: Date) throws
    func pause(snapshot: BatterySnapshot?, at now: Date) throws
}

public struct ReadOnlyBackend: PowerControl {
    public let capability: ControlCapability
    public init(reason: ControlBlock = .unverifiedBackend) {
        capability = ControlCapability(reason: reason)
    }
    public func apply(limit: Int, snapshot: BatterySnapshot?, at now: Date) throws {
        throw capability.reason ?? ControlBlock.unverifiedBackend
    }
    public func pause(snapshot: BatterySnapshot?, at now: Date) throws {
        throw capability.reason ?? ControlBlock.unverifiedBackend
    }
}

// A pure transaction planner: no IOKit, IPC, root commands, or hardware side effects.
// A future authenticated helper must enforce these checks independently.
public struct ControlContext: Equatable {
    public let authorized: Bool
    public let competitorAbsent: Bool
    public let snapshot: BatterySnapshot?
    public let now: Date
    public init(authorized: Bool, competitorAbsent: Bool, snapshot: BatterySnapshot?, now: Date) {
        self.authorized = authorized
        self.competitorAbsent = competitorAbsent
        self.snapshot = snapshot
        self.now = now
    }

    public func validate() throws {
        guard authorized else { throw ControlBlock.permissionDenied }
        guard competitorAbsent else { throw ControlBlock.competingController }
        guard let snapshot = snapshot, !snapshot.isStale(at: now, maximumAge: 15) else {
            throw ControlBlock.staleTelemetry
        }
        // Conservative research policy, not a validated hardware temperature threshold.
        guard snapshot.externalPower == true,
              snapshot.percentage != nil, snapshot.isCharging != nil,
              BatteryHealthSeverity.classify(snapshot.condition) == .normal,
              let temperature = snapshot.temperatureCelsius, (10...40).contains(temperature)
        else { throw ControlBlock.unsafeTelemetry }
    }
}

public enum RecoveryPhase: Equatable { case prepared, applied, restoring }

public struct RecoveryRecord: Equatable {
    public let baseline: Int
    public let expected: Int
    public let phase: RecoveryPhase
    public init(baseline: Int, expected: Int, phase: RecoveryPhase = .prepared) {
        self.baseline = baseline
        self.expected = expected
        self.phase = phase
    }

    fileprivate func withPhase(_ phase: RecoveryPhase) -> RecoveryRecord {
        RecoveryRecord(baseline: baseline, expected: expected, phase: phase)
    }
}

public enum ControlTransaction {
    public static func prepare(limit: Int, live: Int, existing: RecoveryRecord?,
                               context: ControlContext) throws -> RecoveryRecord {
        try context.validate()
        guard (50...100).contains(limit) else { throw ControlBlock.invalidLimit }
        guard (50...100).contains(live) else { throw ControlBlock.unknownBaseline }
        guard existing == nil else { throw ControlBlock.recoveryRequired }
        return RecoveryRecord(baseline: live, expected: limit)
    }

    public static func verify(record: RecoveryRecord, readback: Int) throws {
        guard readback == record.expected else { throw ControlBlock.readbackMismatch }
    }

    public static func restore(record: RecoveryRecord, live: Int,
                               context: ControlContext) throws -> Int {
        try context.validate()
        guard record.phase == .applied,
              (50...100).contains(record.baseline), (50...100).contains(record.expected),
              live == record.expected else { throw ControlBlock.recoveryRequired }
        return record.baseline
    }
}

// Simulation only. No production hardware implementation exists.
// Journal adapters must atomically replace records or throw; durability and
// cross-process exclusion are separate requirements for the future helper.
public protocol LimitTransport {
    func read() throws -> Int
    func write(_ value: Int) throws
}
public protocol RecoveryJournal {
    func load() throws -> RecoveryRecord?
    func save(_ record: RecoveryRecord) throws
    func clear() throws
}

public final class SimulatedTransactionCoordinator {
    // One lock across all simulated coordinators in this process.
    private static let transactionLock = NSLock()
    private let transport: LimitTransport
    private let journal: RecoveryJournal
    private var latched = false
    private var ownedRecord: RecoveryRecord?

    public init(transport: LimitTransport, journal: RecoveryJournal) {
        self.transport = transport
        self.journal = journal
    }

    private func loadRecord() throws -> RecoveryRecord? {
        do { return try journal.load() }
        catch { latched = true; throw ControlBlock.journalFailed }
    }

    private func saveRecord(_ record: RecoveryRecord) throws {
        do { try journal.save(record) }
        catch { latched = true; throw ControlBlock.journalFailed }
    }

    public func apply(limit: Int, context: ControlContext) throws {
        Self.transactionLock.lock()
        defer { Self.transactionLock.unlock() }
        guard !latched else { throw ControlBlock.recoveryRequired }
        try context.validate()
        guard try loadRecord() == nil, ownedRecord == nil else {
            throw ControlBlock.recoveryRequired
        }
        let live = try transport.read()
        let record = try ControlTransaction.prepare(limit: limit, live: live, existing: nil, context: context)
        try saveRecord(record)
        do {
            guard try transport.read() == record.baseline else { throw ControlBlock.recoveryRequired }
            try transport.write(record.expected)
            try ControlTransaction.verify(record: record, readback: transport.read())
            let applied = record.withPhase(.applied)
            try saveRecord(applied)
            ownedRecord = applied
        } catch {
            latched = true
            throw error
        }
    }

    public func pause(context: ControlContext) throws {
        Self.transactionLock.lock()
        defer { Self.transactionLock.unlock() }
        guard !latched else { throw ControlBlock.recoveryRequired }
        try context.validate()
        let loaded = try loadRecord()
        guard let record = loaded else {
            guard ownedRecord == nil else {
                latched = true
                throw ControlBlock.recoveryRequired
            }
            return
        }
        // A reconstructed coordinator cannot prove ownership, even if the
        // journal says applied and the live value matches. No implicit recovery.
        guard record == ownedRecord, record.phase == .applied else {
            latched = true
            throw ControlBlock.recoveryRequired
        }
        do {
            let baseline = try ControlTransaction.restore(record: record, live: transport.read(), context: context)
            try saveRecord(record.withPhase(.restoring))
            guard try transport.read() == record.expected else { throw ControlBlock.recoveryRequired }
            try transport.write(baseline)
            guard try transport.read() == baseline else { throw ControlBlock.readbackMismatch }
            do { try journal.clear() }
            catch { throw ControlBlock.journalFailed }
            ownedRecord = nil
        } catch {
            latched = true
            throw error
        }
    }
}

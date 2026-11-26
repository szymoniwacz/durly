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

public struct RecoveryRecord: Equatable {
    public let baseline: Int
    public let expected: Int
    public init(baseline: Int, expected: Int) {
        self.baseline = baseline
        self.expected = expected
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
        guard (50...100).contains(record.baseline), (50...100).contains(record.expected),
              live == record.expected else { throw ControlBlock.recoveryRequired }
        return record.baseline
    }
}

import Foundation
import CoreFoundation

public struct BatterySnapshot: Equatable, Codable {
    public let capturedAt: Date
    public let percentage: Int?
    public let externalPower: Bool?
    public let isCharging: Bool?
    public let cycles: Int?
    public let currentCapacity: Int?
    public let maxCapacity: Int?
    public let designCapacity: Int?
    public let temperatureCelsius: Double?
    public let currentMilliamps: Int64?
    public let voltageMillivolts: Int?
    public let condition: String?

    public var rawChargePercentage: Double? {
        guard let current = currentCapacity, let max = maxCapacity, max > 0,
              current <= max else { return nil }
        return Double(current) / Double(max) * 100
    }

    public var capacityRetention: Double? {
        guard let max = maxCapacity, let design = designCapacity, design > 0 else { return nil }
        return Double(max) / Double(design) * 100
    }

    public func isStale(at now: Date = Date(), maximumAge: TimeInterval = 30) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age < 0 || age > maximumAge
    }
}

public protocol BatteryProvider {
    func read() throws -> BatterySnapshot
}

public enum BatteryReadError: Error { case unavailable }

public enum BatteryDecoder {
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i = Int(n.stringValue), i >= 0 else { return nil }
        return i
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    // IOKit may expose a negative current as an unsigned 64-bit number.
    private static func current(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let signed = Int64(n.stringValue) ?? UInt64(n.stringValue).map { Int64(bitPattern: $0) }
        guard let signed = signed, (-100_000...100_000).contains(signed) else { return nil }
        return signed
    }

    private static func positive(_ value: Any?) -> Int? {
        guard let n = integer(value), n > 0 else { return nil }
        return n
    }

    private static func capacityPair(_ current: Any?, _ maximum: Any?) -> (Int, Int)? {
        guard let current = integer(current), let maximum = positive(maximum), current <= maximum else { return nil }
        return (current, maximum)
    }

    public static func decode(registry: [String: Any], powerSource: [String: Any],
                              capturedAt: Date = Date()) -> BatterySnapshot {
        let displayed: Int?
        if let cur = integer(powerSource["Current Capacity"]),
           let max = positive(powerSource["Max Capacity"]), cur <= max {
            displayed = Int((Double(cur) / Double(max) * 100).rounded())
        } else { displayed = nil }
        let temperature = integer(registry["Temperature"]).map { Double($0) / 100 }
            .flatMap { (-20...100).contains($0) ? $0 : nil }
        let source: Bool?
        switch powerSource["Power Source State"] as? String {
        case "AC Power": source = true
        case "Battery Power": source = false
        default: source = boolean(registry["ExternalConnected"])
        }
        // Never combine capacity values from different registry key families.
        let raw = capacityPair(registry["AppleRawCurrentCapacity"], registry["AppleRawMaxCapacity"])
        let standard = capacityPair(registry["CurrentCapacity"], registry["MaxCapacity"])
        let pair = raw ?? standard
        // Preserve individually available capacity data if no complete pair exists,
        // but select both fields from the same family.
        let useRaw = raw != nil || (standard == nil && (integer(registry["AppleRawCurrentCapacity"]) != nil || positive(registry["AppleRawMaxCapacity"]) != nil))
        let partialCurrent = integer(registry[useRaw ? "AppleRawCurrentCapacity" : "CurrentCapacity"])
        let partialMax = positive(registry[useRaw ? "AppleRawMaxCapacity" : "MaxCapacity"])
        let selectedCurrent = pair?.0 ?? (partialMax == nil ? partialCurrent : nil)
        let selectedMax = pair?.1 ?? partialMax
        return BatterySnapshot(
            capturedAt: capturedAt, percentage: displayed, externalPower: source,
            isCharging: boolean(powerSource["Is Charging"]) ?? boolean(registry["IsCharging"]),
            cycles: integer(registry["CycleCount"]),
            currentCapacity: selectedCurrent,
            maxCapacity: selectedMax,
            designCapacity: positive(registry["DesignCapacity"]),
            temperatureCelsius: temperature, currentMilliamps: current(registry["Amperage"]),
            voltageMillivolts: positive(registry["Voltage"]),
            condition: powerSource["BatteryHealth"] as? String
                ?? registry["BatteryHealth"] as? String
                ?? registry["BatteryHealthCondition"] as? String
        )
    }
}

public final class BatteryMonitor {
    public private(set) var snapshot: BatterySnapshot?
    public private(set) var failed = false
    private let provider: BatteryProvider
    public init(provider: BatteryProvider) { self.provider = provider }
    public func refresh() {
        do { snapshot = try provider.read(); failed = false }
        catch { snapshot = nil; failed = true }
    }
    public func freshSnapshot(at now: Date = Date()) -> BatterySnapshot? {
        guard !failed, let value = snapshot, !value.isStale(at: now) else { return nil }
        return value
    }
}

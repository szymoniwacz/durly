import Foundation

// A fresh session requires explicit epoch confirmation when hardware identity
// is not established. No identity is inferred from capacity or cycle count.
public struct HistoryCapture {
    public private(set) var epoch: UUID?
    private var last: BatterySnapshot?
    private var lastUptime: TimeInterval?
    public init() {}
    public mutating func select(_ epoch: UUID) {
        self.epoch = epoch
        last = nil
        lastUptime = nil
    }
    public mutating func suspend() {
        epoch = nil
        last = nil
        lastUptime = nil
    }
    public func clockRegressed(_ sample: BatterySnapshot, uptime: TimeInterval) -> Bool {
        guard let last = last, let previous = lastUptime else { return false }
        return uptime < previous || sample.capturedAt < last.capturedAt
    }
    public func shouldCapture(_ sample: BatterySnapshot, uptime: TimeInterval, now: Date) -> Bool {
        guard epoch != nil, uptime.isFinite, uptime >= 0,
              !sample.isStale(at: now, maximumAge: 30),
              sample.percentage != nil else { return false }
        guard let last = last, let previous = lastUptime else { return true }
        guard uptime >= previous, sample.capturedAt > last.capturedAt else { return false }
        let elapsed = uptime - previous
        return elapsed >= 60 || (elapsed >= 1 &&
            (sample.externalPower != last.externalPower || sample.isCharging != last.isCharging ||
             sample.condition != last.condition || sample.percentage != last.percentage ||
             sample.cycles != last.cycles || sample.currentCapacity != last.currentCapacity ||
             sample.maxCapacity != last.maxCapacity || sample.designCapacity != last.designCapacity ||
             sample.temperatureCelsius != last.temperatureCelsius ||
             sample.currentMilliamps != last.currentMilliamps || sample.voltageMillivolts != last.voltageMillivolts))
    }
    public mutating func recorded(_ sample: BatterySnapshot, uptime: TimeInterval) {
        last = sample
        lastUptime = uptime
    }
}

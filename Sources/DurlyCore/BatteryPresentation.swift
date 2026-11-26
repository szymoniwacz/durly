import Foundation

public enum BatteryPresentation {
    public static func symbol(for percentage: Int?) -> String {
        guard let percentage = percentage, (0...100).contains(percentage) else { return "questionmark.circle" }
        switch percentage {
        case 0..<13: return "battery.0"
        case 13..<38: return "battery.25"
        case 38..<63: return "battery.50"
        case 63..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    public static func chargeState(for snapshot: BatterySnapshot?) -> String {
        guard let s = snapshot else { return "Battery data unavailable" }
        if s.isCharging == true {
            return s.externalPower == false ? "Power state unavailable" : "Charging"
        }
        if s.externalPower == true && s.isCharging == false { return "On AC · Not charging" }
        if s.externalPower == false && s.isCharging == false { return "On battery" }
        return "Power state unavailable"
    }

    public static func fresh(_ snapshot: BatterySnapshot?, settings: DisplaySettings,
                             at now: Date = Date()) -> BatterySnapshot? {
        guard let snapshot = snapshot,
              !snapshot.isStale(at: now, maximumAge: Double(settings.refreshSeconds + 5))
        else { return nil }
        return snapshot
    }
}

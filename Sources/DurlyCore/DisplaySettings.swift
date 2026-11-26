import Foundation
import CoreFoundation

public struct DisplaySettings: Equatable {
    public static let allowedIntervals = [10, 30, 60]
    public let showPercentage: Bool
    public let showDetails: Bool
    public let refreshSeconds: Int

    public init(showPercentage: Bool = true, showDetails: Bool = false, refreshSeconds: Int = 10) {
        self.showPercentage = showPercentage
        self.showDetails = showDetails
        self.refreshSeconds = Self.allowedIntervals.contains(refreshSeconds) ? refreshSeconds : 10
    }
}

public final class DisplaySettingsStore {
    private let defaults: UserDefaults
    private let key = "durly.display.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> DisplaySettings {
        let values = defaults.dictionary(forKey: key) ?? [:]
        func bool(_ key: String, fallback: Bool) -> Bool {
            guard let n = values[key] as? NSNumber,
                  CFGetTypeID(n) == CFBooleanGetTypeID() else { return fallback }
            return n.boolValue
        }
        let number = values["refreshSeconds"] as? NSNumber
        let interval = number.flatMap {
            CFGetTypeID($0) != CFBooleanGetTypeID() ? Int($0.stringValue) : nil
        } ?? 10
        return DisplaySettings(showPercentage: bool("showPercentage", fallback: true),
                               showDetails: bool("showDetails", fallback: false),
                               refreshSeconds: interval)
    }

    public func save(_ settings: DisplaySettings) {
        defaults.set(["showPercentage": settings.showPercentage,
                      "showDetails": settings.showDetails,
                      "refreshSeconds": settings.refreshSeconds], forKey: key)
    }
}

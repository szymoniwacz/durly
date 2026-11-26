import Foundation
import Combine
import DurlyCore

final class PopoverModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var settings: DisplaySettings
    @Published private(set) var unavailable = true

    private let monitor: BatteryMonitor
    private let store: DisplaySettingsStore
    var onChange: (() -> Void)?

    init(provider: BatteryProvider, store: DisplaySettingsStore = DisplaySettingsStore()) {
        self.monitor = BatteryMonitor(provider: provider)
        self.store = store
        self.settings = store.load()
    }

    func refresh() {
        monitor.refresh()
        // Freshness is relative to the configured polling period.
        let value = monitor.snapshot
        snapshot = value.flatMap { $0.isStale(maximumAge: Double(settings.refreshSeconds + 5)) ? nil : $0 }
        unavailable = snapshot == nil
        onChange?()
    }

    func update(showPercentage: Bool? = nil, showDetails: Bool? = nil, refreshSeconds: Int? = nil) {
        let next = DisplaySettings(showPercentage: showPercentage ?? settings.showPercentage,
                                   showDetails: showDetails ?? settings.showDetails,
                                   refreshSeconds: refreshSeconds ?? settings.refreshSeconds)
        guard next != settings else { return }
        settings = next
        store.save(next)
        onChange?()
    }

    var chargeState: String {
        guard let s = snapshot else { return "Battery data unavailable" }
        if s.isCharging == true { return "Charging" }
        if s.externalPower == true && s.isCharging == false { return "On AC · Not charging" }
        if s.externalPower == false && s.isCharging == false { return "On battery" }
        return "Power state unavailable"
    }

    var healthSeverity: BatteryHealthSeverity { BatteryHealthSeverity.classify(snapshot?.condition) }

    var healthWarning: String? {
        guard let condition = snapshot?.condition?.trimmingCharacters(in: .whitespacesAndNewlines),
              !condition.isEmpty else { return nil }
        return BatteryHealthSeverity.classify(condition) == .normal ? nil : condition
    }
}

import Foundation
import Combine
import DurlyCore

final class PopoverModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var settings: DisplaySettings
    var unavailable: Bool { snapshot == nil }

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
        snapshot = BatteryPresentation.fresh(monitor.snapshot, settings: settings)
        onChange?()
    }

    func update(showPercentage: Bool? = nil, showDetails: Bool? = nil, refreshSeconds: Int? = nil) {
        let next = DisplaySettings(showPercentage: showPercentage ?? settings.showPercentage,
                                   showDetails: showDetails ?? settings.showDetails,
                                   refreshSeconds: refreshSeconds ?? settings.refreshSeconds)
        guard next != settings else { return }
        let intervalChanged = next.refreshSeconds != settings.refreshSeconds
        settings = next
        store.save(next)
        if intervalChanged { refresh() } else { expireStaleSnapshot(); onChange?() }
    }

    func invalidateSnapshot() {
        snapshot = nil
        onChange?()
    }

    func expireStaleSnapshot() {
        if snapshot != nil && BatteryPresentation.fresh(snapshot, settings: settings) == nil {
            snapshot = nil
            onChange?()
        }
    }

    var chargeState: String { BatteryPresentation.chargeState(for: snapshot) }
    var batterySymbol: String { BatteryPresentation.symbol(for: snapshot?.percentage) }

    var healthSeverity: BatteryHealthSeverity { BatteryHealthSeverity.classify(snapshot?.condition) }

    var healthWarning: String? {
        guard let condition = snapshot?.condition?.trimmingCharacters(in: .whitespacesAndNewlines),
              !condition.isEmpty else { return nil }
        return BatteryHealthSeverity.classify(condition) == .normal ? nil : condition
    }
}

import Foundation
import Darwin
import Combine
import DurlyCore

final class PopoverModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var settings: DisplaySettings
    var unavailable: Bool { snapshot == nil }

    private let powerControl: PowerControl
    var controlExplanation: String {
        powerControl.capability.reason == .unsupportedDevice
            ? "Charge control is not verified for this Mac. Durly does not change charging."
            : "Charge control research is complete; secure hardware access is not verified. Durly does not change charging."
    }
    private let monitor: BatteryMonitor
    private let store: DisplaySettingsStore
    var onChange: (() -> Void)?

    init(provider: BatteryProvider, store: DisplaySettingsStore = DisplaySettingsStore()) {
        var size = 0
        var model = ""
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 1024 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 {
                model = String(cString: buffer)
            }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        let capability = ControlCapabilityDetector.detect(model: model, os: os, architecture: architecture)
        self.powerControl = ReadOnlyBackend(reason: capability.reason ?? .unverifiedBackend)
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

import Foundation
import Combine
import Dispatch
import DurlyCore

final class PopoverModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var settings: DisplaySettings
    var unavailable: Bool { snapshot == nil }

    @Published private(set) var smcProbeRunning = false
    @Published private(set) var smcProbeReport: String?
    @Published private(set) var smcProbeBlocked = false
    let canProbeSMC: Bool

    private let powerControl: PowerControl
    var controlExplanation: String {
        powerControl.capability.reason == .unsupportedDevice
            ? "Charge control is not verified for this Mac. Durly does not change charging."
            : "Charge control is under investigation for this Mac. Durly does not change charging."
    }
    private let monitor: BatteryMonitor
    private let store: DisplaySettingsStore
    var onChange: (() -> Void)?

    init(provider: BatteryProvider, store: DisplaySettingsStore = DisplaySettingsStore()) {
        let identity = NativeSMCProbe.platformIdentity()
        self.canProbeSMC = SMCProbeTarget.supports(model: identity.model, os: identity.os, architecture: identity.architecture)
        let capability = ControlCapabilityDetector.detect(model: identity.model, os: identity.os, architecture: identity.architecture)
        self.powerControl = ReadOnlyBackend(reason: capability.reason ?? .unverifiedBackend)
        self.monitor = BatteryMonitor(provider: provider)
        self.store = store
        self.settings = store.load()
    }

    // Explicit, one-shot diagnostic only; never poll the private driver.
    func probeSMC() {
        guard canProbeSMC, !smcProbeRunning, !smcProbeBlocked else { return }
        smcProbeRunning = true
        smcProbeReport = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report: String
            let blocked: Bool
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            do {
                let result = try NativeSMCProbe.read()
                var lines = ["Started: " + formatter.string(from: result.startedAt),
                             "Completed: " + formatter.string(from: result.completedAt)]
                lines += SMCChargeKey.allCases.map { key in
                    switch result.values[key] {
                    case .success(let value)?: return "\(key.rawValue): \(value)"
                    case .failure(let error)?: return "\(key.rawValue): \(error)"
                    case nil: return "\(key.rawValue): unavailable"
                    }
                }
                if let error = result.closeError {
                    lines.append("Connection close failed: \(error). Further reads disabled until restart.")
                }
                report = lines.joined(separator: "\n")
                blocked = result.closeError != nil
            } catch {
                report = "Attempt ended: " + formatter.string(from: Date()) + "\nSMC unavailable: \(error)"
                blocked = (error as? SMCReadError) == .sessionBlocked
            }
            DispatchQueue.main.async { [weak self] in
                self?.smcProbeReport = report
                self?.smcProbeBlocked = blocked
                self?.smcProbeRunning = false
            }
        }
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

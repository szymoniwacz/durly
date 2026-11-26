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
    @Published private(set) var historyStatus = "History not initialized"
    @Published private(set) var previousEpochAvailable = false
    @Published private(set) var recordingHistory = false
    private var history: BatteryHistory?
    private var capture = HistoryCapture()
    private var previousEpoch: UUID?

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
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Durly", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            history = try BatteryHistory(url: folder.appendingPathComponent("history.sqlite"))
            previousEpoch = try history?.latestEpoch()
            previousEpochAvailable = previousEpoch != nil
            historyStatus = "Confirm battery to start recording"
        } catch { history = nil; historyStatus = "History unavailable: storage initialization failed" }
    }

    func confirmBattery(replacement: Bool) {
        guard let history = history, let sample = snapshot,
              sample.percentage != nil, !sample.isStale(at: Date(), maximumAge: 30) else {
            historyStatus = "Fresh battery data and storage required"
            return
        }
        capture.suspend()
        recordingHistory = false
        do {
            let id: UUID
            if replacement || previousEpoch == nil {
                id = try history.createEpoch(at: sample.capturedAt)
            } else if let previous = previousEpoch {
                id = previous
            } else { return }
            previousEpoch = id
            previousEpochAvailable = true
            capture.select(id)
            recordingHistory = true
            recordHistory()
        } catch {
            capture.suspend()
            historyStatus = "History unavailable: battery selection failed"
        }
    }

    private func recordHistory() {
        guard let history = history, let sample = snapshot, let epoch = capture.epoch else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard capture.shouldCapture(sample, uptime: uptime, now: Date()) else { return }
        do {
            try history.append(sample, epoch: epoch)
            capture.recorded(sample, uptime: uptime)
            historyStatus = "Recording · last saved " + DateFormatter.localizedString(from: sample.capturedAt, dateStyle: .none, timeStyle: .medium)
        } catch {
            capture.suspend()
            recordingHistory = false
            historyStatus = "Recording paused: storage error. Confirm battery to retry."
        }
    }

    func suspendHistory() {
        capture.suspend()
        recordingHistory = false
        if history != nil { historyStatus = "Confirm battery after sleep or missing data" }
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
        if snapshot == nil { suspendHistory() } else { recordHistory() }
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
        suspendHistory()
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

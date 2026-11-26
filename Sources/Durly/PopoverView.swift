import SwiftUI
import DurlyCore

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let quit: () -> Void
    @State private var showSettings = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Durly").font(.headline)
                Spacer()
                Text("Read-only").font(.caption).foregroundColor(.secondary)
                Button(action: { model.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh battery data").accessibilityLabel("Refresh battery data")
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }.help("Settings").accessibilityLabel("Settings")
            }
            if showSettings {
                settingsPanel
            } else {
                overview
            }
            Divider()
            HStack {
                Text("Local battery monitoring").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Quit", action: quit).keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.snapshot?.percentage.map { "\($0)%" } ?? "—")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(model.chargeState).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "battery.100").font(.system(size: 30)).foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            if let percentage = model.snapshot?.percentage {
                ProgressView(value: Double(percentage), total: 100)
                    .accessibilityLabel("Battery charge")
            }
            if model.unavailable {
                Label("Battery data unavailable or stale", systemImage: "exclamationmark.triangle")
                    .font(.callout)
            }
            if let warning = model.healthWarning {
                Label(warning, systemImage: model.healthSeverity == .service ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.callout).foregroundColor(healthColor)
                    .accessibilityLabel("Battery health warning: \(warning)")
            } else if model.healthSeverity == .unknown {
                Text("Battery health unavailable").font(.caption).foregroundColor(.secondary)
            }
            Divider()
            Group {
                metric("Estimated capacity retention", decimal(model.snapshot?.capacityRetention, "%"))
                metric("Cycle count", number(model.snapshot?.cycles))
                metric("Temperature (estimate)", decimal(model.snapshot?.temperatureCelsius, " °C"))
            }
            Divider()
            Group {
                HStack {
                    Text("Charge control").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Unavailable").font(.caption).foregroundColor(.secondary)
                }
                Text("Safe hardware control has not been verified on this Mac. Durly does not change charging.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Show diagnostics", isOn: Binding(get: { model.settings.showDetails },
                                                    set: { model.update(showDetails: $0) }))
            if model.settings.showDetails {
                diagnostics
            }
        }
    }

    private var healthColor: Color {
        switch model.healthSeverity {
        case .warning:
            return colorScheme == .dark
                ? Color(red: 0.88, green: 0.59, blue: 0.59)
                : Color(red: 0.62, green: 0.24, blue: 0.27)
        case .service:
            return colorScheme == .dark
                ? Color(red: 1.0, green: 0.43, blue: 0.45)
                : Color(red: 0.68, green: 0.12, blue: 0.17)
        case .normal, .unknown:
            return .secondary
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            metric("Reported health", model.snapshot?.condition ?? "Unavailable")
            metric("AC connected", yesNo(model.snapshot?.externalPower))
            metric("Charging", yesNo(model.snapshot?.isCharging))
            metric("Current capacity", number(model.snapshot?.currentCapacity, " mAh"))
            metric("Full-charge capacity", number(model.snapshot?.maxCapacity, " mAh"))
            metric("Design capacity", number(model.snapshot?.designCapacity, " mAh"))
            metric("Raw charge ratio", decimal(model.snapshot?.rawChargePercentage, "%"))
            metric("Current", number(model.snapshot?.currentMilliamps, " mA"))
            metric("Voltage", number(model.snapshot?.voltageMillivolts, " mV"))
        }.font(.caption)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.title3.weight(.semibold))
            Toggle("Show percentage in menu bar", isOn: Binding(get: { model.settings.showPercentage },
                                                                set: { model.update(showPercentage: $0) }))
            Picker("Refresh interval", selection: Binding(get: { model.settings.refreshSeconds },
                                                          set: { model.update(refreshSeconds: $0) })) {
                ForEach(DisplaySettings.allowedIntervals, id: \.self) { seconds in
                    Text("\(seconds) seconds").tag(seconds)
                }
            }
            Text("Settings are saved automatically on this Mac. They affect display only.")
                .font(.caption).foregroundColor(.secondary)
            Button("Back") { showSettings = false }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.callout)
    }

    private func number<T>(_ value: T?, _ suffix: String = "") -> String {
        value.map { "\($0)\(suffix)" } ?? "Unavailable"
    }

    private func decimal(_ value: Double?, _ suffix: String) -> String {
        value.map { String(format: "%.1f", $0) + suffix } ?? "Unavailable"
    }

    private func yesNo(_ value: Bool?) -> String {
        value.map { $0 ? "Yes" : "No" } ?? "Unavailable"
    }
}

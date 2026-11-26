import SwiftUI
import DurlyCore

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    let maximumHeight: CGFloat
    let quit: () -> Void
    @State private var showSettings = false
    @State private var confirmReplacement = false
    @State private var showHistory = false
    @State private var contentHeight: CGFloat = 1
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
            ScrollView {
                Group {
                    if showSettings {
                        settingsPanel
                    } else if showHistory {
                        historyDetails
                    } else {
                        overview
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                })
            }
            .frame(height: min(max(1, contentHeight), maximumHeight - 100))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
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
                Image(systemName: model.batterySymbol).font(.system(size: 30)).foregroundColor(.secondary)
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
                Text(model.controlExplanation)
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Group {
                historyPanel
                Toggle("Show diagnostics", isOn: Binding(get: { model.settings.showDetails },
                                                        set: { model.update(showDetails: $0) }))
                if model.settings.showDetails {
                    diagnostics
                }
            }
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Battery history").font(.subheadline.weight(.medium))
            Text(model.historyStatus).font(.caption).foregroundColor(.secondary)
            Button(model.recordingHistory ? "Stop recording" : "Start recording") {
                if model.recordingHistory {
                    model.stopRecording()
                } else {
                    model.confirmBattery(replacement: false)
                }
            }.disabled(!model.recordingHistory && model.unavailable)
            if model.previousEpochAvailable && !model.recordingHistory {
                Text("Start only if the same battery is installed.").font(.caption)
                    .foregroundColor(.secondary)
            }
            if model.previousEpochAvailable {
                Button("Register replacement battery") { confirmReplacement = true }
                    .disabled(model.unavailable)
                    .alert("Start a separate battery history?", isPresented: $confirmReplacement) {
                        Button("Cancel", role: .cancel) {}
                        Button("Confirm replacement") { model.confirmBattery(replacement: true) }
                    } message: { Text("Only confirm if the physical battery was replaced. Previous history is preserved. Recording starts for the new battery.") }
                Button("View history") {
                    model.loadHistory()
                    showHistory = true
                }
            }
        }
    }

    private var historyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Battery history").font(.headline)
                Spacer()
                Button("Back") { showHistory = false }
            }
            Picker("Battery", selection: Binding(get: { model.viewedEpoch }, set: { model.selectHistory($0) })) {
                ForEach(model.historyEpochs) { epoch in
                    Text("Battery " + String(epoch.number) + (epoch.id == model.previousEpoch ? " · latest" : " · archived"))
                        .tag(Optional(epoch.id))
                }
            }
            if let epoch = model.historyEpochs.first(where: { $0.id == model.viewedEpoch }) {
                Text("Registered " + DateFormatter.localizedString(from: epoch.createdAt, dateStyle: .short, timeStyle: .none) + " · " + String(epoch.sampleCount) + " samples")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let baseline = model.observedBaseline {
                Text("First observed capacity: " + number(baseline.maxCapacity, " mAh"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text("Showing " + String(model.recentHistory.count) + " most recent saved samples")
                .font(.caption).foregroundColor(.secondary)
            if model.historyReadError {
                Text("History could not be read.").foregroundColor(.secondary)
            } else if model.recentHistory.isEmpty {
                Text("No recorded samples yet.").foregroundColor(.secondary)
            } else {
                ForEach(model.recentHistory, id: \.capturedAt) { sample in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            metric("Full-charge capacity", number(sample.maxCapacity, " mAh"))
                            metric("Current capacity", number(sample.currentCapacity, " mAh"))
                            metric("Design capacity", number(sample.designCapacity, " mAh"))
                            metric("Temperature", decimal(sample.temperatureCelsius, " °C"))
                            metric("Current", number(sample.currentMilliamps, " mA"))
                            metric("Voltage", number(sample.voltageMillivolts, " mV"))
                            metric("Cycles", number(sample.cycles))
                            metric("AC / Charging", yesNo(sample.externalPower) + " / " + yesNo(sample.isCharging))
                            metric("Health", sample.condition ?? "Unavailable")
                        }.padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DateFormatter.localizedString(from: sample.capturedAt, dateStyle: .short, timeStyle: .medium))
                                .font(.caption).foregroundColor(.secondary)
                            Text(number(sample.percentage, "%") + "  ·  " + number(sample.maxCapacity, " mAh") + "  ·  " + decimal(sample.temperatureCelsius, " °C"))
                                .font(.callout).monospacedDigit()
                        }
                    }
                    Divider()
                }
                if model.canShowMoreHistory {
                    Button("Show older samples", action: model.showMoreHistory)
                }
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
            if model.canProbeSMC {
                Button(model.smcProbeRunning ? "Reading SMC…" : "Read SMC charge keys", action: model.probeSMC)
                    .disabled(model.smcProbeRunning || model.smcProbeBlocked)
                if let report = model.smcProbeReport {
                    Text("Last manual probe (raw bytes)").foregroundColor(.secondary)
                    Text(report).monospacedDigit().textSelection(.enabled)
                }
            }
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

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

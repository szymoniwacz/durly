import AppKit
import Foundation
import DurlyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = BatteryMonitor(provider: IOKitBatteryProvider())
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let menu = NSMenu()
    private var rows: [String: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()
        refresh()
        let timer = Timer(timeInterval: 10, target: self, selector: #selector(refresh),
                          userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func refresh() {
        monitor.refresh()
        let snapshot = monitor.freshSnapshot()
        statusItem?.button?.title = snapshot?.percentage.map { "Durly \($0)%" } ?? "Durly —"
        func line(_ label: String, _ value: String) {
            rows[label]?.title = "\(label): \(value)"
        }
        func number<T>(_ value: T?, suffix: String = "") -> String {
            value.map { "\($0)\(suffix)" } ?? "Unavailable"
        }
        func decimal(_ value: Double?, suffix: String) -> String {
            value.map { String(format: "%.1f", $0) + suffix } ?? "Unavailable"
        }
        func yesNo(_ value: Bool?) -> String {
            value.map { $0 ? "Yes" : "No" } ?? "Unavailable"
        }
        line("Mode", "Read-only")
        line("Battery data", snapshot == nil ? "Unavailable or stale" : "Available")
        let s = snapshot
        line("Charge", number(s?.percentage, suffix: "%"))
        line("AC connected", yesNo(s?.externalPower))
        line("Charging", yesNo(s?.isCharging))
        line("Cycles", number(s?.cycles))
        line("Current capacity", number(s?.currentCapacity, suffix: " mAh"))
        line("Full-charge capacity", number(s?.maxCapacity, suffix: " mAh"))
        line("Design capacity", number(s?.designCapacity, suffix: " mAh"))
        line("Estimated capacity retention", decimal(s?.capacityRetention, suffix: "%"))
        line("Raw charge ratio", decimal(s?.rawChargePercentage, suffix: "%"))
        line("Temperature (registry estimate)", decimal(s?.temperatureCelsius, suffix: " °C"))
        line("Current", number(s?.currentMilliamps, suffix: " mA"))
        line("Voltage", number(s?.voltageMillivolts, suffix: " mV"))
        line("Battery health (reported)", s?.condition ?? "Unavailable")
    }

    private func configureMenu() {
        let labels = ["Mode", "Battery data", "Charge", "AC connected", "Charging", "Cycles",
                      "Current capacity", "Full-charge capacity", "Design capacity",
                      "Estimated capacity retention", "Raw charge ratio", "Temperature (registry estimate)",
                      "Current", "Voltage", "Battery health (reported)"]
        for label in labels {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            rows[label] = item
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let update = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        update.target = self
        menu.addItem(update)
        menu.addItem(NSMenuItem(title: "Quit Durly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()

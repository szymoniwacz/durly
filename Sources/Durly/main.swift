import AppKit
import Foundation
import DurlyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = BatteryMonitor(provider: IOKitBatteryProvider())
    private var statusItem: NSStatusItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        let menu = NSMenu()
        func line(_ label: String, _ value: String) {
            let item = NSMenuItem(title: "\(label): \(value)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
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
        if let s = snapshot {
            line("Charge", number(s.percentage, suffix: "%"))
            line("AC connected", yesNo(s.externalPower))
            line("Charging", yesNo(s.isCharging))
            line("Cycles", number(s.cycles))
            line("Current capacity", number(s.currentCapacity, suffix: " mAh"))
            line("Full-charge capacity", number(s.maxCapacity, suffix: " mAh"))
            line("Design capacity", number(s.designCapacity, suffix: " mAh"))
            line("Estimated capacity retention", decimal(s.capacityRetention, suffix: "%"))
            line("Raw charge ratio", decimal(s.rawChargePercentage, suffix: "%"))
            line("Temperature (registry estimate)", decimal(s.temperatureCelsius, suffix: " °C"))
            line("Current", number(s.currentMilliamps, suffix: " mA"))
            line("Voltage", number(s.voltageMillivolts, suffix: " mV"))
            line("Battery health (reported)", s.condition ?? "Unavailable")
        } else {
            line("Battery data", "Unavailable or stale")
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

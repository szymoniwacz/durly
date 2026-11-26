import AppKit
import SwiftUI
import Foundation
import DurlyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PopoverModel(provider: IOKitBatteryProvider())
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?
    private var activeInterval: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model, quit: {
            NSApplication.shared.terminate(nil)
        }))
        model.onChange = { [weak self] in self?.updatePresentation() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake(_:)),
                                                         name: NSWorkspace.didWakeNotification, object: nil)
        model.refresh()
    }

    private func updatePresentation() {
        let percentage = model.snapshot?.percentage
        if let button = statusItem?.button {
            let symbol: String
            if let percentage = percentage {
                switch percentage {
                case 0..<13: symbol = "battery.0"
                case 13..<38: symbol = "battery.25"
                case 38..<63: symbol = "battery.50"
                case 63..<88: symbol = "battery.75"
                default: symbol = "battery.100"
                }
            } else { symbol = "battery.0" }
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.image?.isTemplate = true
            let title = percentage.map { "\($0)%" } ?? "—"
            button.title = model.settings.showPercentage || percentage == nil ? title : ""
            button.setAccessibilityLabel("Durly, \(percentage.map { "\($0) percent" } ?? "battery data unavailable"), \(model.chargeState)")
        }
        let interval = model.settings.refreshSeconds
        if activeInterval != interval {
            timer?.invalidate()
            let next = Timer(timeInterval: Double(interval), target: self, selector: #selector(poll),
                             userInfo: nil, repeats: true)
            next.tolerance = min(2, Double(interval) / 10)
            RunLoop.main.add(next, forMode: .common)
            timer = next
            activeInterval = interval
        }
    }

    @objc private func poll() { model.refresh() }

    @objc private func didWake(_ notification: Notification) { model.refresh() }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()

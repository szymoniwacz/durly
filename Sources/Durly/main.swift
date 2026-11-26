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
    private var expiryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        model.onChange = { [weak self] in self?.updatePresentation() }
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.refresh()
        }
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.invalidateSnapshot()
        }
        model.refresh()
    }

    private func updatePresentation() {
        let percentage = model.snapshot?.percentage
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: model.batterySymbol, accessibilityDescription: nil)
            button.image?.isTemplate = true
            let title = percentage.map { "\($0)%" } ?? "—"
            button.title = model.settings.showPercentage || percentage == nil ? title : ""
            button.setAccessibilityLabel("Durly, \(percentage.map { "\($0) percent" } ?? "battery data unavailable"), \(model.chargeState)")
        }
        scheduleExpiry()
        let interval = min(model.settings.refreshSeconds, 60)
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

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard let snapshot = model.snapshot else { return }
        let deadline = snapshot.capturedAt.addingTimeInterval(Double(model.settings.refreshSeconds + 5))
        let next = Timer(fire: deadline.addingTimeInterval(0.1), interval: 0,
                         repeats: false) { [weak self] _ in self?.model.expireStaleSnapshot() }
        RunLoop.main.add(next, forMode: .common)
        expiryTimer = next
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            let screenHeight = button.window?.screen?.visibleFrame.height ?? 700
            popover.contentViewController = NSHostingController(rootView: PopoverView(model: model, maximumHeight: max(180, screenHeight - 60), quit: {
                NSApplication.shared.terminate(nil)
            }))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        expiryTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        if let wakeObserver = wakeObserver { center.removeObserver(wakeObserver) }
        if let sleepObserver = sleepObserver { center.removeObserver(sleepObserver) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()

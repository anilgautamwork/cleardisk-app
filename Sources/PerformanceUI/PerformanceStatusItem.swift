import AppKit
import PerformanceCore
import SwiftUI

@MainActor
final class PerformanceStatusItem: NSObject, NSPopoverDelegate {
    private weak var coordinator: PerformanceCoordinator?
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?

    init(coordinator: PerformanceCoordinator) {
        self.coordinator = coordinator
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func setVisible(_ visible: Bool) {
        guard visible != (item != nil) else { return }
        if visible {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item?.button?.target = self
            item?.button?.action = #selector(toggle)
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        } else {
            close()
            timer?.invalidate()
            timer = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    func close() { popover.performClose(nil) }

    @objc private func toggle() {
        guard let coordinator, let button = item?.button else { return }
        if popover.isShown { close(); return }
        let controller = NSHostingController(rootView: PerformanceMenu(coordinator: coordinator))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        coordinator.monitor.menuOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        coordinator?.monitor.menuOpen = false
        popover.contentViewController = nil
    }

    private func refresh() {
        guard let monitor = coordinator?.monitor, let button = item?.button else { return }
        let display = UserDefaults.standard.string(forKey: "menuBarDisplay").flatMap(MenuBarDisplay.init(rawValue:)) ?? .cpuAndMemory
        let message: String?
        if monitor.isPaused { message = "Paused" }
        else if monitor.error != nil || monitor.catalog == nil { message = "Unavailable" }
        else if monitor.lastChecked == nil { message = "Checking…" }
        else { message = nil }
        button.image = message == nil ? StatusDot.image(Theme.nsColor(monitor.result.status))
            : NSImage(systemSymbolName: monitor.isPaused ? "pause.circle" : "waveform.path.ecg", accessibilityDescription: "ClearDisk Performance")
        let cpu = "CPU \(Format.percent(monitor.signals?.cpuLoadPercent ?? 0))"
        let memory = monitor.memory.map { " · \(Format.bytes($0.used))" } ?? ""
        button.title = display == .icon ? "" : " \(message ?? (cpu + (display == .cpuAndMemory ? memory : "")))"
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.toolTip = "ClearDisk Performance: \(message ?? (cpu + memory))"
        button.setAccessibilityLabel(button.toolTip)
    }
}

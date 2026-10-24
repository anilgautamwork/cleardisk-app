import AppKit
import PerformanceCore
import ServiceManagement
import SwiftUI

/// A presentation preference only: all modes use the existing monitor samples.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case icon, cpu, cpuAndMemory
    var id: Self { self }
    var title: String {
        switch self {
        case .icon: "Status icon only"
        case .cpu: "CPU"
        case .cpuAndMemory: "CPU and memory"
        }
    }
}

struct MenuBarStatusLabel: View {
    @Environment(Monitor.self) private var monitor
    @AppStorage("menuBarDisplay") private var display = MenuBarDisplay.cpuAndMemory

    private var unavailable: String? {
        if monitor.isPaused { return "Paused" }
        if monitor.error != nil || monitor.catalog == nil { return "Unavailable" }
        if monitor.lastChecked == nil || monitor.signals == nil { return "Checking…" }
        return nil
    }

    var body: some View {
        HStack(spacing: 5) {
            if monitor.isPaused {
                Image(systemName: "pause.circle")
            } else if monitor.error != nil || monitor.catalog == nil {
                Image(systemName: "exclamationmark.circle")
            } else if unavailable != nil {
                Image(systemName: "circle.dotted")
            } else {
                StatusDot(status: monitor.result.status)
            }
            if display != .icon {
                if let unavailable {
                    Text(unavailable)
                } else {
                    Text("CPU \(Format.percent(monitor.signals?.cpuLoadPercent ?? 0))")
                        .frame(width: 62, alignment: .trailing)
                    if display == .cpuAndMemory {
                        Text("·")
                        Text(monitor.memory.map { String(format: "%.1f GB", Double($0.used) / Double(1 << 30)) } ?? "— GB")
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .medium)).monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .help(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if let unavailable { return "ClearDisk: \(unavailable). Open to check your Mac." }
        let cpu = monitor.signals.map { Format.percent($0.cpuLoadPercent) } ?? "unavailable"
        let memory = monitor.memory.map { "\(Format.bytes($0.used)) of \(Format.bytes($0.total))" } ?? "unavailable"
        return "ClearDisk: \(monitor.result.status.pillLabel). Whole-Mac CPU \(cpu). Memory used \(memory). Open for the latest reading."
    }
}

/// One glance from the menu bar: machine load, the top three apps, and the main fix.
struct MenuBarView: View {
    @Environment(PerformanceCoordinator.self) private var coordinator
    @Environment(Monitor.self) private var monitor
    @Environment(FixActions.self) private var actions
    @Environment(LicenseStore.self) private var license
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let r = monitor.result
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if monitor.isPaused {
                    Pill(text: "Paused", symbol: "pause", fg: Theme.text2, bg: Theme.raised)
                } else if monitor.error != nil || monitor.catalog == nil {
                    Pill(text: "Unavailable", symbol: "exclamationmark.triangle", fg: Theme.amber, bg: Theme.amberBG)
                } else if monitor.lastChecked == nil {
                    Pill(text: "Checking…", symbol: "clock", fg: Theme.text2, bg: Theme.raised)
                } else {
                    StatusPill(status: r.status)
                }
                Spacer()
                Button(monitor.isPaused ? "Resume" : "Check now") {
                    if monitor.isPaused { monitor.togglePause() } else { monitor.checkNow() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(monitor.catalog == nil)
            }
            LiveDot()
            loadMetrics
            Text(headline)
                .font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if monitor.lastChecked != nil && (monitor.isPaused || monitor.error != nil) {
                Text("Values shown are from the last successful check.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            topProcesses
            VStack(alignment: .leading, spacing: 8) {
                if monitor.error == nil, !monitor.isPaused, let hero = r.hero, let fix = hero.primaryFix, fix != .explain {
                    Button {
                        openMain()
                        let group = monitor.group(id: hero.groupID)
                        // The confirmation is shown in the main window.
                        Task { try? await Task.sleep(for: .milliseconds(300)); actions.perform(fix, group: group) }
                    } label: {
                        Label(fix.title(monitor.group(id: hero.groupID)), systemImage: fix.isPaid && !license.isLicensed ? "lock" : fix.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button { openMain() } label: {
                    Text("Open ClearDisk").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Divider().overlay(Theme.line)
            Toggle("Start at login", isOn: $startAtLogin)
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12.5))
                .onChange(of: startAtLogin) { _, on in setStartAtLogin(on) }
            Text("macOS will show a \"Background Items Added\" notice. That's ClearDisk, and you can turn it off here anytime.")
                .font(.system(size: 11)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            Button("Quit ClearDisk") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { monitor.menuOpen = true }
        .onDisappear { monitor.menuOpen = false }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var headline: String {
        if monitor.isPaused { return "Monitoring is paused." }
        if monitor.catalog == nil { return "ClearDisk couldn't load its process list. Reinstall ClearDisk." }
        if let error = monitor.error { return error }
        if monitor.lastChecked == nil { return "Checking your Mac…" }
        return monitor.result.hero?.headline ?? "Your Mac is running smoothly."
    }

    private var loadMetrics: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Label("CPU", systemImage: "cpu").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                Text(monitor.signals.map { Format.percent($0.cpuLoadPercent) } ?? "—")
                    .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text("Across all cores").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Theme.line).frame(width: 1, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Label("Memory used", systemImage: "memorychip").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                Text(monitor.memory.map { Format.bytes($0.used) } ?? "—")
                    .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text(monitor.memory.map { "of \(Format.bytes($0.total))" } ?? "Waiting for a reading")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                if let pressure = monitor.signals?.pressure {
                    Text("\(pressure.label) pressure").font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.color(pressure))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var topProcesses: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Highest CPU use").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 54, alignment: .trailing)
                Text("Memory").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            ForEach(Array(monitor.groups.prefix(3))) { group in
                HStack {
                    Text(group.displayName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.percent(group.cpuPercent)).frame(width: 54, alignment: .trailing)
                    Text(Format.bytes(group.memoryBytes)).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 12.5)).monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(group.displayName), CPU \(Format.percent(group.cpuPercent)), memory \(Format.bytes(group.memoryBytes))")
            }
            if !monitor.groups.isEmpty {
                Text("App CPU can exceed 100% when it uses several cores.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(monitor.lastChecked == nil ? "App readings will appear after the first check." : "No app readings available.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func openMain() {
        coordinator.closeMenu()
        coordinator.openPerformance()
        coordinator.presentWindow()
        NSApp.activate()
    }

    private func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            startAtLogin = SMAppService.mainApp.status == .enabled
            actions.toast = "Couldn't change Start at login."
        }
    }
}

private struct LiveDot: View {
    @Environment(Monitor.self) private var monitor
    @State private var shown = false

    var body: some View {
        ZStack {
            // The menu's content can stay alive while closed; only tick while it's open.
            if shown {
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    Text(monitor.lastChecked.map { "Last checked \(max(0, Int(ctx.date.timeIntervalSince($0))))s ago" } ?? "No reading yet")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            }
        }
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }
}

/// The menu bar dot: green, amber or red. Menu bar images are template
/// (monochrome) by default, so the color needs a non-template image.
struct StatusDot: View {
    let status: Status

    var body: some View {
        Image(nsImage: Self.images[status] ?? NSImage())
            .accessibilityLabel("ClearDisk status: \(status.pillLabel)")
    }

    /// Rendered once: redrawing the SF Symbol on every sample cost CPU and memory.
    private static let images: [Status: NSImage] = [.quiet: image(Theme.nsColor(.quiet)),
                                                    .busy: image(Theme.nsColor(.busy)),
                                                    .struggling: image(Theme.nsColor(.struggling))]

    static func image(_ color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [color]))
        let img = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "ClearDisk status")?
            .withSymbolConfiguration(config) ?? NSImage()
        img.isTemplate = false
        return img
    }
}

extension Theme {
    static func nsColor(_ s: Status) -> NSColor {
        switch s {
        case .quiet: NSColor(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255, alpha: 1)
        case .busy: NSColor(red: 0xF5 / 255, green: 0xB8 / 255, blue: 0x41 / 255, alpha: 1)
        case .struggling: NSColor(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255, alpha: 1)
        }
    }
}

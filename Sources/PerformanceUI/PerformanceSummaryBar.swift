import PerformanceCore
import SwiftUI

/// One sampling loop supplies the window, menu bar and process list.
public struct PerformanceSummaryBar: View {
    let coordinator: PerformanceCoordinator
    let diskFree: Int64
    let diskTotal: Int64
    let openStorage: () -> Void
    let openProcesses: () -> Void
    @AppStorage("performance.showMenuBar") private var showMenuBar = false

    public init(coordinator: PerformanceCoordinator, diskFree: Int64, diskTotal: Int64,
                openStorage: @escaping () -> Void, openProcesses: @escaping () -> Void) {
        self.coordinator = coordinator
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.openStorage = openStorage
        self.openProcesses = openProcesses
    }

    public var body: some View {
        let monitor = coordinator.monitor
        let status = monitor.readingStatus
        let free = status == nil ? (monitor.signals?.diskFreeBytes ?? diskFree) : diskFree
        let total = status == nil ? (monitor.signals?.diskTotalBytes ?? diskTotal) : diskTotal
        HStack(spacing: 22) {
            Button(action: openStorage) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Macintosh HD", systemImage: "internaldrive")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(total > 0 ? Format.storage(free) : "—")
                            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        Text("available").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Spacer(minLength: 0)
                    }
                    ProgressView(value: total > 0 ? min(1, max(0, 1 - Double(free) / Double(total))) : 0)
                        .tint(Theme.accent).accessibilityLabel("Disk used")
                    Text(total > 0 ? "\(Format.storage(max(0, total - free))) used of \(Format.storage(total))" : "Disk reading unavailable")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                .frame(minWidth: 190, maxWidth: 260, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help("Open disk scan or results. Available space can include space macOS can reclaim.")
            Divider().frame(height: 58)
            Button(action: openProcesses) {
                metric("CPU load", symbol: "cpu",
                       value: status == nil ? monitor.signals.map { Format.percent($0.cpuLoadPercent) } ?? "—" : "—",
                       detail: status ?? "Across all cores")
            }.buttonStyle(.plain).help("Review running apps by CPU or memory use")
            Button(action: openProcesses) {
                metric("Memory used", symbol: "memorychip",
                       value: status == nil ? monitor.memory.map { Format.bytes($0.used) } ?? "—" : "—",
                       detail: status ?? monitor.signals.map { "\($0.pressure.label) pressure" } ?? "Checking…")
            }.buttonStyle(.plain).help("Review memory use and quit apps you no longer need")
            Spacer(minLength: 0)
            Toggle(isOn: $showMenuBar) {
                Label("Menu bar", systemImage: "menubar.rectangle")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.button).buttonStyle(.bordered)
            .help("Show CPU, memory, disk space and running apps from the macOS menu bar")
            .accessibilityLabel("Show ClearDisk in the menu bar")
        }
        .padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 18)
        .background(Theme.card).foregroundStyle(Theme.text)
    }

    private func metric(_ title: String, symbol: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
        .frame(minWidth: 105, alignment: .leading)
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

enum PerformanceReadout {
    static func status(enabled: Bool, paused: Bool, available: Bool, hasError: Bool,
                       lastChecked: Date?, now: Date = Date()) -> String? {
        if paused { return "Paused" }
        if !enabled { return "Not monitoring" }
        if !available || hasError { return "Unavailable" }
        guard let lastChecked else { return "Checking…" }
        if now.timeIntervalSince(lastChecked) > 60 { return "Waiting for update" }
        return nil
    }

    static func apps(_ groups: [ProcessGroup], byMemory: Bool, limit: Int = 5) -> [ProcessGroup] {
        Array(groups.filter { $0.appPath != nil && !$0.members.isEmpty }.sorted {
            let left = byMemory ? Double($0.memoryBytes) : $0.cpuPercent
            let right = byMemory ? Double($1.memoryBytes) : $1.cpuPercent
            return left == right ? $0.id < $1.id : left > right
        }.prefix(max(0, limit)))
    }
}

extension Monitor {
    var readingStatus: String? {
        PerformanceReadout.status(enabled: enabled, paused: isPaused, available: catalog != nil,
                                  hasError: error != nil, lastChecked: lastChecked)
    }
}

import AppKit
import PerformanceCore
import SwiftUI

/// What's behind macOS's "Background Items Added" notices. Read-only in 1.0.
struct BackgroundItemsView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let owners = grouped
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Background Items").font(.system(size: 30, weight: .bold))
                        Text("Apps can add helpers that run in the background. Here's what each one does.")
                            .font(.system(size: 14.5)).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    FixButton(fix: .openLoginItemsSettings, group: nil)
                }
                if monitor.backgroundItems.isEmpty {
                    ContentUnavailableView("No background items found", systemImage: "checkmark.circle",
                                           description: Text("Nothing is set to run in the background."))
                }
                ForEach(owners, id: \.name) { owner in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            OwnerIcon(name: owner.name)
                            Text(owner.name).font(.system(size: 15, weight: .semibold))
                            Text("\(owner.items.count)").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        }
                        .padding(.bottom, 8)
                        ForEach(owner.items) { ItemRow(item: $0) }
                    }
                }
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
        .task { await monitor.refreshBackgroundItems(force: true) }
    }

    private var grouped: [(name: String, items: [BackgroundItem])] {
        Dictionary(grouping: monitor.backgroundItems) { $0.ownerApp ?? "Unknown developer" }
            .map { (name: $0.key, items: $0.value.sorted { $0.label < $1.label }) }
            .sorted { a, b in
                if a.name == "Unknown developer" { return false }
                if b.name == "Unknown developer" { return true }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}

private struct OwnerIcon: View {
    let name: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: "/Applications/\(name).app")) ??
            (FileManager.default.fileExists(atPath: "/Applications/\(name).app") ? URL(fileURLWithPath: "/Applications/\(name).app") : nil) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
        } else {
            Image(systemName: "questionmark.app").font(.system(size: 18)).foregroundStyle(Theme.text3).frame(width: 24, height: 24)
        }
    }
}

private struct ItemRow: View {
    let item: BackgroundItem
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let e = monitor.catalog?.explain(launchdLabel: item.label, ownerApp: item.ownerApp)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e?.title ?? item.label).font(.system(size: 13.5, weight: .medium))
                Text(item.label).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(scopeLabel).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 150, alignment: .leading)
            Color.clear.frame(width: 190, height: 1).overlay(alignment: .leading) { running }
            Color.clear.frame(width: 110, height: 1).overlay(alignment: .leading) { if let e { VerdictPill(verdict: e.verdict) } }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var scopeLabel: String {
        switch item.scope {
        case .userAgent: "Runs for you"
        case .systemAgent: "Runs for all users"
        case .systemDaemon: "Runs as system"
        case .appBundled: "Built into \(item.ownerApp ?? "an app")"
        }
    }

    @ViewBuilder private var running: some View {
        if let pid = item.pid {
            HStack(spacing: 6) {
                Pill(text: "Running", fg: Theme.green, bg: Theme.greenBG)
                if let u = monitor.usage(pid: pid) {
                    Text("\(Format.percent(u.cpuPercent)) · \(Format.bytes(u.memoryBytes))")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).monospacedDigit()
                }
            }
        } else {
            Text("Not running").font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }
}

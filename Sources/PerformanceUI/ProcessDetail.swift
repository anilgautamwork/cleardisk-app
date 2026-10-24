import AppKit
import PerformanceCore
import SwiftUI

/// The expanded row: what it is, why it gets busy, what you can do.
struct ProcessDetail: View {
    let group: ProcessGroup
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let e = monitor.explanation(for: group)
        VStack(alignment: .leading, spacing: 14) {
            if let e {
                Text(e.summary).font(.system(size: 14)).foregroundStyle(Theme.text)
                if let why = e.whyHigh {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: "Why it gets busy")
                        Text(why).font(.system(size: 13.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if group.helperCount > 0 { Helpers(group: group) }
                if Diagnosis.spotlightFamily.contains(group.primary.name) { SpotlightHelp(group: group) }
                if group.primary.name == "WindowServer" { WindowServerHelp() }
                let fixes = shownFixes(e)
                if !fixes.isEmpty || e.guide != nil {
                    HStack(spacing: 10) {
                        ForEach(fixes, id: \.self) { FixButton(fix: $0, group: group) }
                        if let guide = e.guide, let url = URL(string: "https://whyslow.app/process/\(guide)") {
                            Button { NSWorkspace.shared.open(url) } label: {
                                Label("Read the full guide", systemImage: "arrow.up.right").labelStyle(TrailingIcon())
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    /// Rebuild only appears once Spotlight looks stuck (3+ hours busy);
    /// debug builds always show it so the admin prompt can be tested.
    private func shownFixes(_ e: Explanation) -> [FixID] {
        e.fixes.filter { fix in
            switch fix {
            case .explain: false
            case .quitApp: group.quittable
            case .rebuildSpotlightIndex: spotlightStuck
            default: true
            }
        }
    }

    private var spotlightStuck: Bool {
        #if DEBUG
        return true
        #else
        return monitor.spotlightBusySince.map { Date().timeIntervalSince($0) > 3 * 3600 } ?? false
        #endif
    }
}

private struct Helpers: View {
    let group: ProcessGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Busiest parts (\(group.members.count) processes)")
            ForEach(Array(group.members.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5).enumerated()), id: \.offset) { _, m in
                HStack {
                    Text(m.name).font(.system(size: 12.5, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Text(Format.percent(m.cpuPercent)).font(.system(size: 12.5)).monospacedDigit().frame(width: 60, alignment: .trailing)
                    Text(Format.bytes(m.memoryBytes)).font(.system(size: 12.5)).monospacedDigit().frame(width: 80, alignment: .trailing)
                }
                .foregroundStyle(Theme.text2)
            }
        }
        .frame(maxWidth: 560)
    }
}

private struct SpotlightHelp: View {
    let group: ProcessGroup
    @State private var folders: [HeavyFolder]?
    @Environment(FixActions.self) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Folders that keep Spotlight busy")
            if let folders {
                if folders.isEmpty {
                    Text("No big build or virtual machine folders found.").font(.system(size: 13)).foregroundStyle(Theme.text2)
                } else {
                    ForEach(folders, id: \.path) { f in
                        HStack {
                            Text(f.label).font(.system(size: 13))
                            Text(f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text3).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(f.bytes)).font(.system(size: 13)).monospacedDigit()
                        }
                    }
                    Text("Add these folders under Spotlight Privacy so macOS stops indexing them.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = await Task.detached { SpotlightAdvisor.heavyFolders(home: home) }.value
        }
    }
}

private struct WindowServerHelp: View {
    @State private var census: [WindowCount] = []
    @State private var displays: DisplayInfo?
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Windows open right now")
            ForEach(Array(census.prefix(5).enumerated()), id: \.offset) { _, w in
                HStack {
                    Text(w.ownerName).font(.system(size: 13))
                    Spacer()
                    Text("\(w.count) \(w.count == 1 ? "window" : "windows")").font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
            }
            if let d = displays {
                Text("Displays: \(d.count)\(d.scaledCount > 0 ? " (\(d.scaledCount) scaled)" : "")")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            // The display settings buttons come from the catalog's fix row below; only the
            // window-owner action is specific to this view.
            if let top = topGroup {
                if Diagnosis.isBrowser(top) {
                    FixButton(fix: .reviewTabs, group: top)
                } else if top.quittable {
                    FixButton(fix: .quitApp, group: top)
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .task {
            census = WindowCensus.live()
            displays = WindowCensus.displays()
        }
    }

    /// The app group that owns the most windows.
    private var topGroup: ProcessGroup? {
        guard let pid = census.first?.ownerPID else { return nil }
        return monitor.groups.first { $0.members.contains { $0.pid == pid } }
    }
}

import PerformanceCore
import SwiftUI

struct ProcessesView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(Router.self) private var router
    @State private var search = ""
    @State private var sortByMemory = false
    @State private var filter: Verdict?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let all = allRows
        let rows = visible(all)
        let counts = Dictionary(grouping: all, by: \.verdict).mapValues(\.count)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Processes").font(.system(size: 30, weight: .bold))
                    Text("Everything running on your Mac, in plain English.").font(.system(size: 14.5)).foregroundStyle(Theme.text2)
                }
                Spacer()
                LiveBadge()
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3)
                    TextField("Search processes, like mds or Chrome", text: $search)
                        .textFieldStyle(.plain).focused($searchFocused)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
                Picker("Sort", selection: $sortByMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 170).labelsHidden()
            }
            HStack(spacing: 8) {
                chip(nil, "All", all.count)
                chip(.safe, Verdict.safe.label, counts[.safe] ?? 0)
                chip(.review, Verdict.review.label, counts[.review] ?? 0)
                chip(.leave, Verdict.leave.label, counts[.leave] ?? 0)
            }
            ProcessTableHeader()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.group.id) { row in
                            ExpandableRow(group: row.group, expanded: router.expandedID == row.group.id) {
                                router.expandedID = router.expandedID == row.group.id ? nil : row.group.id
                            }
                            .id(row.group.id)
                        }
                        if rows.isEmpty {
                            Text(search.isEmpty ? "Nothing here right now." : "No process matches \"\(search)\".")
                                .foregroundStyle(Theme.text2).padding(.top, 40)
                        }
                    }
                }
                .onAppear { if let id = router.expandedID { proxy.scrollTo(id, anchor: .top) } }
            }
        }
        .padding(.horizontal, 34).padding(.top, 28)
        .onChange(of: router.focusSearch) { _, _ in searchFocused = true }
        .onAppear { if router.focusSearch > 0 { searchFocused = true } }
    }

    private struct Row {
        let group: ProcessGroup
        let verdict: Verdict
    }

    /// kernel_task isn't visible to ps without root, so it gets a pinned row
    /// that reports heat instead of a CPU number.
    private var allRows: [Row] {
        let kernel = ProcessGroup(id: "kernel_task", displayName: "kernel_task", appPath: nil,
                                  members: [ProcessUsage(pid: 0, ppid: 0, uid: 0, user: "root", path: "kernel_task",
                                                         name: "kernel_task", cpuPercent: 0, memoryBytes: 0)],
                                  cpuPercent: 0, memoryBytes: 0, quittable: false)
        return ([kernel] + monitor.groups).map { g in Row(group: g, verdict: monitor.explanation(for: g)?.verdict ?? .review) }
    }

    private func visible(_ all: [Row]) -> [Row] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all
            .filter { filter == nil || $0.verdict == filter }
            .filter { r in
                q.isEmpty || r.group.displayName.lowercased().contains(q)
                    || r.group.members.contains { $0.name.lowercased().contains(q) }
                    || (monitor.explanation(for: r.group)?.title.lowercased().contains(q) ?? false)
            }
            .sorted { a, b in
                if a.group.id == "kernel_task" { return true }
                if b.group.id == "kernel_task" { return false }
                return sortByMemory ? a.group.memoryBytes > b.group.memoryBytes : a.group.cpuPercent > b.group.cpuPercent
            }
    }

    private func chip(_ v: Verdict?, _ label: String, _ count: Int) -> some View {
        let on = filter == v
        return Button { filter = v } label: {
            Text("\(label) \(count)")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(on ? Theme.text : Theme.text2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? Theme.accentBG : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.5) : Theme.line))
        }
        .buttonStyle(.plain)
    }
}

private struct ExpandableRow: View {
    let group: ProcessGroup
    let expanded: Bool
    let toggle: () -> Void
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text3).frame(width: 14)
                    if group.id == "kernel_task" {
                        KernelRow()
                    } else {
                        ProcessRow(group: group)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(expanded ? Theme.card : .clear)
            if expanded {
                ProcessDetail(group: group)
                    .padding(.leading, 60).padding(.trailing, 14).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }
}

private struct KernelRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let thermal = monitor.signals?.thermal ?? .normal
        HStack(spacing: 12) {
            ProcessIcon(group: ProcessGroup(id: "k", displayName: "kernel_task", appPath: nil, members: [], cpuPercent: 0,
                                            memoryBytes: 0, quittable: false), symbol: "thermometer.medium")
            VStack(alignment: .leading, spacing: 3) {
                Text("kernel_task").font(Theme.mono)
                Text("Kernel (heat control)").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 130, height: 1).overlay(alignment: .leading) { VerdictPill(verdict: .leave) }
            Color.clear.frame(width: 170, height: 1).overlay(alignment: .leading) {
                LeaveNote(text: thermal == .normal ? "Not cooling right now" : "Cooling your Mac")
            }
            Text(thermal == .normal ? "heat ok" : thermal.label).font(.system(size: 13.5))
                .foregroundStyle(Theme.color(thermal)).frame(width: 70, alignment: .trailing)
            Text("—").font(.system(size: 13.5)).foregroundStyle(Theme.text3).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

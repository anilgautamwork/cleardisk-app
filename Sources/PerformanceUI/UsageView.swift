import Charts
import PerformanceCore
import SwiftUI

/// How hard the Mac works, and whether it's time for a new one.
struct UsageView: View {
    @Environment(Monitor.self) private var monitor
    @State private var range = 24
    @State private var records: [MinuteRecord] = []
    @State private var weekRecords: [MinuteRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usage").font(.system(size: 30, weight: .bold))
                    Text("How hard your Mac works, and whether it's time for a new one.").font(.system(size: 14.5)).foregroundStyle(Theme.text2)
                }
                macCard
                verdictCard
                HStack(alignment: .top, spacing: 16) {
                    liveCPU
                    liveMemory
                }
                history
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
        .task(id: range) {
            // New minutes land while the screen is open.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: Mac and verdict

    private var macCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer").font(.system(size: 26)).foregroundStyle(Theme.accentLight)
            if let mac = monitor.mac {
                Text([mac.name, mac.chip, "\(Format.bytes(mac.memoryBytes)) memory",
                      monitor.signals.map { "\(Format.storage($0.diskTotalBytes)) storage" } ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 15, weight: .semibold))
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var verdict: UpgradeVerdict {
        let s = monitor.signals
        let free = s.map { $0.diskTotalBytes > 0 ? Double($0.diskFreeBytes) / Double($0.diskTotalBytes) : 1 } ?? 1
        return UpgradeAdvisor.evaluate(records: weekRecords, memoryBytes: monitor.mac?.memoryBytes ?? Int64(ProcessInfo.processInfo.physicalMemory),
                                       diskFreeShare: free)
    }

    private var verdictCard: some View {
        let v = verdict
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Do you need a new Mac?").font(.system(size: 20, weight: .bold))
                switch v {
                case .notEnoughData(let h):
                    verdictLine("hourglass", Theme.text2,
                                "Not enough data yet. ClearDisk has measured \(h) hours. Keep it running (turn on Start at login) and check back in a few days.")
                case .healthy:
                    verdictLine("checkmark.seal", Theme.green,
                                "Your Mac has headroom. Over the last 7 days it rarely ran short of memory or processor power. No upgrade needed for how you use it.")
                case .bottlenecks(let list, _):
                    ForEach(Array(list.enumerated()), id: \.offset) { _, b in bottleneck(b) }
                }
                if monitor.mac?.isAppleSilicon == false {
                    verdictLine("exclamationmark.triangle", Theme.amber,
                                "This is an Intel Mac. It can't run macOS 27 or later, so plan an upgrade to keep getting security updates.")
                }
                Text("Based on \(hours(v)) hours measured while ClearDisk was running. Nothing is uploaded.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        }
    }

    @ViewBuilder private func bottleneck(_ b: Bottleneck) -> some View {
        switch b {
        case .memory(let gb, let share):
            verdictLine("memorychip", Theme.amber,
                        "Memory is holding your Mac back. It was under memory pressure \(Int((share * 100).rounded()))% of the time. Your next Mac should have at least \(gb) GB of memory.")
        case .cpu(let share):
            verdictLine("cpu", Theme.amber,
                        "Your processor is often maxed out (\(Int((share * 100).rounded()))% of the time). A Mac with a newer or bigger chip would help with your workload.")
        case .storage:
            HStack(alignment: .top) {
                verdictLine("internaldrive", Theme.amber, "Your disk is nearly full. Free up space with ClearDisk, or choose more storage next time.")
                FixButton(fix: .openClearDisk, group: nil)
            }
        }
    }

    private func verdictLine(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(text).font(.system(size: 14.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hours(_ v: UpgradeVerdict) -> Int {
        switch v {
        case .notEnoughData(let h), .healthy(let h), .bottlenecks(_, let h): h
        }
    }

    // MARK: Live

    private var liveCPU: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "CPU load, last 10 minutes")
                Text("\(Int((monitor.signals?.cpuLoadPercent ?? 0).rounded()))%").font(.system(size: 26, weight: .bold))
                Chart(monitor.cpuHistory) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("CPU", p.load))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", p.date), y: .value("CPU", p.load)).foregroundStyle(Theme.accentLight)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
                .frame(height: 140)
                .accessibilityLabel("CPU load over the last 10 minutes, now \(Int((monitor.signals?.cpuLoadPercent ?? 0).rounded())) percent")
            }
        }
    }

    private var liveMemory: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Memory right now")
                if let m = monitor.memory {
                    Text("\(Format.bytes(m.used)) of \(Format.bytes(m.total))").font(.system(size: 26, weight: .bold))
                    let parts: [(String, Int64, Color)] = [("App", m.app, Theme.accent), ("Wired", m.wired, Theme.amber),
                                                           ("Compressed", m.compressed, Theme.red), ("Cached", m.cached, Color(hex: 0x60A5FA)),
                                                           ("Free", m.free, Theme.raised)]
                    Chart(parts, id: \.0) { p in
                        BarMark(x: .value("Bytes", p.1), y: .value("Memory", "Memory"))
                            .foregroundStyle(p.2)
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 26)
                    .accessibilityLabel("Memory used \(Format.bytes(m.used)) of \(Format.bytes(m.total))")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 6) {
                        ForEach(parts, id: \.0) { p in
                            HStack(spacing: 5) {
                                Circle().fill(p.2).frame(width: 7, height: 7)
                                Text("\(p.0) \(Format.bytes(p.1))").font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                            }
                        }
                    }
                    HStack {
                        Text("Pressure: ").foregroundStyle(Theme.text2)
                        Text(monitor.signals?.pressure.label ?? "—").foregroundStyle(monitor.signals.map { Theme.color($0.pressure) } ?? Theme.text)
                        Spacer()
                        Text("Swap: \(Format.bytes(monitor.signals?.swapUsedBytes ?? 0))").foregroundStyle(Theme.text2)
                    }
                    .font(.system(size: 13))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: History

    private var history: some View {
        let buckets = UsageBuckets.bucket(records, minutes: range == 24 ? 60 : 1440)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History").font(.system(size: 17, weight: .bold))
                Spacer()
                Picker("Range", selection: $range) {
                    Text("24 hours").tag(24)
                    Text("7 days").tag(24 * 7)
                    Text("30 days").tag(24 * 30)
                }
                .pickerStyle(.segmented).frame(width: 280).labelsHidden()
            }
            if !monitor.keepHistory {
                Text("Usage history is off. Turn it on in Settings.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            } else if buckets.isEmpty {
                Text("ClearDisk records one line a minute while it runs. Check back soon.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    historyChart("Average CPU load", buckets, value: { $0.cpu }, unit: "%", color: Theme.accentLight)
                    historyChart("Time under memory pressure", buckets, value: { $0.pressureShare * 100 }, unit: "%", color: Theme.amber)
                    historyChart("Swap", buckets, value: { Double($0.swap) / Double(1 << 30) }, unit: " GB", color: Theme.red)
                }
            }
        }
    }

    private func historyChart(_ title: String, _ buckets: [UsageBucket], value: @escaping (UsageBucket) -> Double,
                              unit: String, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: title)
                Chart(buckets) { b in
                    BarMark(x: .value("Time", b.start, unit: range == 24 ? .hour : .day), y: .value(title, value(b)))
                        .foregroundStyle(color)
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))\(unit)") } } }
                .frame(height: 120)
                .accessibilityLabel(title)
            }
        }
    }

    private func load() async {
        let store = monitor.usageStore
        let since = Date().addingTimeInterval(-Double(range) * 3600)
        let week = Date().addingTimeInterval(-7 * 86400)
        (records, weekRecords) = await Task.detached { (store.load(since: since), store.load(since: week)) }.value
    }
}

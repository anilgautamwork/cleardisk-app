import PerformanceCore
import SwiftUI

struct OverviewView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Header()
                if let error = monitor.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.amber).font(.system(size: 13))
                }
                HeroCard()
                SignalsRow()
                TopTable()
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
    }
}

private struct Header: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overview").font(.system(size: 30, weight: .bold))
                Text("Understand what's happening on your Mac.").font(.system(size: 14.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            LiveBadge()
        }
    }
}

struct LiveBadge: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(monitor.isPaused ? Theme.text3 : Theme.green).frame(width: 7, height: 7)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(label(now: ctx.date)).font(.system(size: 12.5)).foregroundStyle(Theme.text2).monospacedDigit()
            }
            Button { monitor.togglePause() } label: {
                Label(monitor.isPaused ? "Resume" : "Pause", systemImage: monitor.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12.5))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func label(now: Date) -> String {
        if monitor.isPaused { return "Paused" }
        guard let t = monitor.lastChecked else { return "Checking…" }
        return "Live · checked \(max(0, Int(now.timeIntervalSince(t))))s ago"
    }
}

private struct HeroCard: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let r = monitor.result
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: r.hero?.kind.symbol ?? "checkmark.seal")
                        .font(.system(size: 18)).foregroundStyle(Theme.color(r.status))
                        .frame(width: 38, height: 38)
                        .background(r.status == .quiet ? Theme.greenBG : r.status == .busy ? Theme.amberBG : Theme.redBG,
                                    in: RoundedRectangle(cornerRadius: 10))
                    StatusPill(status: monitor.lastChecked == nil ? .quiet : r.status)
                }
                if monitor.lastChecked == nil {
                    Text("Checking your Mac…").font(.system(size: 23, weight: .bold)).padding(.top, 16)
                } else if let hero = r.hero {
                    Text(hero.headline).font(.system(size: 23, weight: .bold)).padding(.top, 16)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hero.detail).font(.system(size: 15)).foregroundStyle(Theme.text2).lineSpacing(4)
                        .padding(.top, 8).frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        let group = monitor.group(id: hero.groupID)
                        if group != nil, hero.primaryFix != .explain {
                            FixButton(fix: .explain, group: group, prominent: true)
                        }
                        if let fix = hero.primaryFix {
                            FixButton(fix: fix, group: group, prominent: fix == .explain)
                        } else if let note = hero.leaveNote {
                            Pill(text: note, fg: Color(hex: 0xC4C4CC), bg: Color(hex: 0x24242C))
                        }
                    }
                    .padding(.top, 18)
                    if !r.more.isEmpty { MoreCauses(findings: r.more) }
                } else {
                    Text("Your Mac is running smoothly.").font(.system(size: 23, weight: .bold)).padding(.top, 16)
                    Text("Nothing is slowing your Mac down right now.").font(.system(size: 15)).foregroundStyle(Theme.text2).padding(.top, 8)
                }
            }
        }
    }
}

private struct MoreCauses: View {
    let findings: [Finding]
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "And \(findings.count) more \(findings.count == 1 ? "cause" : "causes")")
            ForEach(findings) { f in
                HStack(spacing: 10) {
                    Circle().fill(Theme.color(f.severity)).frame(width: 6, height: 6)
                    Text(f.headline).font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xD4D4D8))
                    Spacer(minLength: 12)
                    if let fix = f.primaryFix {
                        FixButton(fix: fix, group: monitor.group(id: f.groupID))
                    } else if let note = f.leaveNote {
                        Pill(text: note, fg: Color(hex: 0xC4C4CC), bg: Color(hex: 0x24242C))
                    }
                }
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 6) }
    }
}

private struct SignalsRow: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let s = monitor.signals
        HStack(spacing: 0) {
            signal("CPU load", "cpu", s.map { "\(Int($0.cpuLoadPercent.rounded()))%" } ?? "—", Theme.text, "Across all CPU cores")
            divider
            signal("Memory pressure", "memorychip", s?.pressure.label ?? "—", s.map { Theme.color($0.pressure) } ?? Theme.text,
                   s.map { "\(Format.bytes($0.memoryTotalBytes)) installed" } ?? "")
            divider
            signal("Thermal state", "thermometer.medium", s?.thermal.label ?? "—", s.map { Theme.color($0.thermal) } ?? Theme.text,
                   s?.thermal == .normal ? "Running at full speed" : "macOS reports elevated heat")
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 70) }

    private func signal(_ title: String, _ symbol: String, _ value: String, _ color: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(color)
            Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

private struct TopTable: View {
    @Environment(Monitor.self) private var monitor
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What's using your CPU").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { router.screen = .processes } label: {
                    Label("All processes", systemImage: "arrow.right").labelStyle(TrailingIcon())
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.accentLight)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
            ProcessTableHeader()
            ForEach(Array(monitor.groups.prefix(5))) { g in
                ProcessRow(group: g)
            }
        }
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct ProcessTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("").frame(width: 34)
            Text("Process").frame(maxWidth: .infinity, alignment: .leading)
            Text("Verdict").frame(width: 130, alignment: .leading)
            Text("Action").frame(width: 170, alignment: .leading)
            Text("CPU").frame(width: 70, alignment: .trailing)
            Text("Memory").frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 12.5)).foregroundStyle(Theme.text3)
        .padding(.horizontal, 10).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct ProcessRow: View {
    let group: ProcessGroup
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let e = monitor.explanation(for: group)
        HStack(spacing: 12) {
            ProcessIcon(group: group, symbol: e?.symbol ?? "gearshape")
            VStack(alignment: .leading, spacing: 3) {
                Text(group.displayName).font(Theme.mono).lineLimit(1)
                Text(subtitle(e)).font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Fixed-width slots: an empty cell must still hold its column.
            Color.clear.frame(width: 130, height: 1).overlay(alignment: .leading) { if let e { VerdictPill(verdict: e.verdict) } }
            Color.clear.frame(width: 170, height: 1).overlay(alignment: .leading) { action(e) }
            Text(cpuText).font(.system(size: 13.5)).monospacedDigit()
                .foregroundStyle(group.cpuPercent >= 80 ? Theme.amber : Theme.text).frame(width: 70, alignment: .trailing)
            Text(Format.bytes(group.memoryBytes)).font(.system(size: 13.5)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private var cpuText: String {
        String(format: "%.1f%%", group.cpuPercent)
    }

    private func subtitle(_ e: Explanation?) -> String {
        let title = e?.title ?? ""
        return group.helperCount > 0 ? "\(title) · \(group.helperCount) helpers" : title
    }

    @ViewBuilder private func action(_ e: Explanation?) -> some View {
        if let e, group.quittable, e.fixes.contains(.quitApp) {
            FixButton(fix: .quitApp, group: group)
        } else if let note = e?.idleNote {
            LeaveNote(text: note)
        }
    }
}

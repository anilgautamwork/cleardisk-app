import AppKit
import PerformanceCore
import Foundation
import Observation
import os

struct CPUPoint: Identifiable, Sendable {
    let date: Date
    let load: Double
    var id: Date { date }
}

/// Owns the sampling loop: ps → CPU deltas → app groups → 3-sample smoothing
/// → diagnosis. Every 3s while the window is visible, every 15s otherwise.
@MainActor
@Observable
final class Monitor {
    private(set) var groups: [ProcessGroup] = []
    private(set) var signals: SystemSignals?
    private(set) var result = DiagnosisResult(findings: [])
    private(set) var lastChecked: Date?
    private(set) var error: String?
    private(set) var spotlightBusySince: Date?
    /// Computed once per sample, off the main thread — views never re-run catalog matching.
    private(set) var explanations: [String: Explanation] = [:]
    private(set) var backgroundItems: [BackgroundItem] = []
    /// Last ~10 minutes of whole-Mac CPU load for the live chart.
    private(set) var cpuHistory: [CPUPoint] = []
    private(set) var memory: MemoryBreakdown?
    private(set) var mac: MacInfo?
    /// Settings: record one line per minute to Application Support (on by default).
    var keepHistory: Bool = UserDefaults.standard.object(forKey: "keepUsageHistory") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(keepHistory, forKey: "keepUsageHistory")
            aggregator = MinuteAggregator()
        }
    }
    let usageStore = UsageStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClearDisk/Performance", isDirectory: true))
    var isPaused = false
    var windowVisible = false {
        didSet {
            guard windowVisible != oldValue else { return }
            // Nobody can see row explanations or background items now; free them.
            if !windowVisible { explanations = [:]; backgroundItems = []; itemsLoadedAt = nil }
            restartLoop()
        }
    }
    /// The menu bar panel is open: sample fast and refresh right away.
    var menuOpen = false {
        didSet { if menuOpen != oldValue { restartLoop() } }
    }
    /// Set when an app survives Force Quit; raises the restart finding.
    var stuckApp: String?
    let catalog: ProcessCatalog?

    @ObservationIgnored private var previous: Snapshot?
    /// Last 3 samples as id → CPU only, for smoothing (whole groups would cost megabytes).
    @ObservationIgnored private var history: [[String: Double]] = []
    @ObservationIgnored private var busy = BusyTracker()
    @ObservationIgnored private var loop: Task<Void, Never>?
    private(set) var enabled = false
    @ObservationIgnored private var ticking = false
    @ObservationIgnored private var itemsLoadedAt: Date?
    @ObservationIgnored private var aggregator = MinuteAggregator()
    @ObservationIgnored private let log = Logger(subsystem: "app.cleardisk.performance.ClearDisk", category: "monitor")

    init() {
        catalog = try? ProcessCatalog.bundled()
    }

    var interval: Duration {
        SamplingPolicy.interval(windowVisible: windowVisible, menuOpen: menuOpen,
                                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func start() {
        guard enabled, loop == nil, catalog != nil else { return }
        observeSleep()
        if mac == nil {
            let store = usageStore
            Task { [weak self] in
                guard let self else { return }
                mac = await Task.detached { MacInfo.read() }.value
                await Task.detached { try? store.prune(now: Date()) }.value
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPaused { await self.tick() }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused { checkNow() }
    }

    func checkNow() {
        guard enabled else { return }
        Task { await tick() }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { start() }
        else {
            loop?.cancel()
            loop = nil
            resetBaseline()
            aggregator = MinuteAggregator()
        }
    }

    /// After sleep, cumulative CPU deltas would span the whole nap.
    func resetBaseline() {
        previous = nil
        history = []
    }

    func explanation(for g: ProcessGroup) -> Explanation? {
        explanations[g.id] ?? catalog?.explain(g)
    }

    func group(id: String?) -> ProcessGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    /// Launch agents, daemons and app login items, joined with what's running.
    /// Refreshed at most once a minute unless forced.
    func refreshBackgroundItems(force: Bool = false) async {
        if !force, let t = itemsLoadedAt, Date().timeIntervalSince(t) < (windowVisible ? 60 : 600) { return }
        itemsLoadedAt = Date()
        let processes = previous?.processes ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser
        backgroundItems = await Task.detached {
            BackgroundItemsReader.markRunning(BackgroundItemsReader.scan(home: home),
                                              launchctl: (try? PSProcessSource.launchctlList()) ?? [:], processes: processes)
        }.value
    }

    /// CPU and memory of a running background item, from the latest sample.
    func usage(pid: Int32) -> ProcessUsage? {
        for g in groups { if let m = g.members.first(where: { $0.pid == pid }) { return m } }
        return nil
    }

    private func record(signals: SystemSignals, memory: MemoryBreakdown) {
        let now = Date()
        cpuHistory.append(CPUPoint(date: now, load: signals.cpuLoadPercent))
        cpuHistory.removeAll { now.timeIntervalSince($0.date) > 600 }
        guard keepHistory,
              let minute = aggregator.add(cpuLoad: signals.cpuLoadPercent, pressure: signals.pressure,
                                          swap: signals.swapUsedBytes, memUsed: memory.used, at: now) else { return }
        let store = usageStore
        do { try store.append(minute) }
        catch { log.error("history write failed: \(error.localizedDescription, privacy: .public)") }
    }

    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []

    /// Pause while asleep; on wake, drop the CPU baseline so the nap doesn't
    /// show up as one giant delta.
    private func observeSleep() {
        guard sleepObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.loop?.cancel(); self?.loop = nil }
            },
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetBaseline(); self?.start() }
            },
        ]
    }

    func clearHistory() throws {
        try usageStore.clear()
        aggregator = MinuteAggregator()
    }

    private func restartLoop() {
        loop?.cancel()
        loop = nil
        start()
    }

    func tick() async {
        guard enabled, !Task.isCancelled, !ticking, let catalog else { return }
        ticking = true
        defer { ticking = false }
        let prev = previous
        let uid = getuid()
        let explain = windowVisible
        do {
            let s = try await Task.detached { () throws -> (Snapshot, [ProcessGroup], SystemSignals, [String: Explanation], MemoryBreakdown) in
                let snap = try PSProcessSource().sample()
                // Footprint is only readable for our own processes; don't ask for the rest.
                let own = Set(snap.processes.lazy.filter { $0.uid == uid }.map(\.pid))
                let usage = CPUMeter.usage(previous: prev, current: snap,
                                           footprint: { own.contains($0) ? MemoryReader.footprint(pid: $0) : nil })
                let groups = AppGrouper.group(usage, currentUID: uid)
                // Row explanations are only needed while the window shows them.
                let explanations = explain ? Dictionary(groups.map { ($0.id, catalog.explain($0)) }, uniquingKeysWith: { a, _ in a }) : [:]
                return (snap, groups, SignalReader.read(totalCPUPercent: usage.reduce(0) { $0 + $1.cpuPercent }),
                        explanations, MemoryStats.read())
            }.value
            guard enabled, !Task.isCancelled else { return }
            if explain && windowVisible { explanations = s.3 }
            memory = s.4
            record(signals: s.2, memory: s.4)
            previous = s.0
            history = Array((history + [Smoother.cpuByID(s.1)]).suffix(3))
            let smoothed = Smoother.average(latest: s.1, history: history)
            let spotlightCPU = smoothed.filter { Diagnosis.spotlightFamily.contains($0.primary.name) }.reduce(0) { $0 + $1.cpuPercent }
            spotlightBusySince = busy.update(spotlightCPU: spotlightCPU, now: Date())
            groups = smoothed
            signals = s.2
            if let stuck = stuckApp, !Diagnosis.isRunning(app: stuck, in: s.1) { stuckApp = nil }
            result = Diagnosis.run(DiagnosisInput(signals: s.2, groups: smoothed, spotlightBusySince: spotlightBusySince,
                                                  lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                                  stuckApp: stuckApp, now: Date()), catalog: catalog)
            lastChecked = Date()
            error = nil
            // Background items only feed the window; skip the scan while it's closed.
            if windowVisible { await refreshBackgroundItems() }
        } catch {
            self.error = "Couldn't read processes. Retrying."
            log.error("sample failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

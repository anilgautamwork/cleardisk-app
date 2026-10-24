import Foundation

public enum Smoother {
    /// The light form kept in history: group id → CPU, nothing else.
    public static func cpuByID(_ groups: [ProcessGroup]) -> [String: Double] {
        Dictionary(groups.map { ($0.id, $0.cpuPercent) }, uniquingKeysWith: +)
    }

    /// Averages each latest group's CPU over the history (which should end
    /// with the latest sample), counting a missing sample as 0 — so one spike
    /// never becomes a finding. Memory and membership come from `latest`.
    public static func average(latest: [ProcessGroup], history: [[String: Double]]) -> [ProcessGroup] {
        guard !history.isEmpty else { return latest }
        return latest.map { g in
            var g = g
            g.cpuPercent = history.reduce(0) { $0 + ($1[g.id] ?? 0) } / Double(history.count)
            return g
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }
}

/// How often ClearDisk samples. Fast while someone is looking; slow when it's
/// just keeping the menu bar dot and history current, slower on Low Power Mode.
public enum SamplingPolicy {
    public static func interval(windowVisible: Bool, menuOpen: Bool, lowPower: Bool) -> Duration {
        if windowVisible || menuOpen { return .seconds(3) }
        return lowPower ? .seconds(60) : .seconds(30)
    }
}

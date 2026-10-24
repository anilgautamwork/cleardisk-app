import Darwin
import Foundation

public struct ProcessUsage: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let uid: UInt32
    public let user: String
    public let path: String
    public let name: String
    /// 100% = one full core.
    public let cpuPercent: Double
    public let memoryBytes: Int64

    public init(pid: Int32, ppid: Int32, uid: UInt32, user: String, path: String, name: String,
                cpuPercent: Double, memoryBytes: Int64) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.user = user
        self.path = path
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public enum CPUMeter {
    /// Exact CPU % from the change in cumulative CPU time between two samples.
    /// Falls back to `ps`'s decayed %cpu for new processes, reused pids, or a
    /// first sample — never negative, never divided by a zero interval.
    public static func usage(previous: Snapshot?, current: Snapshot,
                             footprint: (Int32) -> Int64?) -> [ProcessUsage] {
        let before = Dictionary((previous?.processes ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let interval = previous.map { current.takenAt.timeIntervalSince($0.takenAt) } ?? 0
        return current.processes.map { p in
            var cpu = p.psCPU
            if interval > 0, let old = before[p.pid], old.path == p.path, p.cpuTime >= old.cpuTime {
                cpu = (p.cpuTime - old.cpuTime) / interval * 100
            }
            return ProcessUsage(pid: p.pid, ppid: p.ppid, uid: p.uid, user: p.user, path: p.path, name: p.name,
                                cpuPercent: max(0, cpu), memoryBytes: footprint(p.pid) ?? p.rssBytes)
        }
    }
}

public enum MemoryReader {
    /// The figure Activity Monitor shows as "Memory". Readable only for the
    /// current user's processes; nil otherwise (caller falls back to RSS).
    public static func footprint(pid: Int32) -> Int64? {
        var info = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return rc == 0 ? Int64(info.ri_phys_footprint) : nil
    }
}

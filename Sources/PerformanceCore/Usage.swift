import Darwin
import Foundation

public struct MemoryBreakdown: Sendable, Equatable {
    public let total: Int64
    public let app: Int64
    public let wired: Int64
    public let compressed: Int64
    public let cached: Int64
    public let free: Int64

    /// Activity Monitor's "Memory Used".
    public var used: Int64 { min(total, app + wired + compressed) }
}

public enum MemoryStats {
    public static func read() -> MemoryBreakdown {
        var s = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard kr == KERN_SUCCESS else { return MemoryBreakdown(total: total, app: 0, wired: 0, compressed: 0, cached: 0, free: total) }
        let page = Int64(sysconf(_SC_PAGESIZE))
        return MemoryBreakdown(total: total,
                               app: max(0, Int64(s.internal_page_count) - Int64(s.purgeable_count)) * page,
                               wired: Int64(s.wire_count) * page,
                               compressed: Int64(s.compressor_page_count) * page,
                               cached: (Int64(s.external_page_count) + Int64(s.purgeable_count)) * page,
                               free: Int64(s.free_count) * page)
    }
}

/// One minute of history. Short keys keep 30 days of files small.
public struct MinuteRecord: Codable, Sendable, Equatable {
    /// Unix time in minutes.
    public let t: Int
    public let cpu: Double
    public let cpuMax: Double
    /// 0 normal, 1 elevated, 2 critical — the worst seen in the minute.
    public let pressure: Int
    public let swap: Int64
    public let memUsed: Int64
    public let n: Int

    public init(t: Int, cpu: Double, cpuMax: Double, pressure: Int, swap: Int64, memUsed: Int64, n: Int) {
        self.t = t
        self.cpu = cpu
        self.cpuMax = cpuMax
        self.pressure = pressure
        self.swap = swap
        self.memUsed = memUsed
        self.n = n
    }
}

public struct MinuteAggregator: Sendable {
    private var minute: Int?
    private var sum = 0.0, peak = 0.0, worst = 0, swap: Int64 = 0, mem: Int64 = 0, n = 0

    public init() {}

    /// Returns the finished minute when a sample lands in a new minute.
    public mutating func add(cpuLoad: Double, pressure: Pressure, swap: Int64, memUsed: Int64, at date: Date) -> MinuteRecord? {
        let m = Int(date.timeIntervalSince1970 / 60)
        var finished: MinuteRecord?
        if let current = minute, current != m, n > 0 {
            finished = MinuteRecord(t: current, cpu: sum / Double(n), cpuMax: peak, pressure: worst, swap: self.swap, memUsed: mem, n: n)
            sum = 0; peak = 0; worst = 0; n = 0
        }
        minute = m
        sum += cpuLoad
        peak = max(peak, cpuLoad)
        worst = max(worst, pressure == .critical ? 2 : pressure == .elevated ? 1 : 0)
        self.swap = swap
        mem = memUsed
        n += 1
        return finished
    }
}

/// `usage-YYYY-MM-DD.jsonl`, one file per UTC day, one record per line.
public struct UsageStore: Sendable {
    private static let lock = NSRecursiveLock()
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private static func dayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return "usage-\(f.string(from: date)).jsonl"
    }

    private func files() -> [URL] {
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter {
                guard $0.lastPathComponent.range(of: #"^usage-\d{4}-\d{2}-\d{2}\.jsonl$"#, options: .regularExpression) != nil,
                      let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func append(_ r: MinuteRecord) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.dayName(Date(timeIntervalSince1970: TimeInterval(r.t * 60))))
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
           values.isSymbolicLink == true || values.isRegularFile != true {
            throw CocoaError(.fileWriteNoPermission)
        }
        var line = try JSONEncoder().encode(r)
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// Skips corrupt lines instead of failing the whole history.
    public func load(since: Date) -> [MinuteRecord] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let first = since == .distantPast ? "" : Self.dayName(since)
        let sinceMinute = since == .distantPast ? Int.min : Int(since.timeIntervalSince1970 / 60)
        let decoder = JSONDecoder()
        return files().filter { $0.lastPathComponent >= first }.flatMap { url -> [MinuteRecord] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap { try? decoder.decode(MinuteRecord.self, from: Data($0.utf8)) }
        }
        .filter { $0.t >= sinceMinute }
        .sorted { $0.t < $1.t }
    }

    public func prune(olderThanDays days: Int = 30, now: Date) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let cutoff = Self.dayName(now.addingTimeInterval(-Double(days) * 86400))
        for url in files() where url.lastPathComponent < cutoff {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func clear() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        for url in files() { try FileManager.default.removeItem(at: url) }
    }
}

public struct MacInfo: Sendable, Equatable {
    public let name: String
    public let chip: String
    public let memoryBytes: Int64
    public let isAppleSilicon: Bool

    public init(name: String, chip: String, memoryBytes: Int64, isAppleSilicon: Bool) {
        self.name = name
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.isAppleSilicon = isAppleSilicon
    }

    public static func parse(systemProfilerJSON data: Data) -> MacInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hw = (root["SPHardwareDataType"] as? [[String: Any]])?.first,
              let name = hw["machine_name"] as? String else { return nil }
        let chip = hw["chip_type"] as? String
        return MacInfo(name: name, chip: chip ?? (hw["cpu_type"] as? String) ?? "Unknown chip",
                       memoryBytes: (hw["physical_memory"] as? String).flatMap(parseSize) ?? Int64(ProcessInfo.processInfo.physicalMemory),
                       isAppleSilicon: chip?.hasPrefix("Apple") ?? false)
    }

    /// "128 GB" → bytes.
    static func parseSize(_ s: String) -> Int64? {
        let parts = s.split(separator: " ")
        guard parts.count == 2, let n = Int64(parts[0]) else { return nil }
        switch parts[1] {
        case "TB": return n << 40
        case "GB": return n << 30
        case "MB": return n << 20
        default: return nil
        }
    }

    /// Reads `system_profiler` once (about a second); call off the main thread.
    public static func read() -> MacInfo {
        if let out = try? Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"]),
           let info = parse(systemProfilerJSON: Data(out.stdout.utf8)) {
            return info
        }
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        var model = [CChar](repeating: 0, count: 64)
        var msize = model.count
        sysctlbyname("hw.model", &model, &msize, nil, 0)
        return MacInfo(name: String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), chip: arm == 1 ? "Apple silicon" : "Intel",
                       memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory), isAppleSilicon: arm == 1)
    }
}

public enum Bottleneck: Sendable, Equatable {
    case memory(recommendedGB: Int, pressureShare: Double)
    case cpu(busyShare: Double)
    case storage(freeShare: Double)
}

public enum UpgradeVerdict: Sendable, Equatable {
    case notEnoughData(hoursMeasured: Int)
    case healthy(hoursMeasured: Int)
    case bottlenecks([Bottleneck], hoursMeasured: Int)
}

/// "Do you need a new Mac?" — rules of spec §18, over the records given
/// (the caller passes the last 7 days).
public enum UpgradeAdvisor {
    public static let memorySteps = [16, 24, 32, 36, 48, 64, 96, 128, 192, 256]

    public static func recommendedMemoryGB(current: Int) -> Int {
        memorySteps.first { $0 >= current * 2 } ?? memorySteps[memorySteps.count - 1]
    }

    public static func evaluate(records: [MinuteRecord], memoryBytes: Int64, diskFreeShare: Double) -> UpgradeVerdict {
        let hours = records.count / 60
        let days = Set(records.map { $0.t / 1440 }).count
        guard records.count >= 1440, days >= 2 else { return .notEnoughData(hoursMeasured: hours) }

        let n = Double(records.count)
        let pressureShare = Double(records.filter { $0.pressure >= 1 }.count) / n
        let busyShare = Double(records.filter { $0.cpu >= 80 }.count) / n
        let swaps = records.map(\.swap).sorted()
        let medianSwap = swaps[swaps.count / 2]

        var found: [Bottleneck] = []
        if pressureShare >= 0.15 || Double(medianSwap) >= 0.25 * Double(memoryBytes) {
            found.append(.memory(recommendedGB: recommendedMemoryGB(current: Int(memoryBytes >> 30)), pressureShare: pressureShare))
        }
        if busyShare >= 0.20 { found.append(.cpu(busyShare: busyShare)) }
        if diskFreeShare < 0.15 { found.append(.storage(freeShare: diskFreeShare)) }
        return found.isEmpty ? .healthy(hoursMeasured: hours) : .bottlenecks(found, hoursMeasured: hours)
    }
}

/// A slice of history for the charts: average CPU, share of minutes under
/// memory pressure, and peak swap.
public struct UsageBucket: Sendable, Equatable, Identifiable {
    public let start: Date
    public let cpu: Double
    public let pressureShare: Double
    public let swap: Int64
    public let minutes: Int

    public init(start: Date, cpu: Double, pressureShare: Double, swap: Int64, minutes: Int) {
        self.start = start
        self.cpu = cpu
        self.pressureShare = pressureShare
        self.swap = swap
        self.minutes = minutes
    }

    public var id: Date { start }
}

public enum UsageBuckets {
    /// Groups minute records into buckets of `size` minutes (60 = hourly, 1440 = daily, UTC).
    public static func bucket(_ records: [MinuteRecord], minutes size: Int) -> [UsageBucket] {
        Dictionary(grouping: records) { $0.t / size }
            .map { key, list in
                let n = Double(list.count)
                return UsageBucket(start: Date(timeIntervalSince1970: TimeInterval(key * size * 60)),
                                   cpu: list.reduce(0) { $0 + $1.cpu } / n,
                                   pressureShare: Double(list.filter { $0.pressure >= 1 }.count) / n,
                                   swap: list.map(\.swap).max() ?? 0, minutes: list.count)
            }
            .sorted { $0.start < $1.start }
    }
}

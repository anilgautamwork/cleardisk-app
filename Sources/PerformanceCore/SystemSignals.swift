import Darwin
import Foundation

public enum Pressure: Sendable, Equatable {
    case normal, elevated, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 2: self = .elevated
        case 4: self = .critical
        default: self = .normal
        }
    }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .critical: "Critical"
        }
    }
}

public enum Thermal: Int, Sendable, Comparable {
    case normal, warm, hot, veryHot

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .fair: self = .warm
        case .serious: self = .hot
        case .critical: self = .veryHot
        default: self = .normal
        }
    }

    public static func < (a: Thermal, b: Thermal) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warm: "Warm"
        case .hot: "Hot"
        case .veryHot: "Very hot"
        }
    }
}

public struct SystemSignals: Sendable, Equatable {
    /// 0–100 across all cores.
    public var cpuLoadPercent: Double
    public var coreCount: Int
    public var pressure: Pressure
    public var swapUsedBytes: Int64
    public var thermal: Thermal
    public var diskFreeBytes: Int64
    public var diskTotalBytes: Int64
    public var uptime: TimeInterval
    public var memoryTotalBytes: Int64

    public init(cpuLoadPercent: Double = 0, coreCount: Int = 8, pressure: Pressure = .normal, swapUsedBytes: Int64 = 0,
                thermal: Thermal = .normal, diskFreeBytes: Int64 = 400_000_000_000, diskTotalBytes: Int64 = 500_000_000_000,
                uptime: TimeInterval = 3600, memoryTotalBytes: Int64 = 16 << 30) {
        self.cpuLoadPercent = cpuLoadPercent
        self.coreCount = coreCount
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.thermal = thermal
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.uptime = uptime
        self.memoryTotalBytes = memoryTotalBytes
    }

    /// Sum of per-process CPU (100 = one core) → share of the whole machine.
    public static func cpuLoad(totalPercent: Double, cores: Int) -> Double {
        min(100, max(0, totalPercent / Double(max(cores, 1))))
    }
}

public enum SignalReader {
    public static func read(totalCPUPercent: Double) -> SystemSignals {
        let info = ProcessInfo.processInfo
        let cores = info.activeProcessorCount
        var level: Int32 = 1
        _ = sysctlValue("kern.memorystatus_vm_pressure_level", &level)
        var swap = xsw_usage()
        _ = sysctlValue("vm.swapusage", &swap)
        var boot = timeval()
        let uptime = sysctlValue("kern.boottime", &boot)
            ? Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec) : info.systemUptime
        let volume = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                                             .volumeTotalCapacityKey])
        return SystemSignals(cpuLoadPercent: SystemSignals.cpuLoad(totalPercent: totalCPUPercent, cores: cores),
                             coreCount: cores,
                             pressure: Pressure(sysctlLevel: level),
                             swapUsedBytes: Int64(swap.xsu_used),
                             thermal: Thermal(info.thermalState),
                             diskFreeBytes: volume?.volumeAvailableCapacityForImportantUsage ?? 0,
                             diskTotalBytes: Int64(volume?.volumeTotalCapacity ?? 0),
                             uptime: uptime,
                             memoryTotalBytes: Int64(info.physicalMemory))
    }

    private static func sysctlValue<T: BitwiseCopyable>(_ name: String, _ value: inout T) -> Bool {
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0
    }
}

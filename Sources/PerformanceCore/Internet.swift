import CoreWLAN
import Foundation
import Network

public enum LinkType: Sendable, Equatable {
    case wifi, ethernet, other, offline
}

public enum WiFiBand: Sendable, Equatable {
    case ghz2_4, ghz5, ghz6, unknown

    public var label: String {
        switch self {
        case .ghz2_4: "2.4 GHz"
        case .ghz5: "5 GHz"
        case .ghz6: "6 GHz"
        case .unknown: "Unknown band"
        }
    }
}

public enum SignalQuality: Int, Sendable, Comparable {
    case poor, fair, good, excellent

    public init(rssi: Int) {
        switch rssi {
        case (-60)...: self = .excellent
        case (-70)...: self = .good
        case (-80)...: self = .fair
        default: self = .poor
        }
    }

    public static func < (a: SignalQuality, b: SignalQuality) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }
}

public struct WiFiLink: Sendable, Equatable {
    public let rssi: Int
    public let noise: Int
    public let transmitRateMbps: Double
    public let band: WiFiBand

    public init(rssi: Int, noise: Int, transmitRateMbps: Double, band: WiFiBand) {
        self.rssi = rssi
        self.noise = noise
        self.transmitRateMbps = transmitRateMbps
        self.band = band
    }

    public var quality: SignalQuality { SignalQuality(rssi: rssi) }
}

public enum LinkReader {
    /// Signal, noise, rate and band need no Location permission; the network
    /// name does, so it's never read.
    public static func wifi() -> WiFiLink? {
        guard let i = CWWiFiClient.shared().interface(), i.rssiValue() != 0 else { return nil }
        let band: WiFiBand = switch i.wlanChannel()?.channelBand {
        case .band2GHz: .ghz2_4
        case .band5GHz: .ghz5
        case .band6GHz: .ghz6
        default: .unknown
        }
        return WiFiLink(rssi: i.rssiValue(), noise: i.noiseMeasurement(), transmitRateMbps: i.transmitRate(), band: band)
    }

    public static func currentType() async -> LinkType {
        await withCheckedContinuation { (c: CheckedContinuation<LinkType, Never>) in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                if path.status != .satisfied { c.resume(returning: .offline) }
                else if path.usesInterfaceType(.wifi) { c.resume(returning: .wifi) }
                else if path.usesInterfaceType(.wiredEthernet) { c.resume(returning: .ethernet) }
                else { c.resume(returning: .other) }
            }
            monitor.start(queue: DispatchQueue(label: "app.cleardisk.performance.path"))
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

public struct SpeedResult: Codable, Sendable, Equatable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let responsivenessRPM: Int?
    public let baseRTTms: Double?
    public let measuredAt: Date

    public init(downloadMbps: Double, uploadMbps: Double, responsivenessRPM: Int?, baseRTTms: Double?, measuredAt: Date) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsivenessRPM = responsivenessRPM
        self.baseRTTms = baseRTTms
        self.measuredAt = measuredAt
    }
}

public enum Responsiveness: String, Sendable {
    case high, medium, low

    public init(rpm: Int) {
        self = rpm >= 1000 ? .high : rpm >= 300 ? .medium : .low
    }

    public var label: String { rawValue.capitalized }
}

public enum SpeedTestError: Error, Equatable {
    case unreadable, failed(String)
}

/// Apple's built-in `networkQuality` tool, against Apple's servers. Runs only
/// when the user confirms it.
public enum SpeedTest {
    public static let arguments = ["-c", "-M", "25"]

    public static func parse(_ json: Data, at date: Date) throws -> SpeedResult {
        guard let d = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let dl = (d["dl_throughput"] as? NSNumber)?.doubleValue,
              let ul = (d["ul_throughput"] as? NSNumber)?.doubleValue
        else { throw SpeedTestError.unreadable }
        return SpeedResult(downloadMbps: dl / 1_000_000, uploadMbps: ul / 1_000_000,
                           responsivenessRPM: (d["responsiveness"] as? NSNumber)?.intValue,
                           baseRTTms: (d["base_rtt"] as? NSNumber)?.doubleValue, measuredAt: date)
    }

    /// `-M 25` caps the test's own runtime, so the call ends on its own.
    public static func run() async throws -> SpeedResult {
        let out = try await Task.detached { try Shell.run("/usr/bin/networkQuality", arguments) }.value
        guard out.status == 0 else { throw SpeedTestError.failed(out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return try parse(Data(out.stdout.utf8), at: Date())
    }
}

public struct NetUsage: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double

    public init(pid: Int32, name: String, bytesInPerSec: Double, bytesOutPerSec: Double) {
        self.pid = pid
        self.name = name
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
    }

    public var total: Double { bytesInPerSec + bytesOutPerSec }
}

/// Per-app network use from `nettop` — works without admin rights.
public enum NetTop {
    public static let arguments = ["-P", "-d", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]

    /// Uses the last block only: in delta mode it holds the bytes moved in the
    /// 1-second interval, so values are already per second.
    public static func parse(_ csv: String) -> [NetUsage] {
        let lines = csv.split(separator: "\n")
        let start = (lines.lastIndex { $0.hasPrefix(",bytes_in") } ?? -1) + 1
        return lines[start...].compactMap { line -> NetUsage? in
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, let dot = f[0].lastIndex(of: "."), let pid = Int32(f[0][f[0].index(after: dot)...]),
                  let inB = Double(f[1]), let outB = Double(f[2]), inB + outB > 0 else { return nil }
            return NetUsage(pid: pid, name: String(f[0][..<dot]), bytesInPerSec: inB, bytesOutPerSec: outB)
        }
        .sorted { $0.total > $1.total }
    }

    /// Takes about 5 seconds.
    public static func sample() async throws -> [NetUsage] {
        let out = try await Task.detached { try Shell.run("/usr/bin/nettop", arguments) }.value
        return parse(out.stdout)
    }
}

public enum InternetDiagnosis {
    public static func run(link: LinkType, wifi: WiFiLink?, speed: SpeedResult?, usage: [NetUsage],
                           appName: (Int32) -> String?) -> [Finding] {
        if link == .offline {
            return [Finding(kind: .offline, severity: .high, headline: "You're offline.",
                            detail: "Check Wi-Fi or your network cable.", primaryFix: .openWiFiSettings)]
        }
        var found: [Finding] = []
        let onWiFi = link == .wifi
        if onWiFi, let w = wifi {
            switch w.quality {
            case .poor, .fair:
                found.append(Finding(kind: .weakWiFi, severity: w.quality == .poor ? .high : .medium,
                                     headline: w.quality == .poor ? "Your Wi-Fi signal is weak." : "Your Wi-Fi signal is only fair.",
                                     detail: "Move closer to your router or remove obstacles. Signal: \(w.rssi) dBm.",
                                     primaryFix: .openWiFiSettings))
            case .good, .excellent:
                if w.band == .ghz2_4 {
                    found.append(Finding(kind: .band24, severity: .low, headline: "You're on 2.4 GHz Wi-Fi.",
                                         detail: "5 GHz is usually much faster if your router supports it."))
                }
            }
        }
        if let s = speed, s.downloadMbps < 10 {
            let detail = link == .ethernet
                ? "Your wired connection is fine, so the slowdown is your internet line or router."
                : (wifi.map { $0.quality >= .good } ?? false)
                    ? "Your Wi-Fi is fine, so the slowdown is your internet line or router."
                    : "Weak Wi-Fi may be part of it."
            found.append(Finding(kind: .slowLine, severity: .high,
                                 headline: "Your internet is slow: \(Int(s.downloadMbps.rounded())) Mbps down.", detail: detail))
        }
        if let rpm = speed?.responsivenessRPM, rpm < 300 {
            found.append(Finding(kind: .laggy, severity: .medium, headline: "Your connection gets laggy when it's busy.",
                                 detail: "Video calls and games may stutter while something else downloads."))
        }
        for u in usage where u.total >= 1_000_000 {
            found.append(Finding(kind: .bandwidthHog, severity: .medium,
                                 headline: "\(appName(u.pid) ?? u.name) is using \(Format.bytes(Int64(u.total)))/s of your connection.",
                                 detail: "Down \(Format.bytes(Int64(u.bytesInPerSec)))/s, up \(Format.bytes(Int64(u.bytesOutPerSec)))/s.",
                                 groupID: "pid:\(u.pid)"))
        }
        return found.enumerated()
            .sorted { $0.element.severity != $1.element.severity ? $0.element.severity > $1.element.severity : $0.offset < $1.offset }
            .map(\.element)
    }
}

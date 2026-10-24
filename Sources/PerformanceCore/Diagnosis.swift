import Foundation

public enum Severity: Int, Comparable, Sendable {
    case low = 1, medium, high, critical
    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

public enum FindingKind: String, Sendable {
    case heat, memory, cpuHog, spotlight, photos, windowServer, browser, lowDisk, longUptime, lowPower, stuckApp
    // Produced by InternetDiagnosis.
    case offline, weakWiFi, band24, slowLine, laggy, bandwidthHog
}

public struct Finding: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: FindingKind
    public let severity: Severity
    public let headline: String
    public let detail: String
    public let groupID: String?
    public let primaryFix: FixID?
    public let leaveNote: String?

    public init(kind: FindingKind, severity: Severity, headline: String, detail: String,
                groupID: String? = nil, primaryFix: FixID? = nil, leaveNote: String? = nil) {
        self.id = kind.rawValue + (groupID.map { ":" + $0 } ?? "")
        self.kind = kind
        self.severity = severity
        self.headline = headline
        self.detail = detail
        self.groupID = groupID
        self.primaryFix = primaryFix
        self.leaveNote = leaveNote
    }
}

public enum Status: Sendable, Equatable {
    case quiet, busy, struggling

    public init(_ findings: [Finding]) {
        if findings.contains(where: { $0.severity >= .high }) { self = .struggling }
        else { self = findings.isEmpty ? .quiet : .busy }
    }
}

public struct DiagnosisInput: Sendable {
    public var signals: SystemSignals
    /// Already smoothed over the last 3 samples.
    public var groups: [ProcessGroup]
    public var spotlightBusySince: Date?
    public var lowPowerMode: Bool
    /// An app that survived Force Quit.
    public var stuckApp: String?
    public var now: Date

    public init(signals: SystemSignals, groups: [ProcessGroup], spotlightBusySince: Date?,
                lowPowerMode: Bool, stuckApp: String?, now: Date) {
        self.signals = signals
        self.groups = groups
        self.spotlightBusySince = spotlightBusySince
        self.lowPowerMode = lowPowerMode
        self.stuckApp = stuckApp
        self.now = now
    }
}

public struct DiagnosisResult: Sendable, Equatable {
    public let status: Status
    /// Ranked: severity, then CPU impact.
    public let findings: [Finding]

    public init(findings: [Finding]) {
        self.findings = findings
        self.status = Status(findings)
    }

    public var hero: Finding? { findings.first }
    public var more: [Finding] { Array(findings.dropFirst().prefix(4)) }
}

public enum Diagnosis {
    public static let spotlightFamily: Set<String> = ["mds", "mds_stores", "mdworker_shared", "mdworker", "mdbulkimport",
                                                     "corespotlightd", "spotlightknowledged"]
    public static let photosFamily: Set<String> = ["photoanalysisd", "mediaanalysisd"]
    public static let browserApps = ["Google Chrome.app", "Brave Browser.app", "Microsoft Edge.app"]
    static let virtualizationPath = "/System/Library/Frameworks/Virtualization.framework/"
    /// Apps that run virtual machines through Apple's Virtualization framework.
    static let vmHosts: Set<String> = ["Docker", "OrbStack", "UTM", "Parallels Desktop", "VMware Fusion", "Podman Desktop",
                                       "Rancher Desktop", "VirtualBuddy", "Tart", "Multipass"]

    /// The stuck-app finding clears once the app has finally gone.
    public static func isRunning(app: String, in groups: [ProcessGroup]) -> Bool {
        groups.contains { $0.displayName == app }
    }

    public static func isBrowser(_ g: ProcessGroup) -> Bool {
        guard let app = g.appPath else { return false }
        return browserApps.contains { app.hasSuffix("/" + $0) }
    }

    public static func run(_ input: DiagnosisInput, catalog: ProcessCatalog) -> DiagnosisResult {
        let s = input.signals
        var found: [(Finding, Double)] = []
        func add(_ f: Finding, cpu: Double = 0) { found.append((f, cpu)) }

        if let app = input.stuckApp {
            add(Finding(kind: .stuckApp, severity: .high, headline: "\(app) won't quit. Restart your Mac to clear it.",
                        detail: "Some apps can't be closed once they're stuck. A restart clears them.", primaryFix: .restartMac))
        }

        switch s.thermal {
        case .normal: break
        case .warm:
            add(Finding(kind: .heat, severity: .low, headline: "Your Mac is warm, so macOS is slowing it slightly to cool down.",
                        detail: "kernel_task holds back other work to cool your Mac. Heavy apps and blocked vents make it worse.",
                        leaveNote: "Leave it"))
        case .hot:
            add(Finding(kind: .heat, severity: .high, headline: "Your Mac is hot and slowing itself down to cool off.",
                        detail: "kernel_task holds back other work to cool your Mac. Quit heavy apps and give it some air.",
                        leaveNote: "Leave it"))
        case .veryHot:
            add(Finding(kind: .heat, severity: .critical, headline: "Your Mac is very hot and running much slower to protect itself.",
                        detail: "Quit heavy apps, unplug extra displays and give it some air.", leaveNote: "Leave it"))
        }

        let gb: Int64 = 1 << 30
        if s.pressure != .normal || s.swapUsedBytes > 4 * gb {
            let target = input.groups.filter(\.quittable).max { $0.memoryBytes < $1.memoryBytes }
                ?? input.groups.max { $0.memoryBytes < $1.memoryBytes }
            let detail = target.map { "\($0.displayName) is using \(Format.bytes($0.memoryBytes))." }
                ?? "Swap in use: \(Format.bytes(s.swapUsedBytes))."
            add(Finding(kind: .memory, severity: s.pressure == .critical ? .high : .medium,
                        headline: "Your Mac is running low on memory.", detail: detail, groupID: target?.id,
                        primaryFix: target?.quittable == true ? .quitApp : nil), cpu: target?.cpuPercent ?? 0)
        }

        // "High" needs 200%+ and a quarter of the whole Mac: 266% is a crisis on 8 cores, not on 16.
        let heavy = { (cpu: Double) in cpu >= 200 && cpu >= Double(s.coreCount) * 25 }
        var claimed = Set<String>()
        let spotlight = input.groups.filter { spotlightFamily.contains($0.primary.name) }
        let spotlightCPU = spotlight.reduce(0) { $0 + $1.cpuPercent }
        if spotlightCPU >= 50, let top = spotlight.max(by: { $0.cpuPercent < $1.cpuPercent }) {
            claimed.formUnion(spotlight.map(\.id))
            let stuck = input.spotlightBusySince.map { input.now.timeIntervalSince($0) > 3 * 3600 } ?? false
            add(Finding(kind: .spotlight, severity: stuck ? .high : .low, headline: "Spotlight is doing a lot of work.",
                        detail: stuck
                            ? "Spotlight has been busy for over 3 hours, which usually means it's stuck. Rebuilding the index often fixes it."
                            : "\(top.primary.name) is using \(Format.percent(spotlightCPU)) CPU while it updates the search index. That's normal after an update or a large file change.",
                        groupID: top.id, primaryFix: stuck ? .rebuildSpotlightIndex : .openSpotlightSettings,
                        leaveNote: "Settles on its own"), cpu: spotlightCPU)
        }

        let photos = input.groups.filter { photosFamily.contains($0.primary.name) }
        let photosCPU = photos.reduce(0) { $0 + $1.cpuPercent }
        if photosCPU >= 30, let top = photos.max(by: { $0.cpuPercent < $1.cpuPercent }) {
            claimed.formUnion(photos.map(\.id))
            add(Finding(kind: .photos, severity: .low, headline: "Photos is analyzing your library.",
                        detail: "It finds faces and objects in your photos, mostly while your Mac is idle and plugged in.",
                        groupID: top.id, leaveNote: "Runs while plugged in"), cpu: photosCPU)
        }

        if let ws = input.groups.first(where: { $0.primary.name == "WindowServer" }) {
            claimed.insert(ws.id)
            if ws.cpuPercent >= 40 {
                add(Finding(kind: .windowServer, severity: .medium, headline: "WindowServer is busy drawing your screen.",
                            detail: "Many windows, external displays or transparency effects keep it busy.",
                            groupID: ws.id, primaryFix: .explain), cpu: ws.cpuPercent)
            }
        }

        for b in input.groups where isBrowser(b) {
            claimed.insert(b.id)
            if b.memoryBytes >= 1_500_000_000 || b.cpuPercent >= 50 {
                add(Finding(kind: .browser, severity: .medium,
                            headline: "\(b.displayName) and \(b.helperCount) helpers are using \(Format.percent(b.cpuPercent)) CPU and \(Format.bytes(b.memoryBytes)).",
                            detail: "Each tab and extension runs as its own helper. Closing tabs you don't need frees memory.",
                            groupID: b.id, primaryFix: .reviewTabs), cpu: b.cpuPercent)
            }
        }

        for g in input.groups where !claimed.contains(g.id) && g.cpuPercent >= 80 {
            if g.primary.path.hasPrefix(virtualizationPath) {
                let host = input.groups.first { vmHosts.contains($0.displayName) && $0.appPath != nil }
                add(Finding(kind: .cpuHog, severity: heavy(g.cpuPercent) ? .high : .medium,
                            headline: "A virtual machine is using \(Format.percent(g.cpuPercent)) CPU.",
                            detail: host.map { "It's run by \($0.displayName). Quitting \($0.displayName) frees all of it." }
                                ?? catalog.explain(g).summary,
                            groupID: host?.id ?? g.id, primaryFix: host?.quittable == true ? .quitApp : .explain), cpu: g.cpuPercent)
                continue
            }
            let e = catalog.explain(g)
            let fix = g.quittable ? (e.fixes.first(where: \.isPaid) ?? .explain) : .explain
            add(Finding(kind: .cpuHog, severity: heavy(g.cpuPercent) ? .high : .medium,
                        headline: "\(g.displayName) is using \(Format.percent(g.cpuPercent)) CPU.", detail: e.summary,
                        groupID: g.id, primaryFix: fix, leaveNote: e.idleNote), cpu: g.cpuPercent)
        }

        // Absolute space matters more than percent: 99 GB free on a 1 TB disk is fine.
        let freeGB = Double(s.diskFreeBytes) / 1_000_000_000
        if s.diskTotalBytes > 0, freeGB < 15 {
            add(Finding(kind: .lowDisk, severity: .high, headline: "Your disk is almost full.",
                        detail: "Only \(Format.bytes(s.diskFreeBytes)) free. macOS slows down when space runs low.",
                        primaryFix: .openClearDisk))
        } else if s.diskTotalBytes > 0, Double(s.diskFreeBytes) < Double(s.diskTotalBytes) * 0.10, freeGB < 50 {
            add(Finding(kind: .lowDisk, severity: .medium, headline: "Your disk is getting full.",
                        detail: "\(Format.bytes(s.diskFreeBytes)) free. Keep at least 10% free so macOS has room for memory and updates.",
                        primaryFix: .openClearDisk))
        }

        if input.lowPowerMode {
            add(Finding(kind: .lowPower, severity: .low, headline: "Low Power Mode is on, so your Mac runs slower to save energy.",
                        detail: "Turn it off in Battery settings when you need full speed.", primaryFix: .openBatterySettings))
        }

        let days = Int(s.uptime / 86400)
        if days > 14, s.swapUsedBytes > 2 * gb {
            add(Finding(kind: .longUptime, severity: .low, headline: "Your Mac hasn't restarted in \(days) days.",
                        detail: "A restart clears memory that has built up over time.", primaryFix: .restartMac))
        }

        let ranked = found.enumerated().sorted { a, b in
            if a.element.0.severity != b.element.0.severity { return a.element.0.severity > b.element.0.severity }
            if a.element.1 != b.element.1 { return a.element.1 > b.element.1 }
            return a.offset < b.offset
        }
        return DiagnosisResult(findings: ranked.map(\.element.0))
    }
}

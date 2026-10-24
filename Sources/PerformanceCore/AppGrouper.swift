import Foundation

/// A row in the UI: an app with all its helper processes, or one standalone process.
public struct ProcessGroup: Sendable, Equatable, Identifiable {
    /// `appPath` for app groups, `"pid:<pid>"` for standalone processes.
    public let id: String
    public let displayName: String
    public let appPath: String?
    public let members: [ProcessUsage]
    public var cpuPercent: Double
    public var memoryBytes: Int64
    /// Pre-checked against `SafetyGate`; `FixRunner` re-checks with the live app.
    public let quittable: Bool

    public init(id: String, displayName: String, appPath: String?, members: [ProcessUsage],
                cpuPercent: Double, memoryBytes: Int64, quittable: Bool) {
        self.id = id
        self.displayName = displayName
        self.appPath = appPath
        self.members = members
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.quittable = quittable
    }

    public var helperCount: Int { members.count - 1 }

    /// The app's main executable if it's running, else the busiest member.
    public var primary: ProcessUsage {
        if let appPath, let main = members.first(where: { AppGrouper.isMainExecutable($0.path, of: appPath) }) {
            return main
        }
        return members.max(by: { $0.cpuPercent < $1.cpuPercent }) ?? members[0]
    }
}

public enum AppGrouper {
    /// The outermost `.app` bundle containing `path`, so Chrome's nested
    /// helper apps resolve to `/Applications/Google Chrome.app`.
    public static func outermostApp(in path: String) -> String? {
        guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil)
        else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    static func isMainExecutable(_ path: String, of appPath: String) -> Bool {
        let dir = appPath + "/Contents/MacOS/"
        return path.hasPrefix(dir) && !path.dropFirst(dir.count).contains("/")
    }

    public static func group(_ usages: [ProcessUsage], currentUID: UInt32) -> [ProcessGroup] {
        var order: [String] = []
        var buckets: [String: (app: String?, members: [ProcessUsage])] = [:]
        for u in usages {
            let app = outermostApp(in: u.path)
            let key = app ?? "pid:\(u.pid)"
            if buckets[key] == nil { order.append(key); buckets[key] = (app, []) }
            buckets[key]!.members.append(u)
        }
        return order.map { key in
            let b = buckets[key]!
            let name = b.app.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? b.members[0].name
            var g = ProcessGroup(id: key, displayName: name, appPath: b.app, members: b.members,
                                 cpuPercent: b.members.reduce(0) { $0 + $1.cpuPercent },
                                 memoryBytes: b.members.reduce(0) { $0 + $1.memoryBytes }, quittable: false)
            let p = g.primary
            g = ProcessGroup(id: g.id, displayName: g.displayName, appPath: g.appPath, members: g.members,
                             cpuPercent: g.cpuPercent, memoryBytes: g.memoryBytes,
                             quittable: SafetyGate.canQuit(uid: p.uid, currentUID: currentUID, path: p.path,
                                                           name: name, isRegularApp: b.app != nil))
            return g
        }
        .sorted { $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.displayName < $1.displayName }
    }
}

/// The one rule every quit goes through. Deny by default.
public enum SafetyGate {
    public static let denyNames: Set<String> = ["kernel_task", "WindowServer", "launchd", "loginwindow", "Dock",
                                                "Finder", "SystemUIServer", "ControlCenter", "ClearDisk", "ClearDiskApp", "WhySlow"]
    static let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/"]

    public static func canQuit(uid: UInt32, currentUID: UInt32, path: String, name: String, isRegularApp: Bool) -> Bool {
        isRegularApp
            && uid == currentUID
            && !denyNames.contains(name)
            && !denyNames.contains((path as NSString).lastPathComponent)
            && !systemPrefixes.contains(where: path.hasPrefix)
    }
}

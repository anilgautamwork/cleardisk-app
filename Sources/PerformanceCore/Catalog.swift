import Foundation

public enum Verdict: String, Codable, Sendable {
    case safe, review, leave

    public var label: String {
        switch self {
        case .safe: "Safe to quit"
        case .review: "Review"
        case .leave: "Leave it"
        }
    }
}

public enum FixID: String, Codable, Sendable {
    case explain, openSpotlightSettings, openLoginItemsSettings, openDisplaySettings, openAccessibilityDisplay,
         openBatterySettings, openWiFiSettings, quitApp, rebuildSpotlightIndex, reviewTabs, openClearDisk, restartMac

    /// The one-click fixes the $7 license unlocks. Settings links, explanations
    /// and Restart stay free.
    public var isPaid: Bool { self == .quitApp || self == .rebuildSpotlightIndex }
}

public struct CatalogEntry: Codable, Sendable, Equatable {
    public struct Match: Codable, Sendable, Equatable {
        public var names: [String] = []
        public var pathPrefixes: [String] = []
        public var launchdLabels: [String] = []
    }

    public let id: String
    public let match: Match
    public let title: String
    public let summary: String
    public let whyHigh: String
    public let verdict: Verdict
    public let idleNote: String?
    public let fixes: [FixID]
    public let guide: String
    public let symbol: String?
}

public struct Explanation: Sendable, Equatable {
    public let entryID: String?
    public let title: String
    public let summary: String
    public let whyHigh: String?
    public let verdict: Verdict
    public let idleNote: String?
    public let fixes: [FixID]
    public let guide: String?
    public let symbol: String
    public let isFallback: Bool
}

public struct ProcessCatalog: Sendable {
    public let entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) { self.entries = entries }

    /// The packaged app ships processes.json in Contents/Resources; SwiftPM's
    /// `Bundle.module` (which traps if its bundle is missing) is only touched
    /// in development and tests.
    public static func bundled() throws -> ProcessCatalog {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.url(forResource: "processes", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return ProcessCatalog(entries: try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url)))
        }
        guard let url = Bundle.main.url(forResource: "processes", withExtension: "json")
                ?? Bundle.module.url(forResource: "processes", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return ProcessCatalog(entries: try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url)))
    }

    /// Exact name, then path prefix, then the fallbacks of spec §7.
    public func explain(name: String, path: String, appName: String?) -> Explanation {
        if let e = entries.first(where: { $0.match.names.contains(name) })
            ?? entries.first(where: { $0.match.pathPrefixes.contains(where: path.hasPrefix) }) {
            return Self.explanation(e)
        }
        if ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/usr/bin/", "/bin/"].contains(where: path.hasPrefix) {
            return Self.fallback("Part of macOS", "A built-in macOS process.", .leave, [])
        }
        if let appName {
            return Self.fallback("Part of \(appName)", "Belongs to \(appName). Quitting \(appName) stops it.", .safe, [.quitApp])
        }
        return Self.fallback("Not in our list yet", "We don't have an explanation for this process yet.", .review, [])
    }

    /// The explanation for a UI row: the app's main process, or the standalone process.
    public func explain(_ g: ProcessGroup) -> Explanation {
        explain(name: g.primary.name, path: g.primary.path, appName: g.appPath == nil ? nil : g.displayName)
    }

    /// Background items: launchd label prefix, then spec §10's fallbacks.
    public func explain(launchdLabel: String, ownerApp: String?) -> Explanation {
        if let e = entries.first(where: { $0.match.launchdLabels.contains(where: launchdLabel.hasPrefix) }) {
            return Self.explanation(e)
        }
        if let ownerApp {
            return Self.fallback("Added by \(ownerApp)", "A background helper installed by \(ownerApp).", .review, [])
        }
        return Self.fallback("Unknown developer", "A background helper from a developer ClearDisk doesn't recognize.", .review, [])
    }

    private static func explanation(_ e: CatalogEntry) -> Explanation {
        Explanation(entryID: e.id, title: e.title, summary: e.summary, whyHigh: e.whyHigh, verdict: e.verdict,
                    idleNote: e.idleNote, fixes: e.fixes, guide: e.guide, symbol: e.symbol ?? "gearshape", isFallback: false)
    }

    private static func fallback(_ title: String, _ summary: String, _ verdict: Verdict, _ fixes: [FixID]) -> Explanation {
        Explanation(entryID: nil, title: title, summary: summary, whyHigh: nil, verdict: verdict, idleNote: nil,
                    fixes: fixes, guide: nil, symbol: "gearshape", isFallback: true)
    }
}

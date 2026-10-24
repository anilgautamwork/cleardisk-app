import Foundation

/// Chromium browsers share one AppleScript dictionary.
public enum ChromiumBrowser: String, CaseIterable, Sendable {
    case chrome = "com.google.Chrome"
    case brave = "com.brave.Browser"
    case edge = "com.microsoft.edgemac"

    public var appName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .brave: "Brave Browser"
        case .edge: "Microsoft Edge"
        }
    }

    public var memorySaverURL: String {
        self == .edge ? "edge://settings/system/managePerformance" : "chrome://settings/performance"
    }

    /// Matches an app group's `appPath` (".../Google Chrome.app").
    public init?(appPath: String) {
        guard let b = Self.allCases.first(where: { appPath.hasSuffix("/\($0.appName).app") }) else { return nil }
        self = b
    }
}

public struct BrowserTab: Sendable, Equatable, Identifiable {
    public let id: String
    public let windowID: String
    public let tabID: String
    public let title: String
    public let url: String
    public let isActive: Bool

    public init(id: String, windowID: String, tabID: String, title: String, url: String, isActive: Bool) {
        self.id = id
        self.windowID = windowID
        self.tabID = tabID
        self.title = title
        self.url = url
        self.isActive = isActive
    }

    public var host: String { URL(string: url)?.host() ?? url }
}

public struct BrowserWindow: Sendable, Equatable, Identifiable {
    public let id: String
    public let isIncognito: Bool
    public let profile: String?
    public var tabs: [BrowserTab]
}

public struct MergePlan: Sendable, Equatable {
    public let targetWindowID: String
    public let urls: [String]
    public let windowsToClose: [String]
    /// The Chrome profile all merged windows share (nil = default profile).
    public let profile: String?

    public init(targetWindowID: String, urls: [String], windowsToClose: [String], profile: String?) {
        self.targetWindowID = targetWindowID
        self.urls = urls
        self.windowsToClose = windowsToClose
        self.profile = profile
    }
}

public struct ExtensionUsage: Sendable, Equatable {
    public let count: Int
    public let memoryBytes: Int64
}

/// AppleScript sources and their output format. Records are separated by
/// ASCII 30 and fields by ASCII 31, so tab titles can contain anything.
public enum TabScript {
    static let rs: Character = "\u{1E}", us: Character = "\u{1F}"

    public static func list(_ b: ChromiumBrowser) -> String {
        """
        set RS to character id 30
        set US to character id 31
        set out to ""
        tell application id "\(b.rawValue)"
            repeat with w in windows
                set wid to (id of w) as text
                set out to out & "W" & US & wid & US & (mode of w) & US & ((active tab index of w) as text) & US & (name of w) & RS
                repeat with t in tabs of w
                    set out to out & "T" & US & wid & US & ((id of t) as text) & US & (title of t) & US & (URL of t) & RS
                end repeat
            end repeat
        end tell
        return out
        """
    }

    public static func parse(_ output: String, appName: String) -> [BrowserWindow] {
        var windows: [BrowserWindow] = []
        var active: [String: Int] = [:]
        for record in output.split(separator: rs) {
            let f = record.split(separator: us, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5 else { continue }
            if f[0] == "W" {
                active[f[1]] = Int(f[3]) ?? 1
                // Fail closed: anything that isn't plainly "normal" is treated as incognito.
                windows.append(BrowserWindow(id: f[1], isIncognito: f[2] != "normal",
                                             profile: TabCleanup.profile(fromWindowName: f[4], appName: appName), tabs: []))
            } else if f[0] == "T", let i = windows.lastIndex(where: { $0.id == f[1] }) {
                let position = windows[i].tabs.count + 1
                windows[i].tabs.append(BrowserTab(id: "\(f[1])/\(f[2])", windowID: f[1], tabID: f[2], title: f[3], url: f[4],
                                                  isActive: position == active[f[1]]))
            }
        }
        return windows
    }

    public static func close(_ tabs: [BrowserTab], _ b: ChromiumBrowser) -> String {
        let lines = tabs.map { "close (every tab of \(normalWindow($0.windowID)) whose id is \(literal($0.tabID)))" }
        return wrap(lines, b)
    }

    public static func merge(_ plan: MergePlan, _ b: ChromiumBrowser) -> String {
        let target = normalWindow(plan.targetWindowID)
        let lines = plan.urls.map { "make new tab at end of tabs of \(target) with properties {URL:\(literal($0, alwaysQuote: true))}" }
            + plan.windowsToClose.map { "close \(normalWindow($0))" }
        return wrap(lines, b)
    }

    public static func openMemorySaver(_ b: ChromiumBrowser) -> String {
        wrap(["if (count of windows) is 0 then make new window",
              "make new tab at end of tabs of front window with properties {URL:\(literal(b.memorySaverURL, alwaysQuote: true))}",
              "activate"], b)
    }

    private static func wrap(_ lines: [String], _ b: ChromiumBrowser) -> String {
        (["tell application id \"\(b.rawValue)\""] + lines.map { "    " + $0 } + ["end tell"]).joined(separator: "\n")
    }

    /// Chrome itself refuses to touch an incognito window, whatever we parsed.
    static func normalWindow(_ id: String) -> String {
        "(first window whose id is \(literal(id)) and mode is \"normal\")"
    }

    /// Chromium window and tab ids are integers; AppleScript won't match an
    /// integer id against a quoted string, so ASCII digits stay bare.
    static func literal(_ s: String, alwaysQuote: Bool = false) -> String {
        if !alwaysQuote, !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public enum TabCleanup {
    public static func normalize(_ url: String) -> String {
        guard var c = URLComponents(string: url) else { return url }
        c.fragment = nil
        c.scheme = c.scheme?.lowercased()
        c.host = c.host?.lowercased()
        var s = c.string ?? url
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Tabs to close: every repeat of a page after its first appearance in
    /// the same profile (two Gmail accounts in two profiles aren't duplicates).
    /// Incognito tabs are never touched.
    public static func duplicates(in windows: [BrowserWindow]) -> [BrowserTab] {
        var seen = Set<String>()
        var dupes: [BrowserTab] = []
        for w in windows where !w.isIncognito {
            for t in w.tabs where !seen.insert((w.profile ?? "") + "\u{1F}" + normalize(t.url)).inserted {
                dupes.append(t)
            }
        }
        return dupes
    }

    /// Merges windows of one profile only — tabs moved across profiles would
    /// reload signed in to the wrong account. Picks the profile with the most
    /// windows; the target is its window with the most tabs (fewest reloads).
    public static func mergePlan(_ windows: [BrowserWindow]) -> MergePlan? {
        let byProfile = Dictionary(grouping: windows.filter { !$0.isIncognito }) { $0.profile ?? "" }
        guard let group = byProfile.values.filter({ $0.count >= 2 }).max(by: { $0.count < $1.count }),
              let target = group.max(by: { $0.tabs.count < $1.tabs.count }) else { return nil }
        let others = group.filter { $0.id != target.id }
        return MergePlan(targetWindowID: target.id, urls: others.flatMap { $0.tabs.map(\.url) },
                         windowsToClose: others.map(\.id), profile: target.profile)
    }

    /// Chrome titles windows "⟨tab⟩ - Google Chrome - ⟨Profile⟩" when more
    /// than one profile is in use.
    public static func profile(fromWindowName name: String, appName: String) -> String? {
        guard let r = name.range(of: " - \(appName) - ", options: .backwards) else { return nil }
        let p = name[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? nil : p
    }

    /// `ps -axo pid=,rss=,args=` lines → the browser's extension processes.
    public static func extensions(fromPSArgs text: String, appPath: String) -> ExtensionUsage {
        var count = 0
        var bytes: Int64 = 0
        for line in text.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let rss = Int64(f[1]), f[2].hasPrefix(appPath + "/"), f[2].contains("--extension-process")
            else { continue }
            count += 1
            bytes += rss * 1024
        }
        return ExtensionUsage(count: count, memoryBytes: bytes)
    }
}

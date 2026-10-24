import Foundation

public enum ItemScope: String, Sendable {
    case userAgent, systemAgent, systemDaemon, appBundled
}

/// A launch agent, launch daemon or app-bundled login item — the things
/// behind macOS's "Background Items Added" notice. Read-only in 1.0.
public struct BackgroundItem: Sendable, Equatable, Identifiable {
    public var id: String { label + "|" + source }
    public let label: String
    public let program: String?
    /// The plist or login-item bundle it came from.
    public let source: String
    public let scope: ItemScope
    public let ownerApp: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public var pid: Int32?

    public init(label: String, program: String?, source: String, scope: ItemScope, ownerApp: String?,
                runAtLoad: Bool, keepAlive: Bool, pid: Int32?) {
        self.label = label
        self.program = program
        self.source = source
        self.scope = scope
        self.ownerApp = ownerApp
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.pid = pid
    }
}

public enum BackgroundItemsReader {
    public static func parse(plist: Data, source: String, scope: ItemScope, bundleRoot: String? = nil) -> BackgroundItem? {
        guard let d = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let label = d["Label"] as? String else { return nil }
        var program = d["Program"] as? String
        if program == nil, let rel = d["BundleProgram"] as? String, let bundleRoot { program = bundleRoot + "/" + rel }
        if program == nil { program = (d["ProgramArguments"] as? [String])?.first }
        // KeepAlive may be a bool or a dictionary of conditions; any dictionary means "restart it".
        let keepAlive = (d["KeepAlive"] as? Bool) ?? (d["KeepAlive"] is [String: Any])
        return BackgroundItem(label: label, program: program, source: source, scope: scope, ownerApp: nil,
                              runAtLoad: d["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive, pid: nil)
    }

    /// `launchctl list` → label: pid, running jobs only.
    public static func parseLaunchctlList(_ text: String) -> [String: Int32] {
        var out: [String: Int32] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: "\t")
            if f.count >= 3, let pid = Int32(f[0]) { out[String(f[2])] = pid }
        }
        return out
    }

    public static func ownerApp(program: String?, label: String, installed: [String: String]) -> String? {
        let helperApp = program.flatMap(AppGrouper.outermostApp(in:))
        let helperName = helperApp.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        // A real app owns its items; a helper app tucked in /Library (like GoogleUpdater) defers to the label.
        if let helperApp, helperApp.hasPrefix("/Applications/") || helperApp.contains("/Users/") { return helperName }
        // ponytail: label-prefix heuristic; use code-signing team ID if it misattributes
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return helperName }
        let best = installed.keys
            .map { id -> (String, Int) in
                let other = id.split(separator: ".")
                return (id, zip(parts, other).prefix { $0 == $1 }.count)
            }
            .filter { $0.1 >= 2 }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }
        return best.flatMap { installed[$0.0] } ?? helperName
    }

    public static func scan(home: URL, root: URL = URL(fileURLWithPath: "/")) -> [BackgroundItem] {
        let fm = FileManager.default
        let apps = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("Applications"), includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        var installed: [String: String] = [:]
        for app in apps {
            if let id = bundleInfo(app)?["CFBundleIdentifier"] as? String {
                installed[id] = app.deletingPathExtension().lastPathComponent
            }
        }

        var items: [BackgroundItem] = []
        for (dir, scope) in [(home.appendingPathComponent("Library/LaunchAgents"), ItemScope.userAgent),
                             (root.appendingPathComponent("Library/LaunchAgents"), .systemAgent),
                             (root.appendingPathComponent("Library/LaunchDaemons"), .systemDaemon)] {
            for item in plists(in: dir, scope: scope, bundleRoot: nil) {
                items.append(with(item, owner: ownerApp(program: item.program, label: item.label, installed: installed)))
            }
        }
        for app in apps {
            let owner = app.deletingPathExtension().lastPathComponent
            let lib = app.appendingPathComponent("Contents/Library")
            for sub in ["LaunchAgents", "LaunchDaemons"] {
                for item in plists(in: lib.appendingPathComponent(sub), scope: .appBundled, bundleRoot: app.path) {
                    items.append(with(item, owner: owner))
                }
            }
            let loginItems = (try? fm.contentsOfDirectory(at: lib.appendingPathComponent("LoginItems"), includingPropertiesForKeys: nil)) ?? []
            for login in loginItems where login.pathExtension == "app" {
                guard let info = bundleInfo(login), let id = info["CFBundleIdentifier"] as? String else { continue }
                let exe = (info["CFBundleExecutable"] as? String).map { login.appendingPathComponent("Contents/MacOS/\($0)").path }
                items.append(BackgroundItem(label: id, program: exe, source: login.path, scope: .appBundled, ownerApp: owner,
                                            runAtLoad: true, keepAlive: false, pid: nil))
            }
        }
        return items
    }

    public static func markRunning(_ items: [BackgroundItem], launchctl: [String: Int32],
                                   processes: [ProcessSample]) -> [BackgroundItem] {
        let byPath = Dictionary(processes.map { ($0.path, $0.pid) }, uniquingKeysWith: { a, _ in a })
        return items.map { item in
            var item = item
            item.pid = launchctl[item.label] ?? item.program.flatMap { byPath[$0] }
            return item
        }
    }

    private static func plists(in dir: URL, scope: ItemScope, bundleRoot: String?) -> [BackgroundItem] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { parse(plist: $0, source: url.path, scope: scope, bundleRoot: bundleRoot) }
        }
    }

    private static func bundleInfo(_ bundle: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func with(_ item: BackgroundItem, owner: String?) -> BackgroundItem {
        BackgroundItem(label: item.label, program: item.program, source: item.source, scope: item.scope, ownerApp: owner,
                       runAtLoad: item.runAtLoad, keepAlive: item.keepAlive, pid: item.pid)
    }
}

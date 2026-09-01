import Foundation

/// One reclaimable developer-junk finding.
public struct DevJunkItem: Identifiable, Sendable {
    public enum Action: Sendable {
        /// Can be moved to the Trash; `defaultSelected` seeds the checkbox.
        case trashable(defaultSelected: Bool)
        /// Never trash from here — explain what to do instead.
        case advisory
    }

    public let id: String
    public let title: String
    public let path: String
    public let bytes: Int64
    public let note: String
    public let action: Action
}

/// Finds rebuildable developer junk: node_modules anywhere, plus the known
/// fixed locations in the home folder. Deliberately EXCLUDES ~/Library/Caches
/// (the System Data screen already cleans it) and .git (deleting it destroys
/// repo history — junk-colored in the treemap, never offered for cleaning).
public enum DevJunkScan {

    /// `homeRoot`/`homePath`: the user's home subtree within the scan — the
    /// scan root itself for a home scan, or /Users/<name> inside a full-disk
    /// scan. nil when the scan doesn't include home (folder scans).
    public static func find(root: FileNode, scanPath: String,
                            homeRoot: FileNode?, homePath: String) -> [DevJunkItem] {
        var items: [DevJunkItem] = []

        // node_modules anywhere in the scanned tree.
        func walk(_ node: FileNode, path: String, depth: Int) {
            guard depth < 12, let children = node.children else { return }
            for child in children where child.isDirectory {
                let childPath = path + "/" + child.name
                if child.name == "node_modules" {
                    if child.size > 50_000_000 {
                        items.append(DevJunkItem(
                            id: childPath, title: "node_modules — \(node.name)",
                            path: childPath, bytes: child.size,
                            note: "Comes back with `npm install`. Uncheck if you're actively working on this project.",
                            action: .trashable(defaultSelected: false)))
                    }
                    continue
                }
                if child.name == ".git" || (node === homeRoot && child.name == "Library") {
                    continue
                }
                if child.size > 50_000_000 {
                    walk(child, path: childPath, depth: depth + 1)
                }
            }
        }
        walk(root, path: scanPath == "/" ? "" : scanPath, depth: 0)

        // Fixed home-folder locations.
        if let homeRoot {
            func node(_ components: [String]) -> FileNode? {
                var current: FileNode? = homeRoot
                for c in components { current = current?.child(c) }
                return current
            }
            func add(_ components: [String], _ title: String, _ note: String,
                     selected: Bool, advisory: Bool = false) {
                guard let found = node(components), found.size > 10_000_000 else { return }
                let path = homePath + "/" + components.joined(separator: "/")
                items.append(DevJunkItem(
                    id: path, title: title, path: path, bytes: found.size, note: note,
                    action: advisory ? .advisory : .trashable(defaultSelected: selected)))
            }

            add(["Library", "Developer", "Xcode", "DerivedData"],
                "Xcode build files", "Xcode rebuilds these on the next build.", selected: true)
            add(["Library", "Developer", "Xcode", "Archives"],
                "Xcode archives", "Old app archives — keep if you need past releases.", selected: false)
            add(["Library", "Developer", "Xcode", "iOS DeviceSupport"],
                "iOS device support", "Recreated when you plug an iPhone in.", selected: true)
            add(["Library", "Developer", "CoreSimulator"],
                "iOS simulators", "Simulator devices and runtimes — re-download in Xcode when needed.", selected: false)
            add([".npm"], "npm cache", "npm re-downloads packages on demand.", selected: true)
            add([".cache"], "Tool caches (~/.cache)", "Command-line tools rebuild these automatically.", selected: true)
            add([".cargo", "registry"], "Rust crate cache", "cargo re-downloads crates on demand.", selected: true)
            add([".gradle", "caches"], "Gradle cache", "Gradle re-downloads dependencies on demand.", selected: true)
            add([".m2", "repository"], "Maven repository", "Maven re-downloads dependencies on demand.", selected: false)
            add([".ollama"], "AI models (Ollama)", "Re-download any model with `ollama pull`.", selected: false)
            add(["Library", "Containers", "com.docker.docker"],
                "Docker data",
                "Don't trash this — reclaim space inside Docker Desktop (Settings → Resources → Disk). Trashing it deletes all your containers.",
                selected: false, advisory: true)
        }

        return items.sorted { $0.bytes > $1.bytes }
    }
}

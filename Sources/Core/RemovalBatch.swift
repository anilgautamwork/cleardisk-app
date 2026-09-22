import Darwin
import Foundation

/// Synchronous filesystem work for a detached worker. No scan-tree/UI state
/// crosses this boundary; callers apply only returned successful paths.
public enum RemovalBatch {
    public enum Method: Sendable { case trash, permanently }

    public struct Target: Hashable, Sendable {
        public let path: String
        public let contentsOnly: Bool
        /// Direct child names omitted only when expanding a contents target.
        public let excludingChildNames: [String]
        public init(path: String, contentsOnly: Bool = false, excludingChildNames: [String] = []) {
            self.path = path
            self.contentsOnly = contentsOnly
            self.excludingChildNames = contentsOnly ? Array(Set(excludingChildNames)).sorted() : []
        }
    }

    public struct Result: Sendable {
        public let removedPaths: [String]
        public let trashedItems: [TrashService.TrashedItem]
        public let failures: [String]
    }

    /// Require the explicit keyword; never accept an empty or partial entry.
    public static func confirmationMatches(_ typed: String) -> Bool {
        typed == "delete"
    }

    public static func perform(targets: [Target], method: Method) -> Result {
        var failures: [String] = []
        var seenTargets: Set<Target> = []
        var candidates: Set<String> = []

        func addCandidate(_ path: String) {
            do {
                try validateWholeTarget(path)
                candidates.insert(path)
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }

        for target in targets {
            do {
                let path = try normalized(target.path)
                guard seenTargets.insert(Target(path: path, contentsOnly: target.contentsOnly, excludingChildNames: target.excludingChildNames)).inserted else { continue }
                if target.contentsOnly {
                    try validateContentsRoot(path)
                    // Expand only direct children. A directory child is one
                    // whole target, leaving the selected container intact.
                    let children = try FileManager.default.contentsOfDirectory(atPath: path)
                    let excluded = Set(target.excludingChildNames)
                    for name in children.sorted() where !excluded.contains(name) { addCandidate(path + "/" + name) }
                } else {
                    addCandidate(path)
                }
            } catch {
                failures.append("\(target.path.isEmpty ? "Empty path" : target.path): \(error.localizedDescription)")
            }
        }

        // Parents sort before descendants. Ancestor coverage eliminates both
        // duplicate operations and spurious missing-file errors after removal.
        let ordered = candidates.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
        }
        var selected: Set<String> = []
        var unique: [String] = []
        for path in ordered {
            var ancestor = (path as NSString).deletingLastPathComponent
            var covered = false
            while !ancestor.isEmpty && ancestor != "/" {
                if selected.contains(ancestor) { covered = true; break }
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
            if !covered { selected.insert(path); unique.append(path) }
        }

        var removed: [String] = []
        var trashed: [TrashService.TrashedItem] = []
        for path in unique {
            do {
                // Recheck immediately before acting: the directory may have
                // changed since expansion. TrashService also rechecks policy.
                try validateWholeTarget(path)
                switch method {
                case .trash:
                    if let url = try TrashService.trash(path) {
                        trashed.append(.init(originalPath: path, trashURL: url))
                    }
                case .permanently:
                    try TrashService.deleteForever(path)
                }
                removed.append(path)
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }
        return Result(removedPaths: removed, trashedItems: trashed, failures: failures)
    }

    private struct Refusal: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func normalized(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw Refusal(message: "Choose a valid absolute path.")
        }
        // Lexically collapsing '..' can hide a symlink traversal and change
        // which file the user meant. Refuse it instead of following it.
        guard !path.split(separator: "/").contains("..") else {
            throw Refusal(message: "Paths containing a parent-directory step aren’t accepted for removal.")
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func validateWholeTarget(_ path: String) throws {
        if case .refused(let reason) = TrashService.verdict(forTrashing: path) {
            throw Refusal(message: reason)
        }
        try validateDirectoryChain((path as NSString).deletingLastPathComponent)
        // A leaf symlink may be removed as the link itself; never traverse it.
        _ = try attributes(path)
    }

    private static func validateContentsRoot(_ path: String) throws {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        guard path != home else {
            throw Refusal(message: "ClearDisk won’t remove the contents of your entire user folder.")
        }
        // Cache/Logs containers must stay, so their whole-folder verdict can
        // be refused while their children are allowed. Check the existing
        // child policy before listing anything, then check every actual child.
        if case .refused(let reason) = TrashService.verdict(forTrashing: path + "/.cleardisk-contents-check") {
            throw Refusal(message: reason)
        }
        try validateDirectoryChain(path)
    }

    private static func validateDirectoryChain(_ path: String) throws {
        var current = ""
        for component in path.split(separator: "/") {
            current += "/" + component
            let info = try attributes(current)
            guard info.st_mode & S_IFMT != S_IFLNK else {
                throw Refusal(message: "This location passes through a symbolic link. Choose the original folder instead.")
            }
            guard info.st_mode & S_IFMT == S_IFDIR else {
                throw Refusal(message: "The selected contents location or one of its parents is not a folder.")
            }
        }
    }

    private static func attributes(_ path: String) throws -> stat {
        var value = stat()
        guard lstat(path, &value) == 0 else {
            let code = errno
            throw Refusal(message: "Couldn’t inspect this location: \(String(cString: strerror(code))).")
        }
        return value
    }
}

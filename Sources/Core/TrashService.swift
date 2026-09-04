import Foundation

/// The only removal path in ClearDisk. Trash and permanent removal share
/// the same deny-by-default blocklist; callers provide the required user
/// confirmation before invoking either operation.
public enum TrashService {

    public enum Verdict: Equatable, Sendable {
        case allowed
        /// User-facing reason the Trash button is disabled for this path.
        case refused(String)
    }

    /// ~/Library children that must never be trashed whole.
    static let protectedLibraryDirs: Set<String> = [
        "Keychains", "Preferences", "Mail", "Messages", "Mobile Documents",
        "CloudStorage", "Containers", "Group Containers", "Application Support",
        "Accounts", "Autosave Information", "Biome", "Daemon Containers",
    ]

    /// Library subtrees where cleaning is expected — these bypass the
    /// protected-dir rule for paths beneath them.
    static let cleanableLibraryRoots = ["Caches", "Logs", "Developer",
                                        "Application Support/MobileSync/Backup"]

    public static func verdict(forTrashing path: String, home: String = NSHomeDirectory()) -> Verdict {
        let p = (path as NSString).standardizingPath
        guard p.hasPrefix(home + "/") else {
            return .refused("ClearDisk only removes files inside your user folder.")
        }
        if p == home {
            return .refused("That's your entire user folder.")
        }
        let relative = String(p.dropFirst(home.count + 1))
        let components = relative.split(separator: "/").map(String.init)

        if components.first == "Library" {
            if components.count == 1 {
                return .refused("Your Library folder keeps your Mac working — ClearDisk never touches it whole.")
            }
            for root in cleanableLibraryRoots {
                let rootComponents = root.split(separator: "/").map(String.init)
                if components.count > rootComponents.count,
                   Array(components[1 ... rootComponents.count]) == rootComponents {
                    return .allowed
                }
            }
            if protectedLibraryDirs.contains(components[1]) {
                return .refused("This folder holds settings and account data your apps depend on.")
            }
            if components.count == 2 {
                return .refused("Top-level Library folders stay — clean inside them instead.")
            }
        }
        return .allowed
    }

    /// Move one item to the Trash. Returns its location in the Trash so the
    /// UI can offer undo (move it back).
    @discardableResult
    public static func trash(_ path: String) throws -> URL? {
        if case .refused(let reason) = verdict(forTrashing: path) {
            throw TrashError.refused(reason)
        }
        var trashedTo: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashedTo)
        return trashedTo as URL?
    }

    public struct TrashedItem: Sendable {
        public let originalPath: String
        public let trashURL: URL
        public init(originalPath: String, trashURL: URL) {
            self.originalPath = originalPath
            self.trashURL = trashURL
        }
    }

    /// Trash the CONTENTS of a directory (used by Clean Safely for cache
    /// roots — the directory itself stays, since apps expect it to exist).
    public static func trashContents(of directory: String) -> (trashed: [TrashedItem], failed: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return ([], 1) }
        var trashed: [TrashedItem] = []
        var failed = 0
        for name in names {
            let original = directory + "/" + name
            do {
                if let url = try trash(original) {
                    trashed.append(TrashedItem(originalPath: original, trashURL: url))
                }
            } catch {
                failed += 1
            }
        }
        return (trashed, failed)
    }

    /// Permanent deletion — the ONLY call site of FileManager.removeItem in
    /// the app (the release script enforces this). UI must gate it behind
    /// double confirmation with type-the-name validation; there is no undo.
    /// Same deny-by-default blocklist as trashing.
    public static func deleteForever(_ path: String) throws {
        if case .refused(let reason) = verdict(forTrashing: path) {
            throw TrashError.refused(reason)
        }
        try FileManager.default.removeItem(atPath: path)
    }

    public struct RestoreResult: Sendable {
        public let restoredPaths: [String]
        public let failedItems: [TrashedItem]
        public let failures: [String]
    }

    /// Report actual filesystem successes so callers never reattach a failed
    /// restore to their scan tree. Existing destination files are not replaced.
    public static func restoreReporting(_ items: [TrashedItem]) -> RestoreResult {
        var paths: [String] = []
        var failed: [TrashedItem] = []
        var failures: [String] = []
        for item in items {
            do {
                try FileManager.default.moveItem(at: item.trashURL,
                                                 to: URL(fileURLWithPath: item.originalPath))
                paths.append(item.originalPath)
            } catch {
                failed.append(item)
                failures.append("\(item.originalPath): \(error.localizedDescription)")
            }
        }
        return RestoreResult(restoredPaths: paths, failedItems: failed, failures: failures)
    }

    /// Compatibility wrapper for callers that only need the successful count.
    public static func restore(_ items: [TrashedItem]) -> Int {
        restoreReporting(items).restoredPaths.count
    }

    public enum TrashError: Error, LocalizedError {
        case refused(String)
        public var errorDescription: String? {
            if case .refused(let reason) = self { return reason }
            return nil
        }
    }
}

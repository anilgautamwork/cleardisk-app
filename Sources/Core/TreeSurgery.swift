import Foundation

/// In-place updates to a scanned tree after the app trashes or deletes
/// something — so the UI refreshes instantly instead of demanding a rescan.
/// Sizes are subtracted up the ancestor chain; moves to the Trash grow the
/// home .Trash node; undo reattaches the removed nodes.
public enum TreeSurgery {

    public struct Removed {
        public let parentPath: String
        public let node: FileNode
    }

    /// Nodes from the scan root down to `path`, or nil when the path isn't in
    /// the tree. `path == scanPath` yields [root].
    public static func chain(for path: String, root: FileNode, scanPath: String) -> [FileNode]? {
        let base = scanPath == "/" ? "" : scanPath
        if path == scanPath || path == base { return [root] }
        guard path.hasPrefix(base + "/") else { return nil }
        var nodes = [root]
        for component in path.dropFirst(base.count + 1).split(separator: "/") {
            guard let next = nodes.last?.child(String(component)) else { return nil }
            nodes.append(next)
        }
        return nodes
    }

    /// Detach the nodes at `paths`, subtracting their sizes from every
    /// ancestor. Paths not present (already gone) are skipped.
    public static func remove(paths: [String], root: FileNode,
                              scanPath: String) -> (removed: [Removed], bytes: Int64) {
        var removed: [Removed] = []
        var bytes: Int64 = 0
        for path in paths {
            guard let nodes = chain(for: path, root: root, scanPath: scanPath),
                  nodes.count >= 2 else { continue }
            let node = nodes[nodes.count - 1]
            let parent = nodes[nodes.count - 2]
            parent.children?.removeAll { $0 === node }
            for ancestor in nodes.dropLast() {
                ancestor.size -= node.size
            }
            bytes += node.size
            removed.append(Removed(parentPath: (path as NSString).deletingLastPathComponent,
                                   node: node))
        }
        return (removed, bytes)
    }

    /// Undo: put detached nodes back and restore ancestor sizes.
    public static func reattach(_ removed: [Removed], root: FileNode, scanPath: String) {
        for item in removed {
            guard let ancestors = chain(for: item.parentPath, root: root, scanPath: scanPath),
                  let parent = ancestors.last else { continue }
            parent.children = (parent.children ?? []) + [item.node]
            for ancestor in ancestors {
                ancestor.size += item.node.size
            }
        }
    }

    /// Grow (or shrink, for undo) the home folder's .Trash node — files moved
    /// to the Trash still occupy disk there.
    public static func adjustTrash(by bytes: Int64, root: FileNode,
                                   scanPath: String, homePath: String) {
        guard bytes != 0,
              let ancestors = chain(for: homePath, root: root, scanPath: scanPath),
              let home = ancestors.last else { return }
        let trashNode: FileNode
        if let existing = home.child(".Trash") {
            trashNode = existing
        } else {
            trashNode = FileNode(name: ".Trash", isDirectory: true, size: 0, modTime: 0)
            home.children = (home.children ?? []) + [trashNode]
        }
        trashNode.size = max(0, trashNode.size + bytes)
        for ancestor in ancestors {
            ancestor.size += bytes
        }
    }
}

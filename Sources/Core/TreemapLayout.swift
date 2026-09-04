import Foundation
import CoreGraphics

/// Immutable, bounded geometry input. IDs refer to UI-owned nodes; this worker
/// never reads a FileNode, which may be changed by deletion or undo on the UI.
public enum TreemapLayout {
    public struct Entry: Sendable {
        public let id: Int
        public let size: Int64
        public let children: [Entry]
        public init(id: Int, size: Int64, children: [Entry] = []) {
            self.id = id; self.size = size; self.children = children
        }
    }
    public struct Tile: Sendable {
        public let id: Int
        public let rect: CGRect
        public let depth: Int
        public let paletteIndex: Int
        public let tintIndex: Int
    }
    public static func layout(entries: [Entry], in frame: CGRect) throws -> [Tile] {
        try Task.checkCancellation()
        let entries = entries.filter { $0.size > 0 }
        var result: [Tile] = []
        for item in Squarify.layout(sizes: entries.map { Double($0.size) }, in: frame) {
            try Task.checkCancellation()
            let entry = entries[item.index]
            let rect = item.rect.insetBy(dx: 2, dy: 2)
            guard rect.width > 3, rect.height > 3 else { continue }
            result.append(Tile(id: entry.id, rect: rect, depth: 0, paletteIndex: item.index, tintIndex: 0))
            guard rect.width > 110, rect.height > 76 else { continue }
            let inner = CGRect(x: rect.minX + 4, y: rect.minY + 40, width: rect.width - 8, height: rect.height - 44)
            let children = entry.children.filter { $0.size > 0 }
            for sub in Squarify.layout(sizes: children.map { Double($0.size) }, in: inner) {
                try Task.checkCancellation()
                let subRect = sub.rect.insetBy(dx: 1.5, dy: 1.5)
                guard subRect.width > 6, subRect.height > 6 else { continue }
                result.append(Tile(id: children[sub.index].id, rect: subRect, depth: 1, paletteIndex: item.index, tintIndex: sub.index))
            }
        }
        return result
    }
}

extension FileNode {
    /// Keep only the visible candidates, avoiding a full O(n log n) directory
    /// sort and an equally large temporary array on every resize. Stable ties.
    /// Must be called by the tree's current owner (UI after scan publication).
    public func largestChildren(limit: Int) -> [FileNode] {
        guard limit > 0 else { return [] }
        var top: [FileNode] = []
        top.reserveCapacity(limit)
        for child in children ?? [] where child.size > 0 {
            if top.count == limit, let last = top.last, child.size <= last.size { continue }
            let insertion = top.firstIndex { $0.size < child.size } ?? top.endIndex
            top.insert(child, at: insertion)
            if top.count > limit { top.removeLast() }
        }
        return top
    }
}

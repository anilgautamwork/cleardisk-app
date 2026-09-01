import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls/Huizing/van Wijk): greedy row packing that
/// keeps rectangles close to square. Pure geometry — no UI.
public enum Squarify {

    public struct Item: Sendable {
        public let index: Int
        public let rect: CGRect
        public init(index: Int, rect: CGRect) {
            self.index = index
            self.rect = rect
        }
    }

    /// Lay out `sizes` (any order; zero/negative entries get zero-area rects)
    /// inside `rect`. Result indexes refer to the input array.
    public static func layout(sizes: [Double], in rect: CGRect) -> [Item] {
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }

        let order = sizes.indices.sorted { sizes[$0] > sizes[$1] }
        let scale = Double(rect.width * rect.height) / total
        var areas = order.map { (index: $0, area: max(0, sizes[$0]) * scale) }

        var result: [Item] = []
        var free = rect

        while !areas.isEmpty {
            let side = Double(min(free.width, free.height))
            var row: [(index: Int, area: Double)] = [areas.removeFirst()]
            var rowArea = row[0].area

            while let next = areas.first {
                let with = worstAspect(row.map(\.area) + [next.area], rowArea + next.area, side)
                let without = worstAspect(row.map(\.area), rowArea, side)
                if with <= without {
                    row.append(areas.removeFirst())
                    rowArea += next.area
                } else {
                    break
                }
            }

            free = place(row: row, rowArea: rowArea, in: free, into: &result)
        }
        return result
    }

    private static func worstAspect(_ areas: [Double], _ total: Double, _ side: Double) -> Double {
        guard total > 0, side > 0 else { return .infinity }
        let thickness = total / side
        var worst = 0.0
        for area in areas where area > 0 {
            let length = area / thickness
            worst = max(worst, max(length / thickness, thickness / length))
        }
        return worst == 0 ? .infinity : worst
    }

    /// Lay one row along the short side of `free`, returning the remainder.
    private static func place(row: [(index: Int, area: Double)], rowArea: Double,
                              in free: CGRect, into result: inout [Item]) -> CGRect {
        let horizontal = free.width >= free.height // row occupies a vertical strip
        let side = Double(horizontal ? free.height : free.width)
        let thickness = side > 0 ? rowArea / side : 0
        var offset = 0.0

        for entry in row {
            let length = rowArea > 0 ? side * (entry.area / rowArea) : 0
            let rect: CGRect
            if horizontal {
                rect = CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
            } else {
                rect = CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
            }
            result.append(Item(index: entry.index, rect: rect))
            offset += length
        }

        if horizontal {
            return CGRect(x: free.minX + thickness, y: free.minY,
                          width: max(0, free.width - thickness), height: free.height)
        } else {
            return CGRect(x: free.minX, y: free.minY + thickness,
                          width: free.width, height: max(0, free.height - thickness))
        }
    }
}

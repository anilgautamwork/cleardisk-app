import CoreGraphics
import Foundation

public struct WindowCount: Sendable, Equatable {
    public let ownerName: String
    public let ownerPID: Int32
    public let count: Int

    public init(ownerName: String, ownerPID: Int32, count: Int) {
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.count = count
    }
}

public struct DisplayInfo: Sendable, Equatable {
    public let count: Int
    public let scaledCount: Int
}

/// Who is making WindowServer work. Owner names and counts only — never
/// window titles — so no Screen Recording permission is needed.
public enum WindowCensus {
    public static func count(windowInfo: [[String: Any]]) -> [WindowCount] {
        var counts: [Int32: (String, Int)] = [:]
        for w in windowInfo {
            guard (w["kCGWindowLayer"] as? Int) == 0, (w["kCGWindowIsOnscreen"] as? Bool) ?? true,
                  let pid = w["kCGWindowOwnerPID"] as? Int32 ?? (w["kCGWindowOwnerPID"] as? Int).map(Int32.init),
                  let name = w["kCGWindowOwnerName"] as? String else { continue }
            counts[pid, default: (name, 0)].1 += 1
        }
        return counts.map { WindowCount(ownerName: $0.value.0, ownerPID: $0.key, count: $0.value.1) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.ownerName < $1.ownerName }
    }

    public static func live() -> [WindowCount] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return count(windowInfo: info)
    }

    /// A display counts as scaled when it isn't running at its largest pixel width.
    public static func displays() -> DisplayInfo {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &n) == .success else { return DisplayInfo(count: 0, scaledCount: 0) }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let scaled = ids.prefix(Int(n)).filter { id in
            guard let current = CGDisplayCopyDisplayMode(id),
                  let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
                  let native = modes.map(\.pixelWidth).max() else { return false }
            return current.pixelWidth != native
        }
        return DisplayInfo(count: Int(n), scaledCount: scaled.count)
    }
}

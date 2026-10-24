import Foundation

public struct HeavyFolder: Sendable, Equatable {
    public let path: String
    public let label: String
    public let bytes: Int64
}

/// Big, constantly-changing folders that keep Spotlight busy for no benefit.
/// Only locations that don't trigger macOS privacy prompts are measured —
/// never a sandboxed app's container (Docker's isn't sandboxed; UTM's is).
public enum SpotlightAdvisor {
    public static let candidates: [(label: String, relativePath: String)] = [
        ("Xcode build data", "Library/Developer/Xcode/DerivedData"),
        ("Docker data", "Library/Containers/com.docker.docker"),
        ("OrbStack data", ".orbstack"),
        ("Parallels virtual machines", "Parallels"),
    ]

    public static func heavyFolders(home: URL, minimumBytes: Int64 = 1_000_000_000) -> [HeavyFolder] {
        candidates.compactMap { c in
            let url = home.appendingPathComponent(c.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let size = allocatedSize(url)
            return size >= minimumBytes ? HeavyFolder(path: url.path, label: c.label, bytes: size) : nil
        }
    }

    static func allocatedSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

/// Tracks how long the Spotlight family has stayed at or above 50% CPU.
public struct BusyTracker: Sendable {
    public private(set) var busySince: Date?

    public init() {}

    public mutating func update(spotlightCPU: Double, now: Date) -> Date? {
        if spotlightCPU >= 50 {
            busySince = busySince ?? now
        } else {
            busySince = nil
        }
        return busySince
    }
}

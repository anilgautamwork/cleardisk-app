import Foundation

public enum StorageReviewDestination { case scan, largeFiles, caches, developerJunk }

public struct StorageMenuFile: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let bytes: Int64
    public init(path: String, name: String, bytes: Int64) {
        id = path
        self.name = name
        self.bytes = bytes
    }
}

/// Immutable values from a completed storage scan, never a new background scan.
public struct StorageMenuSummary: Sendable {
    public var scanDate: Date?
    public var isScanning: Bool
    public var files: [StorageMenuFile]
    public var cacheBytes: Int64?
    public var developerJunkBytes: Int64
    public var location: String
    public var skippedCount: Int
    public init(scanDate: Date? = nil, isScanning: Bool = false, files: [StorageMenuFile] = [],
                cacheBytes: Int64? = nil, developerJunkBytes: Int64 = 0, location: String = "",
                skippedCount: Int = 0) {
        self.scanDate = scanDate
        self.isScanning = isScanning
        self.files = files
        self.cacheBytes = cacheBytes
        self.developerJunkBytes = developerJunkBytes
        self.location = location
        self.skippedCount = skippedCount
    }
}

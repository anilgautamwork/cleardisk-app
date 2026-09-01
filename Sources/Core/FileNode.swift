import Foundation

/// One entry in the scanned tree. For directories, `size` is the subtree total.
/// @unchecked Sendable: mutated only while a scan builds it (single writer per
/// node); immutable once the scan returns and the tree crosses to the UI.
public final class FileNode: @unchecked Sendable {
    public let name: String
    public let isDirectory: Bool
    /// Allocated bytes on disk (not logical length): sparse and compressed
    /// files report what they actually occupy, matching `du`.
    public internal(set) var size: Int64
    /// Modification time, seconds since epoch. Powers "old downloads" etc.
    public let modTime: Int64
    public internal(set) var children: [FileNode]?

    init(name: String, isDirectory: Bool, size: Int64, modTime: Int64) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modTime = modTime
    }
}

public struct ScanStats: Sendable {
    public var fileCount = 0
    public var directoryCount = 0
    /// Entries we could not read (EPERM etc.) — feeds the Full Disk Access banner.
    public var skippedCount = 0
    public var totalBytes: Int64 = 0
    public init() {}
}

public enum ScanError: Error {
    case cannotOpen(String, Int32)
}

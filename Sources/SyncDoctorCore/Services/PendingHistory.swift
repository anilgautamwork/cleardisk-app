import Foundation

/// Stores only consecutive complete, comparable observations; no contents leave the Mac.
public struct PendingHistory: Codable, Sendable {
    public struct Observation: Codable, Sendable {
        public var firstSeen: Date
        public var lastSeen: Date
        public var count: Int
        var size: Int64
        var modified: Date
        var uploading: Bool
        var downloadStatus: DownloadStatus
        var downloadRequested: Bool?
    }
    public private(set) var observations: [String: Observation] = [:]
    private var roots: [String] = []
    public init() {}
    public mutating func record(_ result: ScanResult) {
        let scope = result.roots.map { $0.standardizedFileURL.path }.sorted()
        guard result.isComplete else { observations = [:]; roots = scope; return }
        if roots != scope { observations = [:] }
        roots = scope
        var next: [String: Observation] = [:]
        for item in result.items.prefix(50_000) {
            guard item.kind == .file, item.name != ".DS_Store", !item.name.hasPrefix("._"), item.isUbiquitous == true,
                  item.isUploaded == false, let uploading = item.isUploading,
                  item.downloadStatus != .unknown, item.isDownloading == false, item.hasUnresolvedConflicts == false, !item.hasAnyError,
                  let size = item.logicalSize, let modified = item.modificationDate else { continue }
            if var old = observations[item.path], old.size == size, old.modified == modified,
               old.uploading == uploading, old.downloadStatus == item.downloadStatus, old.downloadRequested == item.downloadRequested, result.finishedAt > old.lastSeen,
               result.finishedAt.timeIntervalSince(old.lastSeen) <= 7 * 86_400 {
                old.lastSeen = result.finishedAt; old.count = min(old.count + 1, 10_000); next[item.path] = old
            } else {
                next[item.path] = Observation(firstSeen: result.finishedAt, lastSeen: result.finishedAt, count: 1, size: size, modified: modified, uploading: uploading, downloadStatus: item.downloadStatus, downloadRequested: item.downloadRequested)
            }
        }
        observations = next
    }
    public func potentiallyStuckPaths(now: Date = Date(), minimumInterval: TimeInterval = 3 * 3600) -> Set<String> {
        Set(observations.filter { _, value in
            value.count >= 2 && value.lastSeen.timeIntervalSince(value.firstSeen) >= max(0, minimumInterval)
                && now >= value.lastSeen && now.timeIntervalSince(value.lastSeen) <= 7 * 86_400
        }.keys)
    }
}

import Foundation

// MARK: - Options

public struct ScanOptions: Sendable {
    /// Directories to walk. Normally `[ICloudDriveLocation.rootURL]`.
    public var roots: [URL]
    /// Descend into bundles/packages (.app, .pages, .photoslibrary, ...).
    /// iCloud syncs package contents item-by-item, so problems can hide inside.
    public var descendIntoPackages: Bool = true
    /// Include dot-files. Kept on by default: `.Trash`, `.icloud` placeholders
    /// (legacy) and hidden folders are exactly where sync problems accumulate.
    public var includeHidden: Bool = true
    /// Safety valve for huge libraries during development.
    public var maxItems: Int? = 50_000
    /// Emit a `.progress` event every N items.
    public var progressEvery: Int = 200

    public init(roots: [URL]) {
        self.roots = roots
    }
}

// MARK: - Issues (enumeration problems, not per-item sync problems)

public enum ScanIssueKind: String, Codable, Sendable {
    case permissionDenied
    case enumerationFailed
    case rootMissing
    case rootUnreadable
    case materializationPolicyUnavailable
    case coverageLimited
}

public struct ScanIssue: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(path)" }
    public let path: String
    public let kind: ScanIssueKind
    public let error: ItemError?

    public init(path: String, kind: ScanIssueKind, error: ItemError?) {
        self.path = path; self.kind = kind; self.error = error
    }
}

// MARK: - Progress / events

public struct ScanProgress: Sendable {
    public let itemsScanned: Int
    public let currentPath: String
    public let elapsed: TimeInterval
}

public enum ScanEvent: Sendable {
    case started(roots: [URL])
    case progress(ScanProgress)
    case item(ICloudItem)
    case issue(ScanIssue)
    case finished(ScanResult)
}

// MARK: - Summary

/// Counts used by the Overview screen. Everything here is derived from real
/// items; nothing is estimated except the two `estimated*Bytes` fields, which
/// are labelled as such in the UI.
public struct ScanSummary: Codable, Sendable, Hashable {
    public var totalItems = 0
    public var files = 0
    public var directories = 0
    public var ubiquitousItems = 0
    public var nonUbiquitousItems = 0
    public var unknownUbiquity = 0
    public var unknownSyncState = 0

    public var syncedFiles = 0            // uploaded == true && downloaded (current)
    public var waitingToUpload = 0        // uploaded == false, not uploading, no error
    public var uploading = 0
    public var downloading = 0
    public var notDownloaded = 0          // cloud-only
    public var uploadErrors = 0
    public var downloadErrors = 0
    public var accessErrors = 0
    public var unresolvedConflicts = 0
    public var excludedFromSync = 0

    public var totalLogicalBytes: Int64 = 0
    public var estimatedLocalBytes: Int64 = 0
    public var estimatedCloudOnlyBytes: Int64 = 0

    public var problemCount: Int { uploadErrors + downloadErrors + unresolvedConflicts + accessErrors }

    public init() {}

    public init(items: [ICloudItem], issues: [ScanIssue]) {
        for item in items { add(item) }
        accessErrors += issues.filter { $0.kind == .permissionDenied }.count
    }

    public mutating func add(_ item: ICloudItem) {
        totalItems += 1
        switch item.kind {
        case .directory: directories += 1
        default: files += 1
        }
        switch item.isUbiquitous {
        case .some(true): ubiquitousItems += 1
        case .some(false): nonUbiquitousItems += 1
        case .none: unknownUbiquity += 1
        }

        if item.kind != .directory {
            if item.isUbiquitous == true && (item.isUploaded == nil || item.isUploading == nil || item.isDownloading == nil || item.hasUnresolvedConflicts == nil || item.downloadStatus == .unknown) { unknownSyncState += 1 }
            if item.isUploaded == true, item.downloadStatus == .current { syncedFiles += 1 }
            if item.isWaitingToUpload { waitingToUpload += 1 }
            if item.isUploading == true { uploading += 1 }
            if item.isDownloading == true { downloading += 1 }
            if item.downloadStatus == .notDownloaded { notDownloaded += 1 }
            if let size = item.logicalSize { totalLogicalBytes += size }
            estimatedLocalBytes += item.estimatedLocalBytes
            estimatedCloudOnlyBytes += item.estimatedCloudOnlyBytes
        }
        if item.name == ".DS_Store" || item.name.hasPrefix("._") { return }
        if item.uploadError != nil { uploadErrors += 1 }
        if item.downloadError != nil { downloadErrors += 1 }
        if item.accessError != nil { accessErrors += 1 }
        if item.hasUnresolvedConflicts == true { unresolvedConflicts += 1 }
        if item.isExcludedFromSync == true { excludedFromSync += 1 }
    }
}

// MARK: - Result

public struct ScanResult: Sendable {
    public let id: UUID
    public let roots: [URL]
    public let startedAt: Date
    public let finishedAt: Date
    public let items: [ICloudItem]
    public let issues: [ScanIssue]
    public let summary: ScanSummary
    public let wasCancelled: Bool
    public let hitItemLimit: Bool

    public var isComplete: Bool { !wasCancelled && !hitItemLimit && issues.isEmpty && !items.contains { $0.accessError != nil } }

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    public init(id: UUID = UUID(), roots: [URL], startedAt: Date, finishedAt: Date, items: [ICloudItem],
                issues: [ScanIssue], wasCancelled: Bool, hitItemLimit: Bool) {
        self.id = id
        self.roots = roots
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.items = items
        self.issues = issues
        self.summary = ScanSummary(items: items, issues: issues)
        self.wasCancelled = wasCancelled
        self.hitItemLimit = hitItemLimit
    }
}

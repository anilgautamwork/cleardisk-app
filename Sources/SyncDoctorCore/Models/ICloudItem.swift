import Foundation

// MARK: - Supporting enums

public enum ItemKind: String, Codable, Sendable, Hashable {
    case file
    case directory
    case symlink
    case other
}

/// Mirrors `URLUbiquitousItemDownloadingStatus` (public Foundation).
///
/// Apple semantics (NSURL.h):
///  * `current`       – "NSURLUbiquitousItemDownloadingStatusCurrent": a local copy
///                       exists and it is the most recent version known to iCloud.
///  * `downloaded`    – "NSURLUbiquitousItemDownloadingStatusDownloaded": a local
///                       copy exists but iCloud has a newer version not yet downloaded.
///  * `notDownloaded` – "NSURLUbiquitousItemDownloadingStatusNotDownloaded": no
///                       local data — the item is cloud-only (dataless placeholder).
///  * `unknown`       – macOS returned nothing (non-ubiquitous item, permission
///                       problem, or the key is not supported for this item).
public enum DownloadStatus: String, Codable, Sendable, Hashable {
    case current
    case downloaded
    case notDownloaded
    case unknown

    public init(_ status: URLUbiquitousItemDownloadingStatus?) {
        guard let status else { self = .unknown; return }
        switch status {
        case .current: self = .current
        case .downloaded: self = .downloaded
        case .notDownloaded: self = .notDownloaded
        default: self = .unknown
        }
    }

    /// Accepts either the typed value or its raw string (the `allValues`
    /// dictionary returns the underlying NSString).
    public init(rawResourceValue value: Any?) {
        if let typed = value as? URLUbiquitousItemDownloadingStatus {
            self.init(typed)
        } else if let raw = value as? String {
            self.init(URLUbiquitousItemDownloadingStatus(rawValue: raw))
        } else {
            self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .current: return "Downloaded (current)"
        case .downloaded: return "Downloaded (newer version in iCloud)"
        case .notDownloaded: return "Not downloaded (cloud-only)"
        case .unknown: return "Unknown"
        }
    }
}

/// Where the bytes of an item live, as far as we can tell.
public enum Locality: String, Codable, Sendable, Hashable {
    /// Local copy present (may also be in iCloud).
    case local
    /// Placeholder only; data lives in iCloud.
    case cloudOnly
    /// A download is in progress.
    case downloading
    /// Not an iCloud (ubiquitous) item at all.
    case notUbiquitous
    /// macOS did not give us enough to decide. Never guessed.
    case unknown

    public var displayName: String {
        switch self {
        case .local: return "Local + iCloud"
        case .cloudOnly: return "Cloud only"
        case .downloading: return "Downloading"
        case .notUbiquitous: return "Not in iCloud"
        case .unknown: return "Unknown"
        }
    }
}

/// A Codable/Sendable snapshot of an `NSError` returned by Foundation for an item.
public struct ItemError: Error, Codable, Sendable, Hashable, CustomStringConvertible {
    public let domain: String
    public let code: Int
    public let localizedDescription: String
    public let failureReason: String?
    public let recoverySuggestion: String?

    public init(_ error: Error) {
        let ns = error as NSError
        domain = ns.domain
        code = ns.code
        localizedDescription = ns.localizedDescription
        failureReason = ns.localizedFailureReason
        recoverySuggestion = ns.localizedRecoverySuggestion
    }

    public init(domain: String, code: Int, localizedDescription: String) {
        self.domain = domain
        self.code = code
        self.localizedDescription = localizedDescription
        self.failureReason = nil
        self.recoverySuggestion = nil
    }

    public var description: String {
        var s = "\(domain) \(code): \(localizedDescription)"
        if let failureReason { s += " — \(failureReason)" }
        return s
    }

    /// `true` for the usual "Operation not permitted" / "Permission denied"
    /// shapes macOS returns when TCC (Files & Folders / Full Disk Access) blocks us.
    public var looksLikePermissionDenied: Bool {
        if domain == NSCocoaErrorDomain && (code == NSFileReadNoPermissionError || code == NSFileWriteNoPermissionError) { return true }
        if domain == NSPOSIXErrorDomain && (code == Int(EACCES) || code == Int(EPERM)) { return true }
        return false
    }
}

// MARK: - ICloudItem

/// One file or folder inside iCloud Drive, as observed by public Foundation APIs.
///
/// Every optional is `nil` when macOS did not return a value. We never infer or
/// default these — the UI shows "Unknown" instead.
public struct ICloudItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }

    public let url: URL
    public let name: String
    public let path: String
    /// Path relative to the scan root (for compact display).
    public let relativePath: String
    public let kind: ItemKind
    public let isPackage: Bool
    public let isHidden: Bool
    public let isAlias: Bool

    /// Logical size the file claims to have (`totalFileSizeKey`, falling back to
    /// `fileSizeKey`). For a cloud-only file this is the size in iCloud.
    public let logicalSize: Int64?
    /// Bytes actually allocated on the local disk (`totalFileAllocatedSizeKey`).
    /// Cloud-only files report 0 (or a tiny placeholder size).
    public let allocatedSize: Int64?

    public let modificationDate: Date?
    public let creationDate: Date?
    public let lastAccessDate: Date?
    public let addedToDirectoryDate: Date?

    // iCloud / ubiquity metadata ------------------------------------------------
    public let isUbiquitous: Bool?
    public let downloadStatus: DownloadStatus
    public let isDownloading: Bool?
    public let downloadRequested: Bool?
    public let downloadError: ItemError?
    public let isUploaded: Bool?
    public let isUploading: Bool?
    public let uploadError: ItemError?
    /// Percent keys were removed from URL resource values in macOS 10.9 — see
    /// `ICloudMetadataReader`. Expect `nil`; kept so the UI can show "Unknown".
    public let percentDownloaded: Double?
    public let percentUploaded: Double?
    public let hasUnresolvedConflicts: Bool?
    public let isExcludedFromSync: Bool?
    public let isExcludedFromBackup: Bool?
    public let isShared: Bool?
    public let containerDisplayName: String?

    /// From `lstat()` `st_flags & SF_DATALESS`. This is the kernel's view of
    /// "placeholder without data" and is independent of the ubiquity keys.
    public let isDataless: Bool?

    /// Set when reading the item's metadata itself failed (permissions etc.).
    public let accessError: ItemError?

    public init(
        url: URL, name: String, path: String, relativePath: String, kind: ItemKind,
        isPackage: Bool, isHidden: Bool, isAlias: Bool,
        logicalSize: Int64?, allocatedSize: Int64?,
        modificationDate: Date?, creationDate: Date?, lastAccessDate: Date?, addedToDirectoryDate: Date?,
        isUbiquitous: Bool?, downloadStatus: DownloadStatus, isDownloading: Bool?, downloadRequested: Bool?,
        downloadError: ItemError?, isUploaded: Bool?, isUploading: Bool?, uploadError: ItemError?,
        percentDownloaded: Double?, percentUploaded: Double?, hasUnresolvedConflicts: Bool?,
        isExcludedFromSync: Bool?, isExcludedFromBackup: Bool?, isShared: Bool?, containerDisplayName: String?,
        isDataless: Bool?, accessError: ItemError?
    ) {
        self.url = url; self.name = name; self.path = path; self.relativePath = relativePath; self.kind = kind
        self.isPackage = isPackage; self.isHidden = isHidden; self.isAlias = isAlias
        self.logicalSize = logicalSize; self.allocatedSize = allocatedSize
        self.modificationDate = modificationDate; self.creationDate = creationDate
        self.lastAccessDate = lastAccessDate; self.addedToDirectoryDate = addedToDirectoryDate
        self.isUbiquitous = isUbiquitous; self.downloadStatus = downloadStatus; self.isDownloading = isDownloading
        self.downloadRequested = downloadRequested; self.downloadError = downloadError
        self.isUploaded = isUploaded; self.isUploading = isUploading; self.uploadError = uploadError
        self.percentDownloaded = percentDownloaded; self.percentUploaded = percentUploaded
        self.hasUnresolvedConflicts = hasUnresolvedConflicts; self.isExcludedFromSync = isExcludedFromSync
        self.isExcludedFromBackup = isExcludedFromBackup; self.isShared = isShared
        self.containerDisplayName = containerDisplayName; self.isDataless = isDataless; self.accessError = accessError
    }

    // MARK: Derived (never guessed beyond what the raw values say)

    public var isDirectory: Bool { kind == .directory }

    /// Tri-state "is downloaded" derived strictly from `downloadStatus`.
    public var isDownloaded: Bool? {
        switch downloadStatus {
        case .current, .downloaded: return true
        case .notDownloaded: return false
        case .unknown: return nil
        }
    }

    public var locality: Locality {
        if isUbiquitous == false { return .notUbiquitous }
        if isDownloading == true { return .downloading }
        switch downloadStatus {
        case .current, .downloaded: return .local
        case .notDownloaded: return .cloudOnly
        case .unknown:
            // Fall back to the kernel flag only — it is authoritative, not a guess.
            if let isDataless { return isDataless ? .cloudOnly : .local }
            return .unknown
        }
    }

    /// "Waiting to upload": ubiquitous, not uploaded, not currently uploading, no error.
    public var isWaitingToUpload: Bool {
        isUbiquitous == true && isUploaded == false && isUploading == false && uploadError == nil
    }

    public var hasAnyError: Bool { uploadError != nil || downloadError != nil || accessError != nil }

    /// Healthy = ubiquitous, uploaded (or a folder), no errors, no conflicts.
    /// Cloud-only files are considered healthy (that's a valid state).
    public var isHealthy: Bool {
        guard isUbiquitous == true, !hasAnyError, hasUnresolvedConflicts == false else { return false }
        if kind == .directory { return isUploaded == true }
        return isUploaded == true && isUploading == false && isDownloading == false
    }

    /// Bytes we believe are consuming local disk. Prefers the allocated size.
    public var estimatedLocalBytes: Int64 {
        if let allocatedSize { return allocatedSize }
        // Missing allocated bytes remain unmeasured; logical size is not disk usage.
        return 0
    }

    /// Bytes we believe are cloud-only (not on local disk).
    public var estimatedCloudOnlyBytes: Int64 {
        guard locality == .cloudOnly, let logicalSize else { return 0 }
        return max(0, logicalSize - (allocatedSize ?? 0))
    }
}

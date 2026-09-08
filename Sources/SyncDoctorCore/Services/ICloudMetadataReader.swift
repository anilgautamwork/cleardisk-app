import Foundation

/// Reads everything public Foundation exposes about one URL and turns it into
/// an `ICloudItem`. Shared by the scanner and the Raw Inspector.
///
/// ## API notes (current macOS SDK)
///
/// All of these are `URLResourceKey` constants declared in `NSURL.h`:
///
/// | Requested key                                   | Status in current SDK                              |
/// |-------------------------------------------------|----------------------------------------------------|
/// | `isUbiquitousItemKey`                           | available                                          |
/// | `ubiquitousItemDownloadingStatusKey`            | available (macOS 10.9+) — replaces `IsDownloaded`  |
/// | `ubiquitousItemIsDownloadingKey`                | available                                          |
/// | `ubiquitousItemDownloadingErrorKey`             | available                                          |
/// | `ubiquitousItemIsUploadedKey`                   | available                                          |
/// | `ubiquitousItemIsUploadingKey`                  | available                                          |
/// | `ubiquitousItemUploadingErrorKey`               | available                                          |
/// | `ubiquitousItemHasUnresolvedConflictsKey`       | available                                          |
/// | `ubiquitousItemDownloadRequestedKey`            | available (10.10+)                                 |
/// | `ubiquitousItemContainerDisplayNameKey`         | available (10.10+)                                 |
/// | `ubiquitousItemIsExcludedFromSyncKey`           | available (11.3+)                                  |
/// | `ubiquitousItemIsSharedKey` + shared-item keys  | available (10.13+)                                 |
/// | `NSURLUbiquitousItemIsDownloadedKey`            | DEPRECATED in 10.9 → use downloading status        |
/// | `NSURLUbiquitousItemPercentDownloadedKey`       | DEPRECATED in 10.9 → only via `NSMetadataQuery`    |
/// | `NSURLUbiquitousItemPercentUploadedKey`         | DEPRECATED in 10.9 → only via `NSMetadataQuery`    |
///
/// The deprecated keys are still *requested* by raw string (so we don't take a
/// compile-time dependency on a deprecated symbol) and whatever comes back is
/// shown verbatim in the Raw Inspector. In practice they return nothing, and
/// `NSMetadataQuery`'s ubiquitous scopes require the iCloud container
/// entitlement, so **percent downloaded/uploaded is not available** to a
/// direct-download app for arbitrary iCloud Drive files. See
/// `UbiquityMetadataQueryProbe` for the experiment that verifies this.
public enum ICloudMetadataReader {

    // MARK: Keys

    /// Deprecated keys requested by raw string. See table above.
    public static let legacyIsDownloadedKey = URLResourceKey(rawValue: "NSURLUbiquitousItemIsDownloadedKey")
    public static let legacyPercentDownloadedKey = URLResourceKey(rawValue: "NSURLUbiquitousItemPercentDownloadedKey")
    public static let legacyPercentUploadedKey = URLResourceKey(rawValue: "NSURLUbiquitousItemPercentUploadedKey")

    /// Shared-item keys (10.13+). Requested by raw string so the reader keeps
    /// compiling even if a future SDK renames the Swift constants.
    public static let sharedCurrentUserRoleKey = URLResourceKey(rawValue: "NSURLUbiquitousSharedItemCurrentUserRoleKey")
    public static let sharedCurrentUserPermissionsKey = URLResourceKey(rawValue: "NSURLUbiquitousSharedItemCurrentUserPermissionsKey")
    public static let sharedOwnerNameComponentsKey = URLResourceKey(rawValue: "NSURLUbiquitousSharedItemOwnerNameComponentsKey")
    public static let sharedMostRecentEditorNameComponentsKey = URLResourceKey(rawValue: "NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey")

    public static let fileSystemKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
        .isAliasFileKey, .isHiddenKey,
        .fileSizeKey, .totalFileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
        .contentModificationDateKey, .creationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey,
        .isExcludedFromBackupKey, .contentTypeKey, .fileResourceTypeKey,
    ]

    public static let ubiquityKeys: [URLResourceKey] = [
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemDownloadRequestedKey,
        .ubiquitousItemDownloadingErrorKey,
        .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey,
        .ubiquitousItemUploadingErrorKey,
        .ubiquitousItemHasUnresolvedConflictsKey,
        .ubiquitousItemContainerDisplayNameKey,
        .ubiquitousItemIsExcludedFromSyncKey,
        .ubiquitousItemIsSharedKey,
        sharedCurrentUserRoleKey,
        sharedCurrentUserPermissionsKey,
        sharedOwnerNameComponentsKey,
        sharedMostRecentEditorNameComponentsKey,
        legacyIsDownloadedKey,
        legacyPercentDownloadedKey,
        legacyPercentUploadedKey,
    ]

    public static let allKeys: Set<URLResourceKey> = Set(fileSystemKeys + ubiquityKeys)

    // MARK: Reading

    /// Build an `ICloudItem` for `url`. Never throws: failures are recorded in
    /// `accessError` so the scan keeps going and the UI can show the problem.
    public static func item(at url: URL, relativeTo root: URL?, fresh: Bool = true) -> ICloudItem {
        if fresh { (url as NSURL).removeAllCachedResourceValues() }
        var values: [URLResourceKey: Any] = [:]
        var accessError: ItemError?

        // One batched call first (fast path). `resourceValues(forKeys:)` may be
        // cached on the URL object by the enumerator — that's fine, the
        // enumerator prefetches exactly these keys.
        do {
            values = try url.resourceValues(forKeys: allKeys).allValues
        } catch {
            accessError = ItemError(error)
            // Retry just the file-system keys so we at least get kind/size.
            if let fs = try? url.resourceValues(forKeys: Set(fileSystemKeys)).allValues {
                values = fs
            }
        }

        let posix = POSIXFileInfo.lstat(path: url.path)
        let posixInfo = try? posix.get()
        if accessError == nil, case .failure(let e) = posix { accessError = e }

        return build(url: url, values: values, posix: posixInfo, root: root, accessError: accessError)
    }

    /// Same as `item(at:)` but reading each key separately, so a single
    /// unsupported key cannot hide the others. Slower; used by the Raw Inspector.
    public static func rawValues(at url: URL) -> (values: [URLResourceKey: Any], errors: [URLResourceKey: ItemError]) {
        var values: [URLResourceKey: Any] = [:]
        var errors: [URLResourceKey: ItemError] = [:]
        // Ask for a fresh read, not a cached one.
        (url as NSURL).removeAllCachedResourceValues()
        for key in fileSystemKeys + ubiquityKeys {
            do {
                let v = try url.resourceValues(forKeys: [key]).allValues
                if let value = v[key] { values[key] = value }
            } catch {
                errors[key] = ItemError(error)
            }
        }
        return (values, errors)
    }

    // MARK: Building

    static func build(url: URL, values: [URLResourceKey: Any], posix: POSIXFileInfo?, root: URL?, accessError: ItemError?) -> ICloudItem {
        func bool(_ key: URLResourceKey) -> Bool? { (values[key] as? NSNumber)?.boolValue ?? (values[key] as? Bool) }
        func int64(_ key: URLResourceKey) -> Int64? { (values[key] as? NSNumber)?.int64Value }
        func double(_ key: URLResourceKey) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        func date(_ key: URLResourceKey) -> Date? { values[key] as? Date }
        func string(_ key: URLResourceKey) -> String? { values[key] as? String }
        func error(_ key: URLResourceKey) -> ItemError? { (values[key] as? NSError).map(ItemError.init) }

        let kind: ItemKind
        if let posix {
            switch posix.mode & S_IFMT {
            case S_IFDIR: kind = .directory
            case S_IFREG: kind = .file
            case S_IFLNK: kind = .symlink
            default: kind = .other
            }
        } else { kind = .other }


        let path = url.path
        let relative: String
        if let root, path.hasPrefix(root.path) {
            relative = String(path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            relative = path
        }

        // Logical size: prefer total (includes resource fork), then plain, then stat.
        var logical = int64(.totalFileSizeKey) ?? int64(.fileSizeKey)
        if logical == nil, kind == .file, let posix { logical = posix.size }
        var allocated = int64(.totalFileAllocatedSizeKey) ?? int64(.fileAllocatedSizeKey)
        if allocated == nil, kind == .file, let posix { allocated = posix.blocks * 512 }

        return ICloudItem(
            url: url,
            name: string(.nameKey) ?? url.lastPathComponent,
            path: path,
            relativePath: relative,
            kind: kind,
            isPackage: bool(.isPackageKey) ?? false,
            isHidden: bool(.isHiddenKey) ?? url.lastPathComponent.hasPrefix("."),
            isAlias: bool(.isAliasFileKey) ?? false,
            logicalSize: kind == .directory ? nil : logical,
            allocatedSize: kind == .directory ? nil : allocated,
            modificationDate: date(.contentModificationDateKey) ?? posix?.modified,
            creationDate: date(.creationDateKey) ?? posix?.created,
            lastAccessDate: date(.contentAccessDateKey),
            addedToDirectoryDate: date(.addedToDirectoryDateKey),
            isUbiquitous: bool(.isUbiquitousItemKey),
            downloadStatus: DownloadStatus(rawResourceValue: values[.ubiquitousItemDownloadingStatusKey]),
            isDownloading: bool(.ubiquitousItemIsDownloadingKey),
            downloadRequested: bool(.ubiquitousItemDownloadRequestedKey),
            downloadError: error(.ubiquitousItemDownloadingErrorKey),
            isUploaded: bool(.ubiquitousItemIsUploadedKey),
            isUploading: bool(.ubiquitousItemIsUploadingKey),
            uploadError: error(.ubiquitousItemUploadingErrorKey),
            percentDownloaded: double(legacyPercentDownloadedKey),
            percentUploaded: double(legacyPercentUploadedKey),
            hasUnresolvedConflicts: bool(.ubiquitousItemHasUnresolvedConflictsKey),
            isExcludedFromSync: bool(.ubiquitousItemIsExcludedFromSyncKey),
            isExcludedFromBackup: bool(.isExcludedFromBackupKey),
            isShared: bool(.ubiquitousItemIsSharedKey),
            containerDisplayName: string(.ubiquitousItemContainerDisplayNameKey),
            isDataless: posix?.isDataless,
            accessError: accessError
        )
    }
}

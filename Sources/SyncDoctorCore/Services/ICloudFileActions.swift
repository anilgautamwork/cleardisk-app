import Foundation

public enum ICloudActionError: Error, LocalizedError {
    case refused(String)
    public var errorDescription: String? { if case .refused(let reason) = self { return reason }; return nil }
}

public enum ICloudFileActions {
    public static let keepDownloadedIsSupported = false
    static func validateScope(_ url: URL, root: URL = ICloudDriveLocator.cloudDocsURL()) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, resolved == url.standardizedFileURL,
              resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw ICloudActionError.refused("Only original items inside iCloud Drive are supported. Symlinks and the Drive root are refused.")
        }
    }
    public static func evictionRefusal(for item: ICloudItem) -> String? {
        guard item.kind == .file, !item.isAlias, !item.isPackage else { return "Select a regular file; folders, packages, aliases and links cannot be evicted here." }
        guard item.isUbiquitous == true, item.isUploaded == true else { return "macOS has not confirmed this file is fully uploaded." }
        guard item.downloadStatus == .current, item.isDataless == false else { return "A current local download is required." }
        guard item.isUploading == false, item.isDownloading == false, item.hasUnresolvedConflicts == false, !item.hasAnyError,
              item.isExcludedFromSync != true else { return "Transfer, conflict or error metadata is unsafe or unknown." }
        return nil
    }
    public static func requestDownload(of url: URL) throws {
        try validateScope(url)
        let item = ICloudMetadataReader.item(at: url, relativeTo: nil)
        guard item.isUbiquitous == true, item.kind == .file || item.kind == .directory, !item.isAlias, item.accessError == nil else {
            throw ICloudActionError.refused("Cannot confirm this is an accessible iCloud file or folder.")
        }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    public static func evictLocalCopy(of url: URL) throws {
        try DatalessMaterializationPolicy.withoutMaterialization {
            try validateScope(url)
            let item = ICloudMetadataReader.item(at: url, relativeTo: nil)
            if let reason = evictionRefusal(for: item) { throw ICloudActionError.refused(reason) }
            try FileManager.default.evictUbiquitousItem(at: url)
        }
    }
}

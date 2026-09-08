import Foundation

/// Buckets on the Sync Problems screen.
public enum ProblemCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case uploadFailed
    case downloadFailed
    case conflicts
    case waitingToUpload
    case uploadingLong
    case notDownloaded
    case oversized
    case permission

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uploadFailed: return "Upload failed"
        case .downloadFailed: return "Download failed"
        case .conflicts: return "Conflicts"
        case .waitingToUpload: return "Waiting to upload"
        case .uploadingLong: return "Uploading for a long time"
        case .notDownloaded: return "Not downloaded"
        case .oversized: return "Potentially oversized / problematic files"
        case .permission: return "Permission / access issues"
        }
    }

    /// error > warning > info — drives the status colour.
    public var severity: Severity {
        switch self {
        case .uploadFailed, .downloadFailed, .conflicts, .permission: return .error
        case .waitingToUpload, .uploadingLong, .oversized: return .warning
        case .notDownloaded: return .info
        }
    }

    public var recommendedAction: String {
        switch self {
        case .uploadFailed: return "Check the reported error and compare a later scan; a verified archive can preserve a separate local copy."
        case .downloadFailed: return "Retry the download. If it keeps failing, check network and iCloud storage."
        case .conflicts: return "Open the file in its app or Finder to resolve the conflict. ClearDisk never picks a version for you."
        case .waitingToUpload: return "Usually resolves on its own. If it stays here across scans, check network and iCloud storage."
        case .uploadingLong: return "Large files take time. Compare later observations and check Apple’s service status."
        case .notDownloaded: return "Cloud-only is a normal storage state. Use Download Now if you need it locally."
        case .oversized: return "Large size alone does not indicate a sync fault."
        case .permission: return "Grant ClearDisk access in System Settings → Privacy & Security → Files and Folders."
        }
    }
}

public enum Severity: String, Sendable, Codable {
    case healthy, info, warning, error
}

public struct ProblemEntry: Identifiable, Sendable, Hashable {
    public var id: String { "\(category.rawValue):\(item.path)" }
    public let category: ProblemCategory
    public let item: ICloudItem
    public let detail: String
}

/// Turns a scan into grouped problems. Pure function, unit-tested.
///
/// "Uploading for a long time" needs history (multiple scans) to be honest;
/// the classifier accepts an optional `stuckPaths` set produced by the history
/// store so a single scan never claims something is "stuck".
public struct ProblemClassifier: Sendable {
    /// Above this logical size a file is flagged as potentially problematic.
    public var oversizedThreshold: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB

    public init() {}

    public func classify(items: [ICloudItem], issues: [ScanIssue], stuckPaths: Set<String> = []) -> [ProblemCategory: [ProblemEntry]] {
        var out: [ProblemCategory: [ProblemEntry]] = [:]
        func add(_ c: ProblemCategory, _ item: ICloudItem, _ detail: String) {
            out[c, default: []].append(ProblemEntry(category: c, item: item, detail: detail))
        }

        for item in items {
            if item.name == ".DS_Store" || item.name.hasPrefix("._") { continue }
            if let e = item.uploadError { add(.uploadFailed, item, e.description) }
            if let e = item.downloadError { add(.downloadFailed, item, e.description) }
            if item.hasUnresolvedConflicts == true { add(.conflicts, item, "macOS reports unresolved conflicts") }
            if let e = item.accessError { add(.permission, item, e.description) }
            if item.kind != .directory {
                if stuckPaths.contains(item.path), item.isWaitingToUpload || item.isUploading == true {
                    add(.uploadingLong, item, "Upload state unchanged across scans")
                } else if item.isWaitingToUpload {
                    add(.waitingToUpload, item, "isUploaded = false")
                } else if item.isUploading == true {
                    add(.waitingToUpload, item, "isUploading = true")
                }
                if item.downloadStatus == .notDownloaded { add(.notDownloaded, item, "Cloud-only") }
                if let size = item.logicalSize, size >= oversizedThreshold, item.isWaitingToUpload {
                    add(.oversized, item, "Logical size \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                }
            }
        }
        for issue in issues where issue.kind == .permissionDenied || issue.kind == .rootUnreadable {
            let placeholder = ICloudMetadataReader.build(url: URL(fileURLWithPath: issue.path), values: [:], posix: nil, root: nil, accessError: issue.error)
            add(.permission, placeholder, issue.error?.description ?? issue.kind.rawValue)
        }
        for key in out.keys {
            out[key]?.sort { ($0.item.logicalSize ?? 0) > ($1.item.logicalSize ?? 0) }
        }
        return out
    }

    /// Overall severity for the status card. Cloud-only files never count as a problem.
    public static func overallSeverity(summary: ScanSummary) -> Severity {
        if summary.problemCount > 0 { return .error }
        if summary.waitingToUpload > 0 || summary.uploading > 0 { return .warning }
        if summary.unknownUbiquity > 0 || summary.unknownSyncState > 0 || summary.totalItems == 0 { return .info }
        return .healthy
    }
}

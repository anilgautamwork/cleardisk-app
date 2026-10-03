import Foundation
import Darwin

/// A deliberately narrow inventory of observed MobileAsset families, not all
/// System Data and not a promise that these bytes can be reclaimed.
public struct IntelligenceStorageReport: Sendable {
    public struct Location: Identifiable, Sendable {
        public enum Status: String, Sendable { case measured, partial, missing, unavailable }
        public let path: String
        public let title: String
        public let explanation: String
        public let bytes: Int64
        public let files: Int
        public let unreadable: Int
        public let status: Status
        public var id: String { path }
    }
    public let locations: [Location]
    public var measuredBytes: Int64 { locations.reduce(0) { $0 + $1.bytes } }
    public var incomplete: Bool { locations.contains { $0.status == .partial || $0.status == .unavailable } }
}

public enum AppleIntelligenceStorage {
    public static let defaultRoots = [
        "/System/Library/AssetsV2",
        "/System/Library/AssetsV2/PreinstalledAssetsV2/InstallWithOs",
        "/System/Library/AssetsV2/PreinstalledAssetsV2/RequiredByOs",
    ]
    static let families: [(name: String, title: String, explanation: String)] = [
        ("com_apple_MobileAsset_UAF_FM_GenerativeModels", "Generative models",
         "Downloaded foundation-model assets used by Apple Intelligence features."),
        ("com_apple_MobileAsset_UAF_FM_Visual", "Visual model assets",
         "Apple's visual foundation-model assets. Availability varies by macOS version."),
        ("com_apple_MobileAsset_UAF_FM_Overrides", "Model support assets",
         "Configuration and supporting assets for Apple's foundation models."),
    ]

    public static func scan(roots: [String] = defaultRoots,
                            progress: @Sendable (String) -> Void = { _ in }) throws -> IntelligenceStorageReport {
        let fm = FileManager.default
        var locations: [IntelligenceStorageReport.Location] = []
        var seenPaths = Set<String>()
        // Hard links appearing in multiple families contribute allocated bytes once.
        var seenFiles = Set<String>()
        for root in roots {
            for family in families {
                try Task.checkCancellation()
                let url = URL(fileURLWithPath: root).appendingPathComponent(family.name).standardizedFileURL
                guard seenPaths.insert(url.path).inserted else { continue }
                progress(family.title)
                var info = stat()
                let result = lstat(url.path, &info)
                let failure = errno
                var bytes: Int64 = 0, files = 0, unreadable = 0
                var status: IntelligenceStorageReport.Location.Status = .measured
                if result != 0 {
                    status = failure == ENOENT ? .missing : .unavailable
                } else if (info.st_mode & S_IFMT) != S_IFDIR || url.resolvingSymlinksInPath().path != url.path {
                    // No traversal through aliases into unrelated locations.
                    status = .unavailable
                } else {
                    let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [],
                                                   errorHandler: { _, _ in unreadable += 1; return true })
                    if let enumerator {
                        for case let child as URL in enumerator {
                            try Task.checkCancellation()
                            var entry = stat()
                            guard lstat(child.path, &entry) == 0 else { unreadable += 1; continue }
                            let type = entry.st_mode & S_IFMT
                            if type == S_IFLNK { enumerator.skipDescendants(); continue }
                            guard type == S_IFREG else { continue }
                            files += 1
                            let identity = "\(entry.st_dev):\(entry.st_ino)"
                            if seenFiles.insert(identity).inserted { bytes += Int64(entry.st_blocks) * 512 }
                        }
                        if unreadable > 0 { status = .partial }
                    } else { status = .unavailable }
                }
                locations.append(.init(path: url.path, title: family.title, explanation: family.explanation,
                                       bytes: bytes, files: files, unreadable: unreadable, status: status))
            }
        }
        return .init(locations: locations)
    }
}

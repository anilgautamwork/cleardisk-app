import Darwin
import Foundation

/// Slow-but-obviously-correct scanner: FileManager enumeration + lstat per
/// entry. Exists as the correctness oracle for tests and the speed baseline
/// the bulk engine must beat by 5x (plan gate M1).
public enum ReferenceScanner {

    public static func scan(path: String) -> ScanStats {
        var stats = ScanStats()
        var seenHardLinks = Set<UInt64>()

        var rootStat = stat()
        guard lstat(path, &rootStat) == 0 else {
            stats.skippedCount += 1
            return stats
        }
        if (rootStat.st_mode & S_IFMT) != S_IFDIR {
            stats.fileCount = 1
            stats.totalBytes = Int64(rootStat.st_blocks) * 512
            return stats
        }
        stats.directoryCount += 1

        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [],
            options: [.producesRelativePathURLs],
            errorHandler: { _, _ in true }
        )
        guard let enumerator else { return stats }

        for case let url as URL in enumerator {
            var st = stat()
            guard lstat(url.path, &st) == 0 else {
                stats.skippedCount += 1
                continue
            }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFDIR {
                stats.directoryCount += 1
                continue
            }
            var bytes = Int64(st.st_blocks) * 512
            if mode == S_IFREG && st.st_nlink > 1 {
                if seenHardLinks.contains(st.st_ino) {
                    bytes = 0
                } else {
                    seenHardLinks.insert(st.st_ino)
                }
            }
            stats.fileCount += 1
            stats.totalBytes += bytes
        }
        return stats
    }
}

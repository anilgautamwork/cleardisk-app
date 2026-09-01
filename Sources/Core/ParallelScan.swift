import Darwin
import Foundation

/// Parallel front-end over the bulk engine: a shared work queue of directories
/// serviced by one worker per core (x2, they block in syscalls). Every
/// discovered subdirectory becomes a work item, so granularity is fine enough
/// that one giant subtree cannot serialize the scan.
///
/// Hardlinks are deduplicated exactly across workers by merging each worker's
/// fileID->size map at the end. Subtree node sizes keep each worker's local
/// view of a hardlink; only the totals and root are globally corrected —
/// matching how DaisyDisk-class tools display hardlinks.
// ponytail: one directory is one work item, so a single directory holding
// hundreds of thousands of files (Chrome's Cache_Data) enumerates serially —
// getattrlistbulk iteration state is per-fd, so intra-directory parallelism
// isn't possible with this API. Measured ~2x du, ~4x FileManager; good enough.
public enum ParallelScan {

    public struct Result: Sendable {
        public let root: FileNode
        public let stats: ScanStats
    }

    public static func scan(path: String,
                            skipPrefixes: [String]? = nil,
                            onProgress: (@Sendable (Int, Int64) -> Void)? = nil) throws -> Result {
        var st = stat()
        guard lstat(path, &st) == 0 else { throw ScanError.cannotOpen(path, errno) }
        let last = (path as NSString).lastPathComponent
        let name = last.isEmpty ? path : last

        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            let node = FileNode(name: name, isDirectory: false,
                                size: Int64(st.st_blocks) * 512,
                                modTime: Int64(st.st_mtimespec.tv_sec))
            var stats = ScanStats()
            stats.fileCount = 1
            stats.totalBytes = node.size
            return Result(root: node, stats: stats)
        }

        let root = FileNode(name: name, isDirectory: true, size: 0,
                            modTime: Int64(st.st_mtimespec.tv_sec))
        let engine = Engine(skips: skipPrefixes ?? BulkScanner.defaultRootSkips(for: path),
                            onProgress: onProgress)
        let stats = engine.run(root: root, rootPath: path == "/" ? "" : path)
        return Result(root: root, stats: stats)
    }

    // MARK: - engine

    /// Thread-safety model: the queue, counters and merge results are guarded
    /// by `cond`. A FileNode's `children` is written exactly once, by the
    /// worker that popped that directory; parents never touch it again until
    /// the final (single-threaded) size fix-up.
    private final class Engine: @unchecked Sendable {
        private let cond = NSCondition()
        private var queue: [(node: FileNode, path: String)] = []
        private var pendingCount = 0
        private var mergedStats = ScanStats()
        private var mergedLinked: [UInt64: Int64] = [:]
        private var duplicateBytes: Int64 = 0
        private var progressFiles = 0
        private var progressBytes: Int64 = 0

        private let skips: [String]
        private let onProgress: (@Sendable (Int, Int64) -> Void)?

        init(skips: [String], onProgress: (@Sendable (Int, Int64) -> Void)?) {
            self.skips = skips
            self.onProgress = onProgress
        }

        func run(root: FileNode, rootPath: String) -> ScanStats {
            queue.append((root, rootPath))
            pendingCount = 1
            let workers = max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
            DispatchQueue.concurrentPerform(iterations: workers) { _ in
                self.workerLoop()
            }
            mergedStats.totalBytes -= duplicateBytes
            fixDirectorySizes(root)
            root.size -= duplicateBytes
            return mergedStats
        }

        private func pop() -> (node: FileNode, path: String)? {
            cond.lock()
            while queue.isEmpty && pendingCount > 0 { cond.wait() }
            guard !queue.isEmpty else {
                cond.unlock()
                return nil
            }
            let item = queue.removeLast()
            cond.unlock()
            return item
        }

        private func push(_ items: [(node: FileNode, path: String)]) {
            guard !items.isEmpty else { return }
            cond.lock()
            queue.append(contentsOf: items)
            pendingCount += items.count
            cond.broadcast()
            cond.unlock()
        }

        private func finishItem() {
            cond.lock()
            pendingCount -= 1
            if pendingCount == 0 { cond.broadcast() }
            cond.unlock()
        }

        private func workerLoop() {
            let bufSize = 256 * 1024
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
            defer { buf.deallocate() }

            var local = ScanStats()
            var localLinked: [UInt64: Int64] = [:]
            var sinceProgress = 0
            var lastReportedFiles = 0
            var lastReportedBytes: Int64 = 0

            while let item = pop() {
                let fd = open(item.path.isEmpty ? "/" : item.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard fd >= 0 else {
                    local.skippedCount += 1
                    finishItem()
                    continue
                }
                local.directoryCount += 1

                var children: [FileNode] = []
                var discovered: [(node: FileNode, path: String)] = []
                let rc = BulkScanner.enumerate(dirFD: fd, buffer: buf, bufferSize: bufSize) { entry in
                    if entry.errorCode != 0 || entry.name.isEmpty {
                        local.skippedCount += 1
                        return
                    }
                    if entry.objType == BulkScanner.vDIR {
                        let childPath = item.path + "/" + entry.name
                        if skips.contains(where: { childPath == $0 || childPath.hasPrefix($0 + "/") }) {
                            return
                        }
                        let node = FileNode(name: entry.name, isDirectory: true, size: 0, modTime: entry.modTime)
                        children.append(node)
                        discovered.append((node, childPath))
                    } else {
                        var alloc = entry.allocSize
                        if entry.objType == BulkScanner.vREG && entry.linkCount > 1 && entry.fileID != 0 {
                            if localLinked[entry.fileID] != nil {
                                alloc = 0
                            } else {
                                localLinked[entry.fileID] = alloc
                            }
                        }
                        local.fileCount += 1
                        local.totalBytes += alloc
                        children.append(FileNode(name: entry.name, isDirectory: false, size: alloc, modTime: entry.modTime))
                        sinceProgress += 1
                    }
                }
                close(fd)
                if rc != 0 { local.skippedCount += 1 }
                item.node.children = children
                push(discovered)
                finishItem()

                if sinceProgress >= 16384, let onProgress {
                    sinceProgress = 0
                    cond.lock()
                    progressFiles += local.fileCount - lastReportedFiles
                    progressBytes += local.totalBytes - lastReportedBytes
                    let files = progressFiles
                    let bytes = progressBytes
                    cond.unlock()
                    lastReportedFiles = local.fileCount
                    lastReportedBytes = local.totalBytes
                    onProgress(files, bytes)
                }
            }

            // Merge this worker's results.
            cond.lock()
            mergedStats.fileCount += local.fileCount
            mergedStats.directoryCount += local.directoryCount
            mergedStats.skippedCount += local.skippedCount
            mergedStats.totalBytes += local.totalBytes
            for (id, size) in localLinked {
                if mergedLinked[id] != nil {
                    duplicateBytes += size
                } else {
                    mergedLinked[id] = size
                }
            }
            cond.unlock()
        }

        /// Recompute directory sizes bottom-up once the tree is complete —
        /// during the scan, directory nodes never accumulate sizes.
        @discardableResult
        private func fixDirectorySizes(_ node: FileNode) -> Int64 {
            guard node.isDirectory, let children = node.children else { return node.size }
            node.size = children.reduce(0) { $0 + fixDirectorySizes($1) }
            return node.size
        }
    }
}

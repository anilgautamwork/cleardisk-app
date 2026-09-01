import Darwin
import Foundation

/// One decoded getattrlistbulk record.
struct RawEntry {
    var name = ""
    var objType: UInt32 = 0
    var modTime: Int64 = 0
    var fileID: UInt64 = 0
    var linkCount: UInt32 = 1
    var allocSize: Int64 = 0
    var errorCode: UInt32 = 0
}

/// Fast disk scanner built on getattrlistbulk(2) — the syscall DaisyDisk-class
/// tools use. Reads many directory entries per syscall with only the
/// attributes we need, so it avoids a stat() per file.
///
/// Correctness rules it enforces:
/// - allocated size (ATTR_FILE_ALLOCSIZE), so sparse files (Docker.raw) and
///   compressed files match `du`, not their inflated logical length
/// - hardlinks counted once, by file id
/// - symlinks never followed (O_NOFOLLOW; the link itself is counted)
/// - when scanning "/", the /System/Volumes/* firmlink mounts are skipped so
///   user data is not counted twice
public final class BulkScanner {

    public struct Options: Sendable {
        /// Absolute path prefixes never descended into.
        public var skipPrefixes: [String] = []
        /// Called roughly every `progressInterval` entries with (files, bytes).
        public var onProgress: (@Sendable (Int, Int64) -> Void)?
        public var progressInterval = 8192
        public init() {}
    }

    /// Mounts and pseudo-filesystems to skip when scanning the volume root.
    /// /System/Volumes hosts the firmlink targets (Data, VM, Preboot, ...);
    /// descending there would double-count everything reachable via /Users etc.
    public static func defaultRootSkips(for path: String) -> [String] {
        path == "/" ? ["/System/Volumes", "/Volumes", "/dev", "/Network", "/.vol"] : []
    }

    public private(set) var stats = ScanStats()
    /// fileID -> allocated size, for every multi-link file this scanner counted.
    /// ParallelScan merges these maps to undo cross-worker double counting.
    public private(set) var linkedSizes: [UInt64: Int64] = [:]

    private let options: Options
    private var sinceProgress = 0

    public init(options: Options = Options()) {
        self.options = options
    }

    public func scan(path: String) throws -> FileNode {
        var st = stat()
        guard lstat(path, &st) == 0 else { throw ScanError.cannotOpen(path, errno) }
        let last = (path as NSString).lastPathComponent
        let name = last.isEmpty ? path : last

        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            let node = FileNode(name: name, isDirectory: false,
                                size: Int64(st.st_blocks) * 512,
                                modTime: Int64(st.st_mtimespec.tv_sec))
            stats.fileCount += 1
            stats.totalBytes += node.size
            return node
        }

        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ScanError.cannotOpen(path, errno) }
        defer { close(fd) }

        stats.directoryCount += 1
        let root = FileNode(name: name, isDirectory: true, size: 0,
                            modTime: Int64(st.st_mtimespec.tv_sec))
        let children = scanChildren(dirFD: fd, dirPath: path == "/" ? "" : path)
        root.children = children
        root.size = children.reduce(0) { $0 + $1.size }
        return root
    }

    private func scanChildren(dirFD: Int32, dirPath: String) -> [FileNode] {
        var children: [FileNode] = []
        let bufSize = 256 * 1024
        let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { buf.deallocate() }

        let rc = BulkScanner.enumerate(dirFD: dirFD, buffer: buf, bufferSize: bufSize) { entry in
            if entry.errorCode != 0 || entry.name.isEmpty {
                stats.skippedCount += 1
                return
            }
            if entry.objType == BulkScanner.vDIR {
                let childPath = dirPath + "/" + entry.name
                if options.skipPrefixes.contains(where: { childPath == $0 || childPath.hasPrefix($0 + "/") }) {
                    return
                }
                let node = FileNode(name: entry.name, isDirectory: true, size: 0, modTime: entry.modTime)
                let childFD = openat(dirFD, entry.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                if childFD >= 0 {
                    stats.directoryCount += 1
                    let kids = scanChildren(dirFD: childFD, dirPath: childPath)
                    close(childFD)
                    node.children = kids
                    node.size = kids.reduce(0) { $0 + $1.size }
                } else {
                    stats.skippedCount += 1
                }
                children.append(node)
            } else {
                var alloc = entry.allocSize
                if entry.objType == BulkScanner.vREG && entry.linkCount > 1 && entry.fileID != 0 {
                    if linkedSizes[entry.fileID] != nil {
                        alloc = 0
                    } else {
                        linkedSizes[entry.fileID] = alloc
                    }
                }
                stats.fileCount += 1
                stats.totalBytes += alloc
                children.append(FileNode(name: entry.name, isDirectory: false, size: alloc, modTime: entry.modTime))

                sinceProgress += 1
                if sinceProgress >= options.progressInterval {
                    sinceProgress = 0
                    options.onProgress?(stats.fileCount, stats.totalBytes)
                }
            }
        }
        if rc != 0 { stats.skippedCount += 1 }
        return children
    }

    // MARK: - record decoding shared with ParallelScan

    // sys/attr.h values; Swift imports them with mixed signedness, so they are
    // restated here as UInt32.
    private enum Attr {
        static let cmnName: UInt32 = 0x0000_0001
        static let cmnObjType: UInt32 = 0x0000_0008
        static let cmnModTime: UInt32 = 0x0000_0400
        static let cmnFileID: UInt32 = 0x0200_0000
        static let cmnError: UInt32 = 0x2000_0000
        static let cmnReturnedAttrs: UInt32 = 0x8000_0000
        static let fileLinkCount: UInt32 = 0x0000_0001
        static let fileAllocSize: UInt32 = 0x0000_0004
    }

    static let vREG: UInt32 = 1 // VREG
    static let vDIR: UInt32 = 2 // VDIR

    /// Reads every entry of an open directory, decoding records into the
    /// caller's handler. Returns 0 on success, errno on read failure.
    /// The handler MUST NOT re-enter enumerate with the same buffer.
    static func enumerate(dirFD: Int32, buffer: UnsafeMutableRawPointer, bufferSize: Int,
                          _ handler: (RawEntry) -> Void) -> Int32 {
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(Attr.cmnReturnedAttrs | Attr.cmnName | Attr.cmnError
                                      | Attr.cmnObjType | Attr.cmnModTime | Attr.cmnFileID)
        list.fileattr = attrgroup_t(Attr.fileLinkCount | Attr.fileAllocSize)

        while true {
            let n = getattrlistbulk(dirFD, &list, buffer, bufferSize, 0)
            if n < 0 { return errno }
            if n == 0 { return 0 }
            var cursor = buffer
            for _ in 0..<n {
                let recLen = cursor.loadUnaligned(as: UInt32.self)
                handler(decode(record: cursor))
                cursor += Int(recLen)
            }
        }
    }

    /// Field order within a record is the canonical order from getattrlist(2):
    /// returned attrs, name, objtype, modtime, fileid, error, then file attrs.
    private static func decode(record: UnsafeMutableRawPointer) -> RawEntry {
        var f = record + MemoryLayout<UInt32>.size
        let returned = f.loadUnaligned(as: attribute_set_t.self)
        f += MemoryLayout<attribute_set_t>.size
        let common = UInt32(returned.commonattr)
        let fileBits = UInt32(returned.fileattr)

        var entry = RawEntry()
        if common & Attr.cmnName != 0 {
            let nameField = f
            let off = f.loadUnaligned(as: Int32.self)
            entry.name = String(cString: (nameField + Int(off)).assumingMemoryBound(to: CChar.self))
            f += MemoryLayout<attrreference_t>.size
        }
        if common & Attr.cmnObjType != 0 {
            entry.objType = f.loadUnaligned(as: UInt32.self)
            f += MemoryLayout<fsobj_type_t>.size
        }
        if common & Attr.cmnModTime != 0 {
            entry.modTime = Int64(f.loadUnaligned(as: timespec.self).tv_sec)
            f += MemoryLayout<timespec>.size
        }
        if common & Attr.cmnFileID != 0 {
            entry.fileID = f.loadUnaligned(as: UInt64.self)
            f += MemoryLayout<UInt64>.size
        }
        if common & Attr.cmnError != 0 {
            entry.errorCode = f.loadUnaligned(as: UInt32.self)
            f += MemoryLayout<UInt32>.size
        }
        if fileBits & Attr.fileLinkCount != 0 {
            entry.linkCount = f.loadUnaligned(as: UInt32.self)
            f += MemoryLayout<UInt32>.size
        }
        if fileBits & Attr.fileAllocSize != 0 {
            entry.allocSize = f.loadUnaligned(as: Int64.self)
            f += MemoryLayout<Int64>.size
        }
        return entry
    }
}

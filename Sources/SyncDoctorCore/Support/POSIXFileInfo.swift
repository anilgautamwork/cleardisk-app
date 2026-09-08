import Foundation
import Darwin

/// Low-level, read-only facts about a path obtained with `lstat(2)` and
/// `listxattr(2)`. Both are public POSIX/Darwin APIs and neither touches file
/// contents, so they never trigger an iCloud download.
public struct POSIXFileInfo: Sendable, Hashable, Codable {
    public let size: Int64
    public let blocks: Int64
    public let blockSize: Int32
    public let mode: UInt16
    public let flags: UInt32
    public let linkCount: UInt16
    public let inode: UInt64
    public let modified: Date
    public let changed: Date
    public let accessed: Date
    public let created: Date

    /// `st_flags & SF_DATALESS` — the kernel's "placeholder without data" bit.
    public var isDataless: Bool { flags & POSIXFileInfo.SF_DATALESS != 0 }

    /// Human-readable names of the `st_flags` bits that are set. Values from
    /// `<sys/stat.h>`.
    public var flagNames: [String] {
        let table: [(UInt32, String)] = [
            (0x0000_0001, "UF_NODUMP"),
            (0x0000_0002, "UF_IMMUTABLE"),
            (0x0000_0004, "UF_APPEND"),
            (0x0000_0008, "UF_OPAQUE"),
            (0x0000_0020, "UF_COMPRESSED"),
            (0x0000_0040, "UF_TRACKED"),
            (0x0000_0080, "UF_DATAVAULT"),
            (0x0000_8000, "UF_HIDDEN"),
            (0x0001_0000, "SF_ARCHIVED"),
            (0x0002_0000, "SF_IMMUTABLE"),
            (0x0004_0000, "SF_APPEND"),
            (0x0008_0000, "SF_RESTRICTED"),
            (0x0010_0000, "SF_NOUNLINK"),
            (0x0080_0000, "SF_FIRMLINK"),
            (POSIXFileInfo.SF_DATALESS, "SF_DATALESS"),
        ]
        var names = table.filter { flags & $0.0 != 0 }.map(\.1)
        let known = table.reduce(UInt32(0)) { $0 | $1.0 }
        let unknown = flags & ~known
        if unknown != 0 { names.append(String(format: "0x%08x", unknown)) }
        return names
    }

    /// `<sys/stat.h>`: `#define SF_DATALESS 0x40000000`
    public static let SF_DATALESS: UInt32 = 0x4000_0000

    public var modeString: String { String(format: "0%o", mode & 0o7777) }

    public static func lstat(path: String) -> Result<POSIXFileInfo, ItemError> {
        var st = stat()
        let rc = path.withCString { Darwin.lstat($0, &st) }
        guard rc == 0 else {
            let err = NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            return .failure(ItemError(err))
        }
        func date(_ ts: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1e9)
        }
        return .success(POSIXFileInfo(
            size: Int64(st.st_size),
            blocks: Int64(st.st_blocks),
            blockSize: st.st_blksize,
            mode: st.st_mode,
            flags: st.st_flags,
            linkCount: st.st_nlink,
            inode: st.st_ino,
            modified: date(st.st_mtimespec),
            changed: date(st.st_ctimespec),
            accessed: date(st.st_atimespec),
            created: date(st.st_birthtimespec)
        ))
    }

    /// Names (never values) of extended attributes. `XATTR_NOFOLLOW` so we
    /// describe the link itself. Values are intentionally not read — some
    /// xattrs (e.g. Finder comments) are user content.
    public static func xattrNames(path: String) -> Result<[String], ItemError> {
        let flags = Int32(XATTR_NOFOLLOW)
        let length = path.withCString { listxattr($0, nil, 0, flags) }
        if length < 0 {
            return .failure(ItemError(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)))
        }
        if length == 0 { return .success([]) }
        var buffer = [CChar](repeating: 0, count: length)
        let got = path.withCString { listxattr($0, &buffer, length, flags) }
        if got < 0 {
            return .failure(ItemError(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)))
        }
        // NUL-separated list.
        let bytes = buffer[0..<got].map { UInt8(bitPattern: $0) }
        let names = bytes.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        return .success(names)
    }
}

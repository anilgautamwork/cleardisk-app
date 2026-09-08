import Foundation
import Darwin

/// Controls whether the kernel is allowed to *materialize* (download) dataless
/// files when this process touches them.
///
/// Background: since macOS 12.3/13 iCloud Drive is backed by FileProvider.
/// Cloud-only files appear in the filesystem as *dataless* files
/// (`st_flags & SF_DATALESS`). Merely `stat()`-ing them is safe, but `open()`
/// or reading them would trigger a download. A diagnostic tool must never do
/// that by accident, so we ask the kernel to fail such implicit accesses
/// instead. This is the public `setiopolicy_np(3)` API from `<sys/resource.h>`.
///
/// Explicit downloads via `FileManager.startDownloadingUbiquitousItem(at:)`
/// are *not* affected — they go through the file provider, not through
/// implicit materialization.
///
/// The `IOPOL_*` constants are plain `#define`s in `<sys/resource.h>`. Swift
/// normally imports them, but we spell the values out (with the header names
/// in comments) so this file compiles even if the importer skips one.
public enum DatalessMaterializationPolicy {
    // <sys/resource.h>
    private static let IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES: Int32 = 3
    private static let IOPOL_SCOPE_PROCESS: Int32 = 0
    private static let IOPOL_SCOPE_THREAD: Int32 = 1
    private static let IOPOL_MATERIALIZE_DATALESS_FILES_OFF: Int32 = 1

    /// Must surround a synchronous body only: thread-local state cannot cross await.
    public static func withoutMaterialization<T>(_ body: () throws -> T) throws -> T {
        let previous = getiopolicy_np(3, 1)
        guard previous >= 0, setiopolicy_np(3, 1, 1) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Cannot safely disable implicit iCloud downloads."])
        }
        let result = Result { try body() }
        guard setiopolicy_np(3, 1, previous) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Could not restore the prior thread I/O policy."])
        }
        return try result.get()
    }

    /// Current process-level policy value, for the Raw Inspector's diagnostics.
    public static func currentProcessPolicy() -> Int32 {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS)
    }
}

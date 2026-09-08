import Foundation
import Darwin

/// Where iCloud Drive lives on this Mac and whether we can read it.
public struct ICloudDriveLocation: Sendable, Hashable {
    /// `~/Library/Mobile Documents` — the parent of every iCloud container.
    public let mobileDocumentsURL: URL
    /// `~/Library/Mobile Documents/com~apple~CloudDocs` — the user-visible
    /// "iCloud Drive" folder in Finder (including Desktop & Documents when
    /// that option is enabled).
    public let rootURL: URL
    public let mobileDocumentsExists: Bool
    public let rootExists: Bool
    /// We could `contentsOfDirectory` the root without an error.
    public let rootIsReadable: Bool
    public let readError: ItemError?
    /// Other containers (e.g. `iCloud~com~apple~Pages`) visible next to the root.
    /// Only names; scanning them is opt-in.
    public let otherContainerNames: [String]
    /// `FileManager.ubiquityIdentityToken != nil` — an iCloud account is
    /// signed in *and* iCloud Drive is enabled for this process. Public API,
    /// no entitlement required for the check itself.
    public let hasUbiquityIdentityToken: Bool
    /// `FileManager.url(forUbiquityContainerIdentifier: nil)`. Expected to be
    /// `nil` for a direct-download build without the iCloud entitlement —
    /// recorded so the Raw Inspector can show exactly what macOS said.
    public let defaultContainerURL: URL?
    /// Free space on the volume holding iCloud Drive (public resource key).
    public let volumeAvailableBytes: Int64?
    public let volumeTotalBytes: Int64?

    public var isAccessible: Bool { rootExists && rootIsReadable }

    public var accessSummary: String {
        if let readError, !rootExists { return readError.localizedDescription }
        if !mobileDocumentsExists { return "iCloud Drive folder not found (~/Library/Mobile Documents is missing). Is iCloud Drive enabled in System Settings?" }
        if !rootExists { return "com~apple~CloudDocs is missing — iCloud Drive may be turned off for this account." }
        if !rootIsReadable {
            if let readError, readError.looksLikePermissionDenied {
                return "macOS denied access to iCloud Drive. Grant ClearDisk access under System Settings → Privacy & Security → Files and Folders (or Full Disk Access)."
            }
            return "iCloud Drive exists but could not be read: \(readError?.localizedDescription ?? "unknown error")"
        }
        return "iCloud Drive is accessible."
    }
}

public enum ICloudDriveLocator {
    public static let cloudDocsContainerName = "com~apple~CloudDocs"

    /// The *real* home directory, even when sandboxed.
    ///
    /// `FileManager.homeDirectoryForCurrentUser` / `NSHomeDirectory()` return
    /// the sandbox container when App Sandbox is on. `getpwuid(3)` returns the
    /// account's actual home. For the direct-download build both agree; the
    /// helper exists so the sandbox build can reuse the locator and merely add
    /// a security-scoped bookmark on top.
    public static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func mobileDocumentsURL(home: URL = realHomeDirectory()) -> URL {
        home.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
    }

    public static func cloudDocsURL(home: URL = realHomeDirectory()) -> URL {
        mobileDocumentsURL(home: home).appendingPathComponent(cloudDocsContainerName, isDirectory: true)
    }

    /// Probe everything. Safe to call from any thread; does not download anything.
    public static func locate(home: URL = realHomeDirectory()) -> ICloudDriveLocation {
        do { return try DatalessMaterializationPolicy.withoutMaterialization { locateProtected(home: home) } }
        catch {
            return ICloudDriveLocation(mobileDocumentsURL: mobileDocumentsURL(home: home), rootURL: cloudDocsURL(home: home), mobileDocumentsExists: false, rootExists: false, rootIsReadable: false, readError: ItemError(error), otherContainerNames: [], hasUbiquityIdentityToken: false, defaultContainerURL: nil, volumeAvailableBytes: nil, volumeTotalBytes: nil)
        }
    }
    private static func locateProtected(home: URL) -> ICloudDriveLocation {
        let fm = FileManager.default
        let mobileDocs = mobileDocumentsURL(home: home)
        let root = cloudDocsURL(home: home)

        var isDir: ObjCBool = false
        let mobileDocsExists = fm.fileExists(atPath: mobileDocs.path, isDirectory: &isDir) && isDir.boolValue
        let rootExists = fm.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue

        var readable = false
        var readError: ItemError?
        if rootExists {
            do {
                _ = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
                readable = true
            } catch {
                readError = ItemError(error)
                Log.locator.error("Cannot read iCloud Drive root: \(readError!.description)")
            }
        }

        var others: [String] = []
        if mobileDocsExists {
            if let names = try? fm.contentsOfDirectory(atPath: mobileDocs.path) {
                others = names.filter { $0 != cloudDocsContainerName && !$0.hasPrefix(".") }.sorted()
            }
        }

        let token = fm.ubiquityIdentityToken
        // Apple documents this call as potentially slow and says to call it off
        // the main thread. It returns nil without the iCloud entitlement.
        let containerURL = fm.url(forUbiquityContainerIdentifier: nil)

        var available: Int64?
        var total: Int64?
        let volumeProbe = rootExists ? root : home
        if let values = try? volumeProbe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            available = values.volumeAvailableCapacityForImportantUsage
            total = values.volumeTotalCapacity.map(Int64.init)
        }

        let location = ICloudDriveLocation(
            mobileDocumentsURL: mobileDocs,
            rootURL: root,
            mobileDocumentsExists: mobileDocsExists,
            rootExists: rootExists,
            rootIsReadable: readable,
            readError: readError,
            otherContainerNames: others,
            hasUbiquityIdentityToken: token != nil,
            defaultContainerURL: containerURL,
            volumeAvailableBytes: available,
            volumeTotalBytes: total
        )
        Log.locator.info("iCloud Drive: exists=\(rootExists) readable=\(readable) identityToken=\(token != nil) containerURL=\(containerURL != nil) otherContainers=\(others.count)")
        return location
    }
}

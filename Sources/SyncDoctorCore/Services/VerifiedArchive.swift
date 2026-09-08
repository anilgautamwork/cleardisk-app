import Foundation
import CryptoKit
import Darwin

public struct ArchiveReceipt: Sendable {
    public let archiveURL: URL
    public let manifestURL: URL
    public let fileCount: Int
    public let verifiedBytes: Int64
}

public enum VerifiedArchive {
    public static var defaultDestination: URL { ICloudDriveLocator.realHomeDirectory().appendingPathComponent("ClearDisk Archives", isDirectory: true) }
    struct Member: Codable, Equatable {
        let path: String
        let directory: Bool
        let size: Int64
        let inode: UInt64
        let modified: Date
        let changed: Date
        var sha256: String?
    }
    struct Manifest: Codable {
        let version: Int
        let sourcePath: String
        let completedAt: Date
        let members: [Member]
        let note: String
    }
    /// Conservative allowlist: archives are written only below the dedicated home archive folder.
    /// Rejects Desktop/Documents, FileProvider domains, mounted volumes and unknown custom providers.
    public static func validateDestination(_ url: URL, home: URL = ICloudDriveLocator.realHomeDirectory()) throws {
        let canonical = url.standardizedFileURL
        let allowed = home.appendingPathComponent("ClearDisk Archives").standardizedFileURL
        guard url.isFileURL, canonical == canonical.resolvingSymlinksInPath().standardizedFileURL,
              canonical.path == allowed.path || canonical.path.hasPrefix(allowed.path + "/") else {
            throw ICloudActionError.refused("Choose ClearDisk Archives in your home folder (or a folder inside it). Other locations cannot be confirmed outside sync providers.")
        }
        var cursor = canonical
        while cursor.path != "/" {
            if FileManager.default.fileExists(atPath: cursor.path) {
                let values = try cursor.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey])
                guard values.isUbiquitousItem != true, values.volumeIsLocal == true else { throw ICloudActionError.refused("The archive destination is synced or not on a confirmed local volume.") }
            }
            cursor.deleteLastPathComponent()
        }
    }
    public static func create(source: URL, destinationDirectory: URL = defaultDestination,
                              cancellation: @Sendable () -> Bool = { false }) throws -> ArchiveReceipt {
        try ICloudFileActions.validateScope(source)
        return try createLocal(source: source, destinationDirectory: destinationDirectory, home: ICloudDriveLocator.realHomeDirectory(), cancellation: cancellation, requireCloud: true)
    }
    /// Internal fixture entry point. Production calls additionally enforce the iCloud Drive scope.
    static func createLocal(source: URL, destinationDirectory: URL, home: URL,
                            cancellation: @Sendable () -> Bool = { false }, requireCloud: Bool = false) throws -> ArchiveReceipt {
        try validateDestination(destinationDirectory, home: home)
        var staging: URL?
        do {
            return try DatalessMaterializationPolicy.withoutMaterialization {
                func check() throws { if cancellation() || Task.isCancelled { throw CancellationError() } }
                try check()
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                try validateDestination(destinationDirectory, home: home)
                let stage = destinationDirectory.appendingPathComponent("Archive-\(UUID().uuidString)", isDirectory: true)
                try makeDirectory(stage)
                staging = stage
                let target = stage.appendingPathComponent(source.lastPathComponent)
                var receipt: ArchiveReceipt?
                var failure: Error?
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { coordinated in
                    do {
                        try check()
                        guard coordinated.resolvingSymlinksInPath().standardizedFileURL.path == source.resolvingSymlinksInPath().standardizedFileURL.path else { throw ICloudActionError.refused("The source location changed during coordination.") }
                        var before = try inventory(source, check: check, requireCloud: requireCloud)
                        var bytes: Int64 = 0
                        for member in before where !member.directory {
                            let sum = bytes.addingReportingOverflow(member.size)
                            guard member.size >= 0, !sum.overflow else { throw ICloudActionError.refused("Archive size exceeds the supported range.") }
                            bytes = sum.partialValue
                        }
                        let capacity = try destinationDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                        try validateCapacity(available: capacity, required: bytes)
                        for index in before.indices {
                            try check()
                            let member = before[index]
                            let src = member.path.isEmpty ? source : source.appendingPathComponent(member.path)
                            let dst = member.path.isEmpty ? target : target.appendingPathComponent(member.path)
                            if member.directory {
                                try makeDirectory(dst)
                            } else {
                                before[index].sha256 = try copyAndHash(src, dst, check: check)
                                guard try hash(dst, check: check) == before[index].sha256 else { throw ICloudActionError.refused("Archive byte verification failed.") }
                            }
                        }
                        try check()
                        let after = try inventory(source, check: check, requireCloud: requireCloud)
                        guard before.map({ var m = $0; m.sha256 = nil; return m }) == after else { throw ICloudActionError.refused("The source changed while copying. This archive is not verified.") }
                        for member in before where !member.directory {
                            let src = member.path.isEmpty ? source : source.appendingPathComponent(member.path)
                            guard try hash(src, check: check) == member.sha256 else { throw ICloudActionError.refused("The source bytes changed during verification.") }
                        }
                        guard try inventory(source, check: check, requireCloud: requireCloud) == after else { throw ICloudActionError.refused("The source changed during verification.") }
                        try check()
                        let manifestURL = stage.appendingPathComponent("ClearDisk-Manifest-\(UUID().uuidString).json")
                        let manifest = Manifest(version: 1, sourcePath: source.path, completedAt: Date(), members: before, note: "Verified data-fork bytes and directory membership; cloud original retained. Extended attributes, ACLs and resource forks are not archived.")
                        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
                        receipt = ArchiveReceipt(archiveURL: target, manifestURL: manifestURL, fileCount: before.filter { !$0.directory }.count, verifiedBytes: bytes)
                    } catch { failure = error }
                }
                if let error = coordinationError ?? failure as NSError? { throw error }
                guard let receipt else { throw ICloudActionError.refused("Archive coordination did not complete.") }
                return receipt
            }
        } catch {
            throw ICloudActionError.refused("Archive not completed: \(error.localizedDescription). The iCloud original is unchanged." + (staging.map { " Partial copy retained at \($0.path). A copy without a completed manifest is unverified." } ?? ""))
        }
    }
    static func validateCapacity(available: Int64?, required: Int64) throws {
        let reserve: Int64 = 64 * 1024 * 1024
        guard required >= 0, required <= Int64.max - reserve, let available, available > required + reserve else {
            throw ICloudActionError.refused("Insufficient or unknown available local capacity for a verified archive.")
        }
    }
    private static func inventory(_ root: URL, check: () throws -> Void, requireCloud: Bool) throws -> [Member] {
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else { throw ICloudActionError.refused("Symlinks are not supported.") }
        var members: [Member] = []
        func visit(_ url: URL, relative: String) throws {
            try check()
            guard members.count < 50_000 else { throw ICloudActionError.refused("Archive exceeds the 50,000-member safety limit.") }
            let info = try POSIXFileInfo.lstat(path: url.path).get()
            let type = info.mode & UInt16(S_IFMT)
            guard type == UInt16(S_IFREG) || type == UInt16(S_IFDIR) else { throw ICloudActionError.refused("Links and special files cannot be archived.") }
            guard !info.isDataless else { throw ICloudActionError.refused("Download the selected folder or file explicitly, wait for it to finish, then try Archive again.") }
            let metadata = ICloudMetadataReader.item(at: url, relativeTo: root)
            guard !metadata.isAlias, !metadata.hasAnyError, metadata.hasUnresolvedConflicts != true,
                  metadata.isDownloading != true, metadata.isUploading != true else { throw ICloudActionError.refused("An archive member has a transfer, conflict, access error or alias.") }
            if requireCloud, type == UInt16(S_IFREG) {
                guard metadata.isUbiquitous == true, metadata.downloadStatus == .current,
                      metadata.isDownloading == false, metadata.isUploading == false, metadata.hasUnresolvedConflicts == false else { throw ICloudActionError.refused("Current, conflict-free local iCloud metadata is required for every file. Download first, then rescan.") }
            }
            // Refuse executable files and semantic metadata that a data-fork archive cannot preserve.
            if type == UInt16(S_IFREG), info.mode & 0o111 != 0 {
                throw ICloudActionError.refused("Executable files and application bundles require Finder to preserve their executable permissions.")
            }
            let attributes = try POSIXFileInfo.xattrNames(path: url.path).get()
            let unsupported = attributes.filter { name in
                !(name.hasPrefix("com.apple.fileprovider.") || name.hasPrefix("com.apple.icloud.") || name.hasPrefix("com.apple.ubiquity.") || name == "com.apple.provenance" || name == "com.apple.lastuseddate#PS")
            }
            guard unsupported.isEmpty else { throw ICloudActionError.refused("This item has extended metadata (\(unsupported.joined(separator: ", "))) that requires a Finder copy to preserve completely.") }

            members.append(Member(path: relative, directory: type == UInt16(S_IFDIR), size: type == UInt16(S_IFDIR) ? 0 : info.size, inode: info.inode, modified: info.modified, changed: info.changed))
            if type == UInt16(S_IFDIR) {
                for name in try directoryNames(url).sorted() {
                    let child = url.appendingPathComponent(name)
                    try visit(child, relative: relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(root, relative: "")
        return members
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    /// Open every ancestor separately with O_NOFOLLOW. A symlink swap cannot redirect a read/write.
    private static func parentDescriptor(_ url: URL) throws -> Int32 {
        let parts = url.pathComponents.dropFirst().dropLast()
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw posixError() }
        for part in parts {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            close(fd)
            guard next >= 0 else { throw ICloudActionError.refused("Cannot open safe directory ancestor \(part) in \(url.path): \(posixError().localizedDescription)") }
            fd = next
        }
        return fd
    }
    private static func makeDirectory(_ url: URL) throws {
        let parent = try parentDescriptor(url); defer { close(parent) }
        guard mkdirat(parent, url.lastPathComponent, 0o700) == 0 else { throw posixError() }
    }
    private static func directoryNames(_ url: URL) throws -> [String] {
        let parent = try parentDescriptor(url); defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw posixError() }
        guard let directory = fdopendir(fd) else { close(fd); throw posixError() }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
            guard names.count <= 50_000 else { throw ICloudActionError.refused("Directory exceeds archive member limit.") }
            errno = 0
        }
        guard errno == 0 else { throw posixError() }
        return names
    }
    private static func safeOpen(_ url: URL) throws -> Int32 {
        let parent = try parentDescriptor(url); defer { close(parent) }
        let descriptor = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw posixError() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG), info.st_flags & POSIXFileInfo.SF_DATALESS == 0 else { close(descriptor); throw ICloudActionError.refused("The source is no longer a downloaded regular file.") }
        return descriptor
    }
    private static func hash(_ url: URL, check: () throws -> Void) throws -> String {
        let fd = try safeOpen(url); defer { close(fd) }
        var digest = SHA256(); var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true { try check(); let count = read(fd, &buffer, buffer.count); guard count >= 0 else { throw posixError() }; if count == 0 { break }; digest.update(data: Data(buffer.prefix(count))) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func copyAndHash(_ source: URL, _ target: URL, check: () throws -> Void) throws -> String {
        let input = try safeOpen(source); defer { close(input) }
        let parent = try parentDescriptor(target); defer { close(parent) }
        let output = openat(parent, target.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { throw posixError() }; defer { close(output) }
        var digest = SHA256(); var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            try check(); let count = read(input, &buffer, buffer.count)
            guard count >= 0 else { throw posixError() }; if count == 0 { break }
            digest.update(data: Data(buffer.prefix(count)))
            try buffer.withUnsafeBytes { bytes in
                var offset = 0
                while offset < count { try check(); let written = write(output, bytes.baseAddress!.advanced(by: offset), count - offset); guard written > 0 else { throw posixError() }; offset += written }
            }
        }
        guard fsync(output) == 0 else { throw posixError() }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

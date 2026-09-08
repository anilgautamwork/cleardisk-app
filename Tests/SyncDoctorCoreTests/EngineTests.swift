import XCTest
import Darwin
@testable import SyncDoctorCore

final class SyncDoctorCoreTests: XCTestCase {

    private func item(name: String, kind: ItemKind = .file, size: Int64? = 100, allocated: Int64? = 100,
                      ubiquitous: Bool? = true, status: DownloadStatus = .current,
                      uploaded: Bool? = true, uploading: Bool? = false, uploadError: ItemError? = nil,
                      conflicts: Bool? = false, dataless: Bool? = false) -> ICloudItem {
        ICloudItem(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, path: "/tmp/\(name)", relativePath: name,
                   kind: kind, isPackage: false, isHidden: false, isAlias: false,
                   logicalSize: size, allocatedSize: allocated,
                   modificationDate: Date(timeIntervalSince1970: 1), creationDate: nil, lastAccessDate: nil, addedToDirectoryDate: nil,
                   isUbiquitous: ubiquitous, downloadStatus: status, isDownloading: false, downloadRequested: nil,
                   downloadError: nil, isUploaded: uploaded, isUploading: uploading, uploadError: uploadError,
                   percentDownloaded: nil, percentUploaded: nil, hasUnresolvedConflicts: conflicts,
                   isExcludedFromSync: nil, isExcludedFromBackup: nil, isShared: nil, containerDisplayName: nil,
                   isDataless: dataless, accessError: nil)
    }

    func testLocalityNeverGuesses() {
        XCTAssertEqual(item(name: "unknown-membership", ubiquitous: nil, status: .unknown, dataless: false).locality, .unknown)
        XCTAssertEqual(item(name: "a", status: .unknown, dataless: nil).locality, .unknown)
        XCTAssertEqual(item(name: "b", status: .unknown, dataless: true).locality, .cloudOnly)
        XCTAssertEqual(item(name: "c", status: .notDownloaded).locality, .cloudOnly)
        XCTAssertEqual(item(name: "d", ubiquitous: false).locality, .notUbiquitous)
        XCTAssertNil(item(name: "e", status: .unknown).isDownloaded)
    }

    func testSummaryCounts() {
        let items = [
            item(name: "synced"),
            item(name: "waiting", uploaded: false),
            item(name: "uploading", uploaded: false, uploading: true),
            item(name: "cloud", size: 1000, allocated: 0, status: .notDownloaded),
            item(name: "err", uploaded: false, uploadError: ItemError(domain: "x", code: 1, localizedDescription: "boom")),
            item(name: "conflict", conflicts: true),
            item(name: "dir", kind: .directory, size: nil, allocated: nil),
        ]
        let s = ScanSummary(items: items, issues: [])
        XCTAssertEqual(s.totalItems, 7)
        XCTAssertEqual(s.files, 6)
        XCTAssertEqual(s.directories, 1)
        XCTAssertEqual(s.syncedFiles, 2) // "synced" and "conflict" are uploaded+current
        XCTAssertEqual(s.waitingToUpload, 1)
        XCTAssertEqual(s.uploading, 1)
        XCTAssertEqual(s.notDownloaded, 1)
        XCTAssertEqual(s.uploadErrors, 1)
        XCTAssertEqual(s.unresolvedConflicts, 1)
        XCTAssertEqual(s.problemCount, 2)
        XCTAssertEqual(s.estimatedCloudOnlyBytes, 1000)
    }

    func testClassifierBuckets() {
        let items = [
            item(name: "waiting", uploaded: false),
            item(name: "err", uploaded: false, uploadError: ItemError(domain: "x", code: 1, localizedDescription: "boom")),
            item(name: "big", size: 20 * 1024 * 1024 * 1024),
            item(name: "cloud", status: .notDownloaded),
        ]
        let grouped = ProblemClassifier().classify(items: items, issues: [])
        XCTAssertEqual(grouped[.waitingToUpload]?.count, 1)
        XCTAssertEqual(grouped[.uploadFailed]?.count, 1)
        XCTAssertNil(grouped[.oversized])
        XCTAssertEqual(grouped[.notDownloaded]?.count, 1)
        XCTAssertNil(grouped[.uploadingLong])
    }

    func testStuckRequiresHistory() {
        let items = [item(name: "waiting", uploaded: false)]
        let grouped = ProblemClassifier().classify(items: items, issues: [], stuckPaths: ["/tmp/waiting"])
        XCTAssertEqual(grouped[.uploadingLong]?.count, 1)
        XCTAssertNil(grouped[.waitingToUpload])
    }

    func testLogRedaction() {
        LogSettings.shared.verbosePaths = false
        let redacted = Log.path("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/secret.pdf")
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertTrue(redacted.hasPrefix("<path "))
    }

    func testLocatorPathsAreUnderRealHome() {
        let home = ICloudDriveLocator.realHomeDirectory()
        XCTAssertTrue(ICloudDriveLocator.cloudDocsURL(home: home).path.hasSuffix("Library/Mobile Documents/com~apple~CloudDocs"))
    }
    func result(_ items: [ICloudItem], _ time: TimeInterval, complete: Bool = true) -> ScanResult {
        ScanResult(roots: [URL(fileURLWithPath: "/fixture")], startedAt: Date(timeIntervalSince1970: time), finishedAt: Date(timeIntervalSince1970: time), items: items, issues: [], wasCancelled: !complete, hitItemLimit: false)
    }
    func testConsecutiveHistoryResetsForHealthyMissingUnknownAndIncomplete() throws {
        let pending = item(name: "pending", uploaded: false)
        for reset in [result([item(name: "pending")], 200), result([], 200), result([item(name: "pending", uploaded: nil)], 200), result([pending], 200, complete: false)] {
            var history = PendingHistory()
            history.record(result([pending], 100)); history.record(reset); history.record(result([pending], 4000))
            XCTAssertTrue(history.potentiallyStuckPaths(now: Date(timeIntervalSince1970: 4000), minimumInterval: 3600).isEmpty)
        }
        var history = PendingHistory()
        history.record(result([pending], 100)); history.record(result([pending], 4000))
        XCTAssertEqual(history.potentiallyStuckPaths(now: Date(timeIntervalSince1970: 4000), minimumInterval: 3600), [pending.path])
        let decoded = try JSONDecoder().decode(PendingHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded.observations[pending.path]?.count, 2)
    }
    func testUnknownEvictionRefusedAndNoiseSuppressed() {
        XCTAssertNil(ICloudFileActions.evictionRefusal(for: item(name: "safe")))
        for unsafe in [item(name: "unknown", uploaded: nil), item(name: "uploading", uploading: true), item(name: "conflict", conflicts: nil), item(name: "dir", kind: .directory), item(name: "link", kind: .symlink), item(name: "cloud", status: .notDownloaded)] {
            XCTAssertNotNil(ICloudFileActions.evictionRefusal(for: unsafe))
        }
        let noise = item(name: ".DS_Store", uploadError: ItemError(domain: "noise", code: 1, localizedDescription: "noise"))
        XCTAssertTrue(ProblemClassifier().classify(items: [noise], issues: []).isEmpty)
        XCTAssertEqual(ScanSummary(items: [noise], issues: []).problemCount, 0)
        XCTAssertEqual(item(name: "unknown", allocated: nil).estimatedLocalBytes, 0)
    }
    func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("cleardisk-engine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Disposable fixtures are retained; production's TrashService-only deletion boundary stays auditable.
        return root
    }
    func testArchiveFileAndPackageManifestIntegrityAndNoOverwrite() throws {
        let root = try fixture()
        let package = root.appendingPathComponent("sample.pages")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let data = Data("Document bytes 🦊".utf8)
        try data.write(to: package.appendingPathComponent("nested/content"))
        let destination = root.appendingPathComponent("ClearDisk Archives")
        let receipt = try VerifiedArchive.createLocal(source: package, destinationDirectory: destination, home: root)
        XCTAssertEqual(receipt.fileCount, 1); XCTAssertEqual(receipt.verifiedBytes, Int64(data.count))
        XCTAssertEqual(try Data(contentsOf: receipt.archiveURL.appendingPathComponent("nested/content")), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.path))
        let second = try VerifiedArchive.createLocal(source: package, destinationDirectory: destination, home: root)
        XCTAssertNotEqual(receipt.archiveURL, second.archiveURL)
        let file = try VerifiedArchive.createLocal(source: package.appendingPathComponent("nested/content"), destinationDirectory: destination, home: root)
        XCTAssertEqual(try Data(contentsOf: file.archiveURL), data)
    }
    func testArchiveRejectsSymlinksAndSyncedDestinations() throws {
        let root = try fixture(), file = root.appendingPathComponent("file")
        try Data("safe".utf8).write(to: file)
        let destination = root.appendingPathComponent("ClearDisk Archives")
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: file, destinationDirectory: root.appendingPathComponent("Documents"), home: root))
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: root)
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: file, destinationDirectory: destination, home: root))
        let package = root.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("link"), withDestinationURL: file)
        let another = try fixture()
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: package, destinationDirectory: another.appendingPathComponent("ClearDisk Archives"), home: another))
    }
    func testArchiveCancellationRetainsSourceAndPartialStage() throws {
        let root = try fixture(), source = root.appendingPathComponent("file")
        try Data(repeating: 7, count: 3 * 1024 * 1024).write(to: source)
        let counter = CancelCounter()
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: source, destinationDirectory: root.appendingPathComponent("ClearDisk Archives"), home: root, cancellation: { counter.next() > 7 }))
        XCTAssertEqual(try Data(contentsOf: source).count, 3 * 1024 * 1024)
        let stages = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("ClearDisk Archives"), includingPropertiesForKeys: nil)
        XCTAssertEqual(stages.count, 1)
        guard let stage = stages.first else { return }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: stage.path).contains { $0.hasPrefix("ClearDisk-Manifest") })
    }

    func testArchiveRefusesExecutableAndSemanticAttributes() throws {
        let root = try fixture(), source = root.appendingPathComponent("executable")
        try Data("#!/bin/sh".utf8).write(to: source)
        XCTAssertEqual(chmod(source.path, 0o700), 0)
        let destination = root.appendingPathComponent("ClearDisk Archives")
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: source, destinationDirectory: destination, home: root))
        XCTAssertEqual(chmod(source.path, 0o600), 0)
        let value = "fixture"
        XCTAssertEqual(value.withCString { setxattr(source.path, "user.fixture", $0, value.utf8.count, 0, 0) }, 0)
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: source, destinationDirectory: destination, home: root))
        XCTAssertEqual(try Data(contentsOf: source), Data("#!/bin/sh".utf8))
    }
    func testArchiveSourceMutationCannotProduceCompletionManifest() throws {
        let root = try fixture(), source = root.appendingPathComponent("file")
        try Data("before".utf8).write(to: source)
        let counter = CancelCounter()
        XCTAssertThrowsError(try VerifiedArchive.createLocal(source: source, destinationDirectory: root.appendingPathComponent("ClearDisk Archives"), home: root, cancellation: {
            if counter.next() == 5 { try? Data("changed source".utf8).write(to: source) }
            return false
        }))
        let stages = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("ClearDisk Archives"), includingPropertiesForKeys: nil)
        XCTAssertEqual(stages.count, 1)
        for stage in stages { XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: stage.path).contains { $0.hasPrefix("ClearDisk-Manifest") }) }
    }
    func testUnknownOrInsufficientArchiveCapacityFailsClosed() throws {
        XCTAssertThrowsError(try VerifiedArchive.validateCapacity(available: nil, required: 1))
        XCTAssertThrowsError(try VerifiedArchive.validateCapacity(available: 1024, required: 2048))
        XCTAssertThrowsError(try VerifiedArchive.validateCapacity(available: Int64.max, required: Int64.max))
        XCTAssertNoThrow(try VerifiedArchive.validateCapacity(available: 128 * 1024 * 1024, required: 1024))
    }
    func testPublicActionsRefuseLocalFixtureWithoutMutation() throws {
        let root = try fixture(), source = root.appendingPathComponent("file")
        try Data("unchanged".utf8).write(to: source)
        XCTAssertThrowsError(try ICloudFileActions.requestDownload(of: source))
        XCTAssertThrowsError(try ICloudFileActions.evictLocalCopy(of: source))
        XCTAssertThrowsError(try VerifiedArchive.create(source: source))
        XCTAssertEqual(try Data(contentsOf: source), Data("unchanged".utf8))
    }
    func testScannerCapsAndCancellationAndPolicyRestore() async throws {
        let root = try fixture()
        for index in 0..<30 { try Data().write(to: root.appendingPathComponent("file-\(index)")) }
        var options = ScanOptions(roots: [root]); options.maxItems = 3; options.progressEvery = 0
        let result = await ICloudScanner().scanToResult(options: options)
        XCTAssertEqual(result.items.count, 3); XCTAssertTrue(result.hitItemLimit); XCTAssertFalse(result.isComplete)
        let task = Task { await ICloudScanner().scanToResult(options: ScanOptions(roots: [root])) }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.wasCancelled)
        let previous = getiopolicy_np(3, 1)
        try DatalessMaterializationPolicy.withoutMaterialization { XCTAssertEqual(getiopolicy_np(3, 1), 1) }
        XCTAssertEqual(getiopolicy_np(3, 1), previous)
    }

}

private final class CancelCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

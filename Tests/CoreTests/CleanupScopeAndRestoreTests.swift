import Foundation
import XCTest
@testable import Core

final class CleanupScopeAndRestoreTests: XCTestCase {
    private func fixture() throws -> String {
        let root = NSHomeDirectory() + "/.cleardisk-scope-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: false)
        return root
    }
    private func file(_ path: String, contents: String = "owned fixture") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func cacheReport(_ root: String) throws -> SystemDataReport {
        for name in ["AppCache", "Google", "Firefox"] { try file(root + "/Library/Caches/" + name + "/data") }
        let scan = try ParallelScan.scan(path: root, skipPrefixes: [])
        return SystemDataScan.build(homeRoot: scan.root, homePath: root)
    }
    private func targets(_ rows: [SystemDataReport.Row]) -> [RemovalBatch.Target] {
        rows.flatMap { row in row.cleanRoots.map { .init(path: $0, contentsOnly: true, excludingChildNames: row.cleanExcludingNames) } }
    }

    func testApplicationCacheSelectionPreservesUnselectedBrowserRootsAndContents() throws {
        for method in [RemovalBatch.Method.trash, .permanently] {
            let root = try fixture()
            defer { try? TrashService.deleteForever(root) }
            let report = try cacheReport(root)
            let row = try XCTUnwrap(report.rows.first { $0.id == "app-caches" })
            XCTAssertEqual(Set(row.cleanExcludingNames), SystemDataScan.browserCacheDirNames)
            let result = RemovalBatch.perform(targets: targets([row]), method: method)
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.removedPaths, [root + "/Library/Caches/AppCache"])
            XCTAssertTrue(exists(root + "/Library/Caches/Google/data"))
            XCTAssertTrue(exists(root + "/Library/Caches/Firefox/data"))
            XCTAssertTrue(exists(root + "/Library/Caches"))
            _ = TrashService.restore(result.trashedItems)
        }
    }

    func testBrowserCacheSelectionPreservesApplicationCacheAndBrowserContainers() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        let report = try cacheReport(root)
        let row = try XCTUnwrap(report.rows.first { $0.id == "browser-caches" })
        XCTAssertTrue(row.cleanExcludingNames.isEmpty)
        let result = RemovalBatch.perform(targets: targets([row]), method: .permanently)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(result.removedPaths), [root + "/Library/Caches/Google/data", root + "/Library/Caches/Firefox/data"])
        XCTAssertTrue(exists(root + "/Library/Caches/AppCache/data"))
        for name in ["Google", "Firefox"] { XCTAssertTrue(exists(root + "/Library/Caches/" + name)) }
    }

    func testBothCacheRowsRemoveOnlySelectedContentsAndRetainBrowserContainers() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        let report = try cacheReport(root)
        let rows = report.rows.filter { ["app-caches", "browser-caches"].contains($0.id) }
        let result = RemovalBatch.perform(targets: targets(rows), method: .permanently)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(result.removedPaths), [root + "/Library/Caches/AppCache", root + "/Library/Caches/Google/data", root + "/Library/Caches/Firefox/data"])
        XCTAssertTrue(exists(root + "/Library/Caches/Google"))
        XCTAssertTrue(exists(root + "/Library/Caches/Firefox"))
    }

    func testTargetsWithDifferentExclusionsExpandIndependently() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/a"); try file(root + "/b")
        let result = RemovalBatch.perform(targets: [
            .init(path: root, contentsOnly: true, excludingChildNames: ["a"]),
            .init(path: root, contentsOnly: true, excludingChildNames: ["b"]),
        ], method: .permanently)
        XCTAssertEqual(Set(result.removedPaths), [root + "/a", root + "/b"])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testRestoreReportingDistinguishesSuccessConflictAndMissingSource() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/staged/good")
        try file(root + "/staged/conflict")
        try file(root + "/conflict", contents: "keep existing")
        let items = ["good", "conflict", "missing"].map {
            TrashService.TrashedItem(originalPath: root + "/" + $0, trashURL: URL(fileURLWithPath: root + "/staged/" + $0))
        }
        let result = TrashService.restoreReporting(items)
        XCTAssertEqual(result.restoredPaths, [root + "/good"])
        XCTAssertEqual(Set(result.failedItems.map(\.originalPath)), [root + "/conflict", root + "/missing"])
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(result.failures.contains { $0.contains(root + "/conflict") })
        XCTAssertTrue(exists(root + "/good"))
        XCTAssertTrue(exists(root + "/staged/conflict"))
        XCTAssertEqual(try String(contentsOfFile: root + "/conflict", encoding: .utf8), "keep existing")
    }

    func testSelectiveReattachmentRestoresOnlySuccessfulBytesIncludingMissingUndoRecords() {
        let scanPath = NSHomeDirectory() + "/.cleardisk-tree-fixture"
        let root = FileNode(name: "root", isDirectory: true, size: 60, modTime: 0)
        let a = FileNode(name: "a", isDirectory: false, size: 10, modTime: 0)
        let b = FileNode(name: "b", isDirectory: false, size: 20, modTime: 0)
        let noUndo = FileNode(name: "no-undo-url", isDirectory: false, size: 30, modTime: 0)
        root.children = [a, b, noUndo]
        let removed = TreeSurgery.remove(paths: ["a", "b", "no-undo-url"].map { scanPath + "/" + $0 }, root: root, scanPath: scanPath)
        TreeSurgery.adjustTrash(by: removed.bytes, root: root, scanPath: scanPath, homePath: scanPath)
        let restoredBytes = TreeSurgery.reattachRestored(removed.removed, originalPaths: [scanPath + "/a"], root: root, scanPath: scanPath)
        TreeSurgery.adjustTrash(by: -restoredBytes, root: root, scanPath: scanPath, homePath: scanPath)
        XCTAssertEqual(restoredBytes, 10)
        XCTAssertNotNil(root.child("a"))
        XCTAssertNil(root.child("b"))
        XCTAssertNil(root.child("no-undo-url"))
        XCTAssertEqual(root.child(".Trash")?.size, 50)
        XCTAssertEqual(root.size, 60)
        XCTAssertEqual(TreeSurgery.reattachRestored(removed.removed, originalPaths: [scanPath + "/a"], root: root, scanPath: scanPath), 0)
    }

    func testEmptyRestoreReportDoesNotClaimSuccess() {
        let report = TrashService.restoreReporting([])
        XCTAssertTrue(report.restoredPaths.isEmpty)
        XCTAssertTrue(report.failedItems.isEmpty)
        XCTAssertTrue(report.failures.isEmpty)
    }
}

import XCTest
@testable import Core
@testable import ClearDiskApp
import PerformanceUI

final class StorageMenuTests: XCTestCase {
    func testLargestFilesUseOnlyCompletedTreeValuesAndKeepTopThree() {
        let root = FileNode(name: "/", isDirectory: true, size: 1_500_000_000, modTime: 0)
        root.children = [file("small", 99_000_000), file("b", 200_000_000), file("a", 400_000_000),
                         file("c", 300_000_000), file("d", 100_000_000)]
        let rows = AppState.largestMenuFiles(root: root, rootPath: "/")
        XCTAssertEqual(rows.map(\.name), ["a", "c", "b"])
        XCTAssertEqual(rows.map(\.id), ["/a", "/c", "/b"])
        root.children = []
        XCTAssertEqual(rows.first?.bytes, 400_000_000) // Snapshot cannot retain a mutable FileNode.
    }

    @MainActor
    func testIncompleteScansDoNotAdvertiseOldStorageFindings() {
        let state = AppState()
        state.root = file("root", 400_000_000)
        state.scanDate = Date()
        state.menuFiles = [StorageMenuFile(path: "/old", name: "old", bytes: 400_000_000)]
        state.phase = .scanning
        XCTAssertTrue(state.storageMenuSummary.isScanning)
        XCTAssertNil(state.storageMenuSummary.scanDate)
        XCTAssertTrue(state.storageMenuSummary.files.isEmpty)
        state.phase = .welcome
        XCTAssertNil(state.storageMenuSummary.scanDate)
    }

    @MainActor
    func testStorageShortcutsOnlyNavigateAndRespectScanState() {
        let state = AppState()
        state.root = file("root", 400_000_000)
        state.phase = .done
        state.openWorkspace(.performance)
        state.openStorageReview(.largeFiles)
        XCTAssertEqual(state.section, .largeFiles)
        XCTAssertFalse(state.showPerformance)
        XCTAssertEqual(state.phase, .done)
        state.openStorageReview(.developerJunk)
        XCTAssertEqual(state.section, .reclaimable)
        state.openStorageReview(.caches)
        XCTAssertTrue(state.showPermissions) // Folder scan has no home cache measurement.
        state.phase = .scanning
        state.openStorageReview(.scan)
        XCTAssertFalse(state.showPermissions)
        XCTAssertEqual(state.phase, .scanning)
        XCTAssertEqual(state.activeRemovals, 0)
    }

    @MainActor
    func testFolderSummaryDoesNotInventCacheSizeAndReportsSkippedItems() {
        let state = AppState()
        state.root = file("root", 200_000_000)
        state.phase = .done
        state.scanDate = Date()
        var stats = ScanStats()
        stats.skippedCount = 7
        state.stats = stats
        XCTAssertNil(state.storageMenuSummary.cacheBytes)
        XCTAssertEqual(state.storageMenuSummary.skippedCount, 7)
    }

    private func file(_ name: String, _ bytes: Int64) -> FileNode {
        FileNode(name: name, isDirectory: false, size: bytes, modTime: 0)
    }
}

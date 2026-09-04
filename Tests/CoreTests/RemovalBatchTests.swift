import Foundation
import XCTest
@testable import Core

final class RemovalBatchTests: XCTestCase {
    private func fixture() throws -> String {
        let path = NSHomeDirectory() + "/.cleardisk-batch-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        return path
    }
    private func file(_ path: String) throws { try "owned test fixture".write(toFile: path, atomically: true, encoding: .utf8) }
    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func testTrashContentsRetainsContainerAndProvidesUndoForEachSuccess() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/a.txt")
        try FileManager.default.createDirectory(atPath: root + "/nested", withIntermediateDirectories: false)
        try file(root + "/nested/b.txt")
        let result = RemovalBatch.perform(targets: [.init(path: root, contentsOnly: true)], method: .trash)
        XCTAssertEqual(Set(result.removedPaths), [root + "/a.txt", root + "/nested"])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.trashedItems.count, 2)
        XCTAssertTrue(exists(root))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root).isEmpty)
        XCTAssertEqual(TrashService.restore(result.trashedItems), 2)
        XCTAssertTrue(exists(root + "/nested/b.txt"))
    }

    func testDeduplicatesExpandedAndOverlappingTargetsBeforePermanentRemoval() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        let parent = root + "/parent"
        try FileManager.default.createDirectory(atPath: parent + "/nested", withIntermediateDirectories: true)
        try file(parent + "/nested/a.txt")
        let result = RemovalBatch.perform(targets: [
            .init(path: parent + "/nested/a.txt"), .init(path: parent, contentsOnly: true),
            .init(path: parent), .init(path: parent), .init(path: parent + "/nested", contentsOnly: true),
        ], method: .permanently)
        XCTAssertEqual(result.removedPaths, [parent])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.trashedItems.isEmpty)
        XCTAssertFalse(exists(parent))
        XCTAssertTrue(exists(root))
    }

    func testProtectedPathsAreRefusedForBothMethodsAndContentsMode() {
        for method in [RemovalBatch.Method.trash, .permanently] {
            let result = RemovalBatch.perform(targets: [
                .init(path: NSHomeDirectory()),
                .init(path: NSHomeDirectory(), contentsOnly: true),
                .init(path: NSHomeDirectory() + "/Library/Preferences", contentsOnly: true),
                .init(path: "/System/Library", contentsOnly: true),
            ], method: method)
            XCTAssertTrue(result.removedPaths.isEmpty)
            XCTAssertTrue(result.trashedItems.isEmpty)
            XCTAssertEqual(result.failures.count, 4)
        }
    }

    func testRejectsSymlinkContentRootAndSymlinkAncestorWithoutTouchingDestination() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        let destination = root + "/destination"
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
        try file(destination + "/keep.txt")
        try FileManager.default.createSymbolicLink(atPath: root + "/alias", withDestinationPath: destination)
        let result = RemovalBatch.perform(targets: [
            .init(path: root + "/alias", contentsOnly: true), .init(path: root + "/alias/keep.txt"),
        ], method: .permanently)
        XCTAssertTrue(result.removedPaths.isEmpty)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(exists(destination + "/keep.txt"))
    }

    func testRemovingASymlinkLeafDoesNotRemoveItsDestination() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/keep.txt")
        try FileManager.default.createDirectory(atPath: root + "/container", withIntermediateDirectories: false)
        let alias = root + "/container/alias"
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: root + "/keep.txt")
        let result = RemovalBatch.perform(targets: [.init(path: root + "/container", contentsOnly: true)], method: .permanently)
        XCTAssertEqual(result.removedPaths, [alias])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(exists(root + "/keep.txt"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root + "/container").isEmpty)
    }

    func testMissingOrNonDirectoryContentsTargetsFailWithoutDeletingTheFile() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/keep.txt")
        let result = RemovalBatch.perform(targets: [
            .init(path: root + "/missing", contentsOnly: true), .init(path: root + "/keep.txt", contentsOnly: true),
        ], method: .permanently)
        XCTAssertTrue(result.removedPaths.isEmpty)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(exists(root + "/keep.txt"))
    }

    func testMixedResultReportsOnlySuccessfulPathsAndDeduplicatesRepeatedTargets() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/a.txt")
        let result = RemovalBatch.perform(targets: [
            .init(path: root + "/a.txt"), .init(path: root + "//a.txt"),
            .init(path: root + "/missing"), .init(path: root + "/missing"),
        ], method: .permanently)
        XCTAssertEqual(result.removedPaths, [root + "/a.txt"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].contains(root + "/missing"))
    }

    func testEmptyTargetsAndEmptyContainerAreNoOps() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        for targets: [RemovalBatch.Target] in [[], [.init(path: root, contentsOnly: true)]] {
            let result = RemovalBatch.perform(targets: targets, method: .permanently)
            XCTAssertTrue(result.removedPaths.isEmpty)
            XCTAssertTrue(result.failures.isEmpty)
        }
        XCTAssertTrue(exists(root))
    }

    func testPermanentConfirmationRequiresExactNonemptyExpectedText() {
        XCTAssertTrue(RemovalBatch.confirmationMatches("report.txt", expected: "report.txt"))
        for typed in ["", "report", "Report.txt", " report.txt", "report.txt ", "report.txt\n"] {
            XCTAssertFalse(RemovalBatch.confirmationMatches(typed, expected: "report.txt"), typed)
        }
        XCTAssertFalse(RemovalBatch.confirmationMatches("", expected: ""))
    }

    func testParentTraversalIsRefusedRatherThanNormalizedAcrossASymlink() throws {
        let root = try fixture()
        defer { try? TrashService.deleteForever(root) }
        try file(root + "/keep.txt")
        let result = RemovalBatch.perform(targets: [.init(path: root + "/other/../keep.txt")], method: .permanently)
        XCTAssertTrue(result.removedPaths.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(exists(root + "/keep.txt"))
    }
}

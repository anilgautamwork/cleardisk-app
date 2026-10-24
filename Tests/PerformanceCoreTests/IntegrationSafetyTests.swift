import XCTest
@testable import PerformanceCore

final class PerformanceIntegrationSafetyTests: XCTestCase {
    func testClearDiskCannotQuitItself() {
        for name in ["ClearDisk", "ClearDiskApp", "WhySlow"] {
            XCTAssertFalse(SafetyGate.canQuit(uid: 501, currentUID: 501,
                path: "/Applications/\(name).app/Contents/MacOS/\(name)", name: name, isRegularApp: true))
        }
    }

    func testHistoryClearPreservesDirectoriesSymlinksAndUnrelatedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        let folder = directory.appendingPathComponent("usage-2026-01-01.jsonl")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("usage-2026-01-02.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
        let record = directory.appendingPathComponent("usage-2026-01-03.jsonl")
        try Data("{}\n".utf8).write(to: record)
        try UsageStore(directory: directory).clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testShellDrainsBothPipesWithoutDeadlock() throws {
        let output = try Shell.run("/bin/sh", ["-c", "i=0; while [ $i -lt 10000 ]; do echo diagnostic-line >&2; i=$((i+1)); done; echo done"], timeout: 5)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "done")
        XCTAssertGreaterThan(output.stderr.count, 100000)
    }

    func testShellTimesOutStuckTool() {
        let started = Date()
        XCTAssertThrowsError(try Shell.run("/bin/sleep", ["10"], timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }
}

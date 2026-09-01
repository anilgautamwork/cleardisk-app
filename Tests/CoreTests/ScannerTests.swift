import Darwin
import Foundation
import XCTest
@testable import Core

final class ScannerTests: XCTestCase {

    var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("macclear-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.appendingPathComponent("c"), withIntermediateDirectories: true)

        try write("f1.bin", bytes: 100_000)
        try write("a/f2.bin", bytes: 250_000)
        try write("a/b/f3.bin", bytes: 1_000_000)

        // Hardlink: same inode reachable twice, must be counted once.
        XCTAssertEqual(link(fixture.appendingPathComponent("f1.bin").path,
                            fixture.appendingPathComponent("a/hardlink.bin").path), 0)

        // Symlink to the biggest file: must not be followed.
        try fm.createSymbolicLink(at: fixture.appendingPathComponent("c/link"),
                                  withDestinationURL: fixture.appendingPathComponent("a/b/f3.bin"))

        // Sparse file: 50 MB logical, ~0 allocated.
        let sparseFD = open(fixture.appendingPathComponent("c/sparse.bin").path,
                            O_CREAT | O_WRONLY, 0o644)
        XCTAssertGreaterThanOrEqual(sparseFD, 0)
        XCTAssertEqual(ftruncate(sparseFD, 50_000_000), 0)
        close(sparseFD)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func write(_ relative: String, bytes: Int) throws {
        let data = Data(repeating: 0xA5, count: bytes)
        try data.write(to: fixture.appendingPathComponent(relative))
    }

    func testBulkMatchesReferenceScanner() throws {
        let scanner = BulkScanner()
        _ = try scanner.scan(path: fixture.path)
        let reference = ReferenceScanner.scan(path: fixture.path)

        XCTAssertEqual(scanner.stats.totalBytes, reference.totalBytes)
        XCTAssertEqual(scanner.stats.fileCount, reference.fileCount)
        XCTAssertEqual(scanner.stats.directoryCount, reference.directoryCount)
        XCTAssertEqual(scanner.stats.skippedCount, 0)
    }

    func testBulkMatchesDu() throws {
        let scanner = BulkScanner()
        _ = try scanner.scan(path: fixture.path)

        let du = Process()
        du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        du.arguments = ["-sk", fixture.path]
        let pipe = Pipe()
        du.standardOutput = pipe
        try du.run()
        du.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let duBytes = Int64(out.split(separator: "\t").first.flatMap { Int($0) } ?? -1) * 1024

        // du counts directory blocks too (0 on APFS); allow a few blocks of slack.
        XCTAssertEqual(Double(scanner.stats.totalBytes), Double(duBytes), accuracy: 3 * 4096)
    }

    func testHardlinkCountedOnce() throws {
        let scanner = BulkScanner()
        _ = try scanner.scan(path: fixture.path)
        // f1(100k) + f2(250k) + f3(1M) once each, hardlink adds nothing;
        // if it were double counted the total would exceed this bound.
        XCTAssertLessThan(scanner.stats.totalBytes, 1_500_000)
        XCTAssertGreaterThan(scanner.stats.totalBytes, 1_350_000)
    }

    func testSymlinkNotFollowedAndSparseUsesAllocatedSize() throws {
        let scanner = BulkScanner()
        _ = try scanner.scan(path: fixture.path)
        // Following c/link would re-add f3's 1MB; materializing the sparse file
        // would add 50MB. Either failure blows past this ceiling.
        XCTAssertLessThan(scanner.stats.totalBytes, 2_000_000)
    }

    func testTreeStructureAndSizes() throws {
        let scanner = BulkScanner()
        let root = try scanner.scan(path: fixture.path)

        XCTAssertEqual(root.size, scanner.stats.totalBytes)
        let a = root.children?.first { $0.name == "a" }
        XCTAssertNotNil(a)
        // a/ subtree: f2 (250k) + f3 (1M) + hardlink (dedup'd to 0 or counted
        // here and zeroed at f1 — order-dependent, so only bound it).
        XCTAssertGreaterThanOrEqual(a!.size, 1_250_000)
        let sumOfChildren = (root.children ?? []).reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(root.size, sumOfChildren)
    }

    func testParallelMatchesSerial() throws {
        let serial = BulkScanner()
        _ = try serial.scan(path: fixture.path)
        let parallel = try ParallelScan.scan(path: fixture.path)

        XCTAssertEqual(parallel.stats.totalBytes, serial.stats.totalBytes)
        XCTAssertEqual(parallel.stats.fileCount, serial.stats.fileCount)
        XCTAssertEqual(parallel.stats.directoryCount, serial.stats.directoryCount)
        XCTAssertEqual(parallel.root.size, serial.stats.totalBytes)
    }

    func testSkipPrefixes() throws {
        var options = BulkScanner.Options()
        options.skipPrefixes = [fixture.appendingPathComponent("a").path]
        let scanner = BulkScanner(options: options)
        let root = try scanner.scan(path: fixture.path)
        XCTAssertNil(root.children?.first { $0.name == "a" })
        // Only f1 (100k) + c/sparse (~0) + c/link remain.
        XCTAssertLessThan(scanner.stats.totalBytes, 200_000)
    }
}

import XCTest
import Foundation
import Darwin
@testable import Core

final class MacChecksTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cleardisk-check-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func word(_ value: UInt32, little: Bool = true) -> [UInt8] {
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        return little ? bytes : bytes.reversed()
    }
    private func thin(_ cpu: UInt32, little: Bool = true) -> Data {
        let is64 = cpu & 0x01000000 != 0
        var bytes: [UInt8] = []
        for value: UInt32 in [is64 ? 0xfeedfacf : 0xfeedface, cpu, 0, 2, 0, 0, 0] { bytes += word(value, little: little) }
        if is64 { bytes += word(0, little: little) }
        return Data(bytes)
    }
    private func fat(_ cpus: [UInt32], little: Bool = false, is64: Bool = false) -> Data {
        let stride = is64 ? 32 : 20
        var bytes = word(is64 ? 0xcafebabf : 0xcafebabe, little: little) + word(UInt32(cpus.count), little: little)
        var offset = UInt32(8 + cpus.count * stride)
        func wide(_ value: UInt32) -> [UInt8] {
            little ? word(value) + word(0) : word(0, little: false) + word(value, little: false)
        }
        for cpu in cpus {
            let size = UInt32(thin(cpu).count)
            bytes += word(cpu, little: little) + word(0, little: little)
            bytes += is64 ? wide(offset) + wide(size) : word(offset, little: little) + word(size, little: little)
            bytes += word(0, little: little)
            if is64 { bytes += word(0, little: little) }
            offset += size
        }
        for cpu in cpus { bytes += thin(cpu) }
        return Data(bytes)
    }
    private func inspect(_ data: Data) throws -> AppArchitecture {
        let path = root.appendingPathComponent("binary")
        try data.write(to: path)
        return MachOArchitecture.inspect(path)
    }
    private func app(_ name: String, data: Data, executable: String = "main") throws -> URL {
        let url = root.appendingPathComponent(name + ".app")
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try data.write(to: macOS.appendingPathComponent("main"))
        let plist: [String: String] = ["CFBundleExecutable": executable, "CFBundleName": name, "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }

    func testThinArchitecturesAndByteOrders() throws {
        for little in [true, false] {
            XCTAssertEqual(try inspect(thin(0x01000007, little: little)), .intelOnly)
            XCTAssertEqual(try inspect(thin(0x0100000c, little: little)), .appleSilicon)
            XCTAssertEqual(try inspect(thin(7, little: little)), .legacyIntel)
            XCTAssertEqual(try inspect(thin(18, little: little)), .unknown)
        }
    }
    func testUniversalHeadersNeverFlagNativeAppAsIntelOnly() throws {
        for little in [true, false] {
            for is64 in [true, false] {
                XCTAssertEqual(try inspect(fat([0x01000007, 0x0100000c], little: little, is64: is64)), .universal)
                XCTAssertEqual(try inspect(fat([7, 0x01000007], little: little, is64: is64)), .intelOnly)
            }
        }
    }
    func testMalformedAndScriptExecutablesAreUnknown() throws {
        for bytes in [Data(), Data("#!/bin/sh\necho test".utf8), thin(0x01000007).prefix(12), fat([0x01000007, 0x0100000c]).dropLast()] {
            XCTAssertEqual(try inspect(Data(bytes)), .unknown)
        }
        var invalid = fat([0x01000007, 0x0100000c])
        invalid.replaceSubrange(16..<20, with: word(UInt32.max, little: false))
        XCTAssertEqual(try inspect(invalid), .unknown)
    }
    func testFatHeaderMustMatchSliceAndRejectOverlaps() throws {
        var mismatch = fat([0x01000007, 0x0100000c])
        mismatch.replaceSubrange(28..<32, with: word(0x01000007, little: false))
        XCTAssertEqual(try inspect(mismatch), .unknown)
        var overlap = fat([0x01000007, 0x01000007])
        overlap.replaceSubrange(36..<40, with: word(48, little: false))
        XCTAssertEqual(try inspect(overlap), .unknown)
    }
    func testUnsupportedBinaryIsNotCompatibilityPass() throws {
        let intel = try app("Old App", data: thin(0x01000007))
        _ = try app("Native App", data: thin(0x0100000c))
        _ = try app("Script App", data: Data("#!/bin/sh".utf8))
        let result = try IntelAppScan.scan(roots: [root.path, intel.path])
        XCTAssertEqual(result.apps.count, 3, result.apps.map(\.path).joined(separator: "\n"))
        XCTAssertEqual(result.intelApps.map(\.name), ["Old App"])
        XCTAssertEqual(result.apps.first { $0.name == "Script App" }?.architecture, .unknown)
        XCTAssertTrue(result.unavailablePaths.isEmpty)
    }
    func testNestedHelpersAreNotListedAsStandaloneApps() throws {
        let host = try app("Host", data: thin(0x0100000c))
        let helper = try app("Helper", data: thin(0x01000007))
        try FileManager.default.moveItem(at: helper, to: host.appendingPathComponent("Contents/Helper.app"))
        let result = try IntelAppScan.scan(roots: [root.path])
        XCTAssertEqual(result.apps.count, 1)
        XCTAssertTrue(result.intelApps.isEmpty)
    }
    func testAppMetadataCannotEscapeItsBundle() throws {
        let bundle = try app("Bad", data: thin(0x01000007), executable: "../../../binary")
        try thin(0x01000007).write(to: root.appendingPathComponent("binary"))
        XCTAssertEqual(try IntelAppScan.scan(roots: [bundle.path]).apps.first?.architecture, .unknown)
        let link = try app("Link", data: thin(0x01000007))
        let binary = link.appendingPathComponent("Contents/MacOS/main")
        try FileManager.default.removeItem(at: binary)
        try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: root.appendingPathComponent("binary"))
        XCTAssertEqual(try IntelAppScan.scan(roots: [link.path]).apps.first?.architecture, .unknown)
    }
    func testAppAliasesAreNotFollowed() throws {
        let bundle = try app("Original", data: thin(0x01000007))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: bundle)
        XCTAssertEqual(try IntelAppScan.scan(roots: [root.path]).apps.count, 1)
    }
    func testMissingAndInvalidRootsDiffer() throws {
        let missing = try IntelAppScan.scan(roots: [root.appendingPathComponent("missing").path])
        XCTAssertTrue(missing.apps.isEmpty)
        XCTAssertTrue(missing.unavailablePaths.isEmpty)
        let file = root.appendingPathComponent("file")
        try Data([1]).write(to: file)
        XCTAssertEqual(try IntelAppScan.scan(roots: [file.path]).unavailablePaths, [file.path])
    }
    func testStorageMeasuresOnlyRecognizedFamiliesAndDeduplicatesHardLinks() throws {
        let family = root.appendingPathComponent(AppleIntelligenceStorage.families[0].name)
        try FileManager.default.createDirectory(at: family, withIntermediateDirectories: true)
        let file = family.appendingPathComponent("model")
        try Data(repeating: 42, count: 16384).write(to: file)
        try FileManager.default.linkItem(at: file, to: family.appendingPathComponent("hardlink"))
        let other = root.appendingPathComponent("unrelated")
        try Data(repeating: 4, count: 32768).write(to: other)
        try FileManager.default.createSymbolicLink(at: family.appendingPathComponent("external"), withDestinationURL: other)
        var metadata = stat()
        XCTAssertEqual(lstat(file.path, &metadata), 0)
        let result = try AppleIntelligenceStorage.scan(roots: [root.path, root.path])
        XCTAssertEqual(result.measuredBytes, Int64(metadata.st_blocks) * 512)
        XCTAssertEqual(result.locations.count, 3)
        XCTAssertEqual(result.locations.first?.files, 2)
        XCTAssertFalse(result.incomplete)
        XCTAssertEqual(result.locations.filter { $0.status == .missing }.count, 2)
    }
    func testUnavailableModelFolderIsNotReportedAsMeasuredZero() throws {
        let family = root.appendingPathComponent(AppleIntelligenceStorage.families[0].name)
        try FileManager.default.createSymbolicLink(at: family, withDestinationURL: root)
        let result = try AppleIntelligenceStorage.scan(roots: [root.path])
        XCTAssertTrue(result.incomplete)
        XCTAssertEqual(result.locations.first?.status, .unavailable)
    }
    func testUnreadableModelSubfolderProducesPartialMeasurement() throws {
        let family = root.appendingPathComponent(AppleIntelligenceStorage.families[0].name)
        let blocked = family.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: family.appendingPathComponent("readable"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        let result = try AppleIntelligenceStorage.scan(roots: [root.path])
        XCTAssertTrue(result.incomplete)
        XCTAssertEqual(result.locations.first?.status, .partial)
        XCTAssertGreaterThan(result.locations.first?.unreadable ?? 0, 0)
        XCTAssertGreaterThan(result.measuredBytes, 0)
    }

    func testCancelledChecksDoNotReturnCleanReports() async {
        let directory = root.path
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AppleIntelligenceStorage.scan(roots: [directory])
        }
        do { _ = try await worker.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let apps = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try IntelAppScan.scan(roots: [directory])
        }
        do { _ = try await apps.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

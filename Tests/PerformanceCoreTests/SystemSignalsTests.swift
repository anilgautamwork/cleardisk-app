import XCTest
@testable import PerformanceCore

final class SystemSignalsTests: XCTestCase {
    func testMappings() {
        XCTAssertEqual(Pressure(sysctlLevel: 1), .normal)
        XCTAssertEqual(Pressure(sysctlLevel: 2), .elevated)
        XCTAssertEqual(Pressure(sysctlLevel: 4), .critical)
        XCTAssertEqual(Pressure(sysctlLevel: 9), .normal)
        XCTAssertEqual(Thermal(.nominal), .normal)
        XCTAssertEqual(Thermal(.fair), .warm)
        XCTAssertEqual(Thermal(.serious), .hot)
        XCTAssertEqual(Thermal(.critical), .veryHot)
    }

    func testCPULoad() {
        XCTAssertEqual(SystemSignals.cpuLoad(totalPercent: 800, cores: 16), 50)
        XCTAssertEqual(SystemSignals.cpuLoad(totalPercent: 4000, cores: 16), 100)
    }

    func testLiveRead() {
        let s = SignalReader.read(totalCPUPercent: 100)
        XCTAssertGreaterThan(s.coreCount, 0)
        XCTAssertGreaterThan(s.diskTotalBytes, 0)
        XCTAssertGreaterThan(s.uptime, 0)
        XCTAssertGreaterThan(s.memoryTotalBytes, 0)
    }

    func testFormat() {
        XCTAssertEqual(Format.percent(246.4), "246%")
        XCTAssertTrue(Format.bytes(1_800_000_000).hasSuffix("GB"))
        XCTAssertEqual(Format.bytes(0), "0 KB")
        // Disks are sold in decimal units: a "1 TB" Mac reports 994,662,584,320 bytes.
        XCTAssertEqual(Format.storage(994_662_584_320), "995 GB")
        XCTAssertEqual(Format.storage(2_000_000_000_000), "2 TB")
    }
}

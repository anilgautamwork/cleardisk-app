import XCTest
@testable import PerformanceCore

final class UsageTests: XCTestCase {
    let gb: Int64 = 1 << 30

    func rec(_ minute: Int, cpu: Double = 20, pressure: Int = 0, swap: Int64 = 0) -> MinuteRecord {
        MinuteRecord(t: minute, cpu: cpu, cpuMax: cpu, pressure: pressure, swap: swap, memUsed: 8 << 30, n: 4)
    }

    /// `count` minutes starting at minute 0 (spans 2+ UTC days when count > 1440).
    func records(_ count: Int, _ f: (Int) -> MinuteRecord) -> [MinuteRecord] { (0..<count).map(f) }

    func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testAggregatorEmitsOnMinuteChange() {
        var a = MinuteAggregator()
        let m0 = Date(timeIntervalSince1970: 600)
        XCTAssertNil(a.add(cpuLoad: 10, pressure: .normal, swap: 1, memUsed: 5, at: m0))
        XCTAssertNil(a.add(cpuLoad: 50, pressure: .elevated, swap: 2, memUsed: 6, at: m0 + 20))
        XCTAssertNil(a.add(cpuLoad: 30, pressure: .normal, swap: 3, memUsed: 7, at: m0 + 40))
        let r = a.add(cpuLoad: 90, pressure: .normal, swap: 4, memUsed: 8, at: m0 + 61)
        XCTAssertEqual(r, MinuteRecord(t: 10, cpu: 30, cpuMax: 50, pressure: 1, swap: 3, memUsed: 7, n: 3))
    }

    func testStoreRoundTripAcrossDays() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(directory: dir)
        try store.append(rec(1430))
        try store.append(rec(1450))
        let day2 = dir.appendingPathComponent("usage-1970-01-02.jsonl")
        let h = try FileHandle(forWritingTo: day2)
        h.seekToEndOfFile()
        h.write(Data("not json\n".utf8))
        try h.close()
        XCTAssertEqual(store.load(since: Date(timeIntervalSince1970: 0)).map(\.t), [1430, 1450])
        XCTAssertEqual(store.load(since: Date(timeIntervalSince1970: 1440 * 60)).map(\.t), [1450])
    }

    func testPruneAndClear() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = UsageStore(directory: dir)
        let now = Date(timeIntervalSince1970: 40 * 86400)
        try store.append(rec(Int(now.timeIntervalSince1970 / 60) - 31 * 1440))
        try store.append(rec(Int(now.timeIntervalSince1970 / 60) - 1440))
        try store.prune(olderThanDays: 30, now: now)
        XCTAssertEqual(store.load(since: .distantPast).count, 1)
        try store.clear()
        XCTAssertEqual(store.load(since: .distantPast).count, 0)
    }

    func testNotEnoughData() {
        XCTAssertEqual(UpgradeAdvisor.evaluate(records: records(600) { self.rec($0) }, memoryBytes: 16 * gb, diskFreeShare: 0.5),
                       .notEnoughData(hoursMeasured: 10))
    }

    func testMemoryBottleneckByPressure() {
        let r = records(2000) { self.rec($0, pressure: $0 % 5 == 0 ? 1 : 0) }
        guard case .bottlenecks(let b, _) = UpgradeAdvisor.evaluate(records: r, memoryBytes: 16 * gb, diskFreeShare: 0.5),
              case .memory(let gbRec, let share) = b.first else { return XCTFail("expected memory bottleneck") }
        XCTAssertEqual(gbRec, 32)
        XCTAssertEqual(share, 0.2, accuracy: 0.01)
    }

    func testMemoryBottleneckBySwap() {
        let r = records(2000) { self.rec($0, swap: 5 * self.gb) }
        guard case .bottlenecks(let b, _) = UpgradeAdvisor.evaluate(records: r, memoryBytes: 16 * gb, diskFreeShare: 0.5),
              case .memory = b.first else { return XCTFail("expected memory bottleneck") }
    }

    func testCPUBottleneck() {
        let r = records(2000) { self.rec($0, cpu: $0 % 4 == 0 ? 95 : 20) }
        XCTAssertEqual(UpgradeAdvisor.evaluate(records: r, memoryBytes: 16 * gb, diskFreeShare: 0.5),
                       .bottlenecks([.cpu(busyShare: 0.25)], hoursMeasured: 33))
    }

    func testStorage() {
        XCTAssertEqual(UpgradeAdvisor.evaluate(records: records(2000) { self.rec($0) }, memoryBytes: 16 * gb, diskFreeShare: 0.1),
                       .bottlenecks([.storage(freeShare: 0.1)], hoursMeasured: 33))
    }

    func testHealthy() {
        XCTAssertEqual(UpgradeAdvisor.evaluate(records: records(2000) { self.rec($0) }, memoryBytes: 16 * gb, diskFreeShare: 0.5),
                       .healthy(hoursMeasured: 33))
    }

    func testRecommendedMemory() {
        XCTAssertEqual([8, 16, 18, 24, 128, 256].map { UpgradeAdvisor.recommendedMemoryGB(current: $0) }, [16, 32, 36, 48, 256, 256])
    }

    func testParseSystemProfiler() throws {
        let m = try XCTUnwrap(MacInfo.parse(systemProfilerJSON: Data(#"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","chip_type":"Apple M4 Max","physical_memory":"128 GB"}]}"#.utf8)))
        XCTAssertEqual(m, MacInfo(name: "MacBook Pro", chip: "Apple M4 Max", memoryBytes: 128 << 30, isAppleSilicon: true))
        let intel = try XCTUnwrap(MacInfo.parse(systemProfilerJSON: Data(#"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","cpu_type":"Quad-Core Intel Core i7","physical_memory":"16 GB"}]}"#.utf8)))
        XCTAssertFalse(intel.isAppleSilicon)
        XCTAssertEqual(intel.chip, "Quad-Core Intel Core i7")
        XCTAssertNil(MacInfo.parse(systemProfilerJSON: Data("{}".utf8)))
    }

    func testBucketsByHour() {
        let r = records(120) { m in self.rec(m, cpu: m < 60 ? 10 : 30, pressure: m >= 90 ? 1 : 0, swap: Int64(m)) }
        let b = UsageBuckets.bucket(r, minutes: 60)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0], UsageBucket(start: Date(timeIntervalSince1970: 0), cpu: 10, pressureShare: 0, swap: 59, minutes: 60))
        XCTAssertEqual(b[1].cpu, 30)
        XCTAssertEqual(b[1].pressureShare, 0.5)
        XCTAssertEqual(b[1].start, Date(timeIntervalSince1970: 3600))
        XCTAssertTrue(UsageBuckets.bucket([], minutes: 60).isEmpty)
    }

    func testLiveMemoryStats() {
        let m = MemoryStats.read()
        XCTAssertEqual(m.total, Int64(ProcessInfo.processInfo.physicalMemory))
        XCTAssertLessThanOrEqual(m.used, m.total)
        XCTAssertGreaterThan(m.used, 0)
    }
}

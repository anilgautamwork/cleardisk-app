import XCTest
@testable import PerformanceCore

final class CPUMeterTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1000)

    func s(_ pid: Int32, _ cpu: TimeInterval, path: String = "/a", ps: Double = 7, rss: Int64 = 100) -> ProcessSample {
        ProcessSample(pid: pid, ppid: 1, uid: 501, user: "mac", cpuTime: cpu, rssBytes: rss, psCPU: ps, path: path)
    }

    func testDeltaCPU() {
        let u = CPUMeter.usage(previous: Snapshot(takenAt: t0, processes: [s(10, 10)]),
                               current: Snapshot(takenAt: t0 + 2, processes: [s(10, 12)]), footprint: { _ in nil })
        XCTAssertEqual(u[0].cpuPercent, 100, accuracy: 0.01)
    }

    func testFirstSampleUsesPsCPU() {
        let u = CPUMeter.usage(previous: nil, current: Snapshot(takenAt: t0, processes: [s(10, 5)]), footprint: { _ in nil })
        XCTAssertEqual(u[0].cpuPercent, 7)
    }

    func testPidReuseTreatedAsNew() {
        let u = CPUMeter.usage(previous: Snapshot(takenAt: t0, processes: [s(10, 50, path: "/a")]),
                               current: Snapshot(takenAt: t0 + 2, processes: [s(10, 1, path: "/b")]), footprint: { _ in nil })
        XCTAssertEqual(u[0].cpuPercent, 7)
    }

    func testCPUNeverNegative() {
        let u = CPUMeter.usage(previous: Snapshot(takenAt: t0, processes: [s(10, 50)]),
                               current: Snapshot(takenAt: t0 + 2, processes: [s(10, 49)]), footprint: { _ in nil })
        XCTAssertGreaterThanOrEqual(u[0].cpuPercent, 0)
    }

    func testMemoryPrefersFootprint() {
        let cur = Snapshot(takenAt: t0, processes: [s(10, 1), s(11, 1)])
        let u = CPUMeter.usage(previous: nil, current: cur, footprint: { $0 == 10 ? 5 : nil })
        XCTAssertEqual(u.first { $0.pid == 10 }?.memoryBytes, 5)
        XCTAssertEqual(u.first { $0.pid == 11 }?.memoryBytes, 100)
    }

    func testOwnFootprintIsReadable() {
        XCTAssertNotNil(MemoryReader.footprint(pid: getpid()))
    }
}

import XCTest
@testable import PerformanceCore

extension ProcessGroup {
    static func fixture(id: String, cpu: Double, mem: Int64 = 10, name: String? = nil, appPath: String? = nil,
                        quittable: Bool = false, helpers: Int = 0, path: String? = nil, uid: UInt32 = 501) -> ProcessGroup {
        let display = name ?? id
        let primary = ProcessUsage(pid: 1, ppid: 1, uid: uid, user: "mac", path: path ?? "/x/\(display)", name: display,
                                   cpuPercent: cpu, memoryBytes: mem)
        let extra = (0..<helpers).map { i in
            ProcessUsage(pid: Int32(100 + i), ppid: 1, uid: uid, user: "mac", path: "/x/helper", name: "helper",
                         cpuPercent: 0, memoryBytes: 0)
        }
        return ProcessGroup(id: id, displayName: display, appPath: appPath, members: [primary] + extra,
                            cpuPercent: cpu, memoryBytes: mem, quittable: quittable)
    }
}

final class AppGrouperTests: XCTestCase {
    let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/154/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

    func u(_ pid: Int32, _ path: String, cpu: Double, mem: Int64 = 10, uid: UInt32 = 501) -> ProcessUsage {
        ProcessUsage(pid: pid, ppid: 1, uid: uid, user: "mac", path: path,
                     name: URL(fileURLWithPath: path).lastPathComponent, cpuPercent: cpu, memoryBytes: mem)
    }

    func testOutermostApp() {
        XCTAssertEqual(AppGrouper.outermostApp(in: chromeHelper), "/Applications/Google Chrome.app")
        XCTAssertNil(AppGrouper.outermostApp(in: "/usr/libexec/duetexpertd"))
        XCTAssertNil(AppGrouper.outermostApp(in: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"))
    }

    func testGroupsHelpersUnderApp() {
        let g = AppGrouper.group([u(1, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 10, mem: 100),
                                  u(2, chromeHelper, cpu: 20, mem: 200), u(3, chromeHelper, cpu: 5, mem: 50),
                                  u(4, "/usr/libexec/duetexpertd", cpu: 67)], currentUID: 501)
        XCTAssertEqual(g.map(\.displayName), ["duetexpertd", "Google Chrome"])
        XCTAssertEqual(g[1].helperCount, 2)
        XCTAssertEqual(g[1].cpuPercent, 35)
        XCTAssertEqual(g[1].memoryBytes, 350)
        XCTAssertEqual(g[1].primary.pid, 1)
        XCTAssertTrue(g[1].quittable)
        XCTAssertFalse(g[0].quittable)
        XCTAssertEqual(g[0].id, "pid:4")
    }

    func testRealFixtureGroupsChrome() throws {
        let usages = CPUMeter.usage(previous: nil, current: Snapshot(takenAt: Date(), processes: PSParser.parse(try fixture("ps-sample.txt"))),
                                    footprint: { _ in nil })
        let chrome = try XCTUnwrap(AppGrouper.group(usages, currentUID: 501).first { $0.displayName == "Google Chrome" })
        XCTAssertGreaterThan(chrome.helperCount, 5)
    }

    func testSmootherCountsMissingAsZero() {
        let a = ProcessGroup.fixture(id: "A", cpu: 90), spike = ProcessGroup.fixture(id: "B", cpu: 300)
        // History keeps only id → CPU, not whole groups, to stay light in memory.
        let avg = Smoother.average(latest: [a, spike], history: [["A": 90], ["A": 90], Smoother.cpuByID([a, spike])])
        XCTAssertEqual(avg.first { $0.id == "A" }?.cpuPercent, 90)
        XCTAssertEqual(avg.first { $0.id == "B" }?.cpuPercent, 100)
        XCTAssertEqual(avg.map(\.id), ["B", "A"], "busiest first")
    }

    func testSamplingIntervals() {
        XCTAssertEqual(SamplingPolicy.interval(windowVisible: true, menuOpen: false, lowPower: false), .seconds(3))
        XCTAssertEqual(SamplingPolicy.interval(windowVisible: false, menuOpen: true, lowPower: false), .seconds(3))
        XCTAssertEqual(SamplingPolicy.interval(windowVisible: false, menuOpen: false, lowPower: false), .seconds(30))
        XCTAssertEqual(SamplingPolicy.interval(windowVisible: false, menuOpen: false, lowPower: true), .seconds(60))
        XCTAssertEqual(SamplingPolicy.interval(windowVisible: true, menuOpen: false, lowPower: true), .seconds(3))
    }
}

final class SafetyGateTests: XCTestCase {
    func testDenyList() {
        for n in ["kernel_task", "WindowServer", "launchd", "loginwindow", "Dock", "Finder", "SystemUIServer", "ControlCenter", "ClearDisk"] {
            XCTAssertFalse(SafetyGate.canQuit(uid: 501, currentUID: 501, path: "/Applications/\(n).app/Contents/MacOS/\(n)",
                                              name: n, isRegularApp: true), n)
        }
    }

    func testSystemPathsAndOtherUsersRefused() {
        for p in ["/System/Applications/Notes.app/Contents/MacOS/Notes", "/usr/bin/x", "/sbin/x", "/bin/x"] {
            XCTAssertFalse(SafetyGate.canQuit(uid: 501, currentUID: 501, path: p, name: "x", isRegularApp: true), p)
        }
        XCTAssertFalse(SafetyGate.canQuit(uid: 0, currentUID: 501, path: "/Applications/A.app/Contents/MacOS/A", name: "A", isRegularApp: true))
        XCTAssertFalse(SafetyGate.canQuit(uid: 501, currentUID: 501, path: "/Applications/A.app/Contents/MacOS/A", name: "A", isRegularApp: false))
        XCTAssertTrue(SafetyGate.canQuit(uid: 501, currentUID: 501, path: "/Applications/A.app/Contents/MacOS/A", name: "A", isRegularApp: true))
    }
}

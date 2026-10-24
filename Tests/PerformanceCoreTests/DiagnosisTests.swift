import XCTest
@testable import PerformanceCore

final class DiagnosisTests: XCTestCase {
    let catalog = try! ProcessCatalog.bundled()
    let now = Date(timeIntervalSince1970: 2_000_000)
    let gb: Int64 = 1 << 30

    func sig(thermal: Thermal = .normal, pressure: Pressure = .normal, swap: Int64 = 0,
             free: Int64 = 400 << 30, uptime: TimeInterval = 3600) -> SystemSignals {
        SystemSignals(cpuLoadPercent: 20, coreCount: 10, pressure: pressure, swapUsedBytes: swap, thermal: thermal,
                      diskFreeBytes: free, diskTotalBytes: 500 << 30, uptime: uptime, memoryTotalBytes: 16 << 30)
    }

    func chrome(cpu: Double = 24, mem: Int64 = 1_700_000_000) -> ProcessGroup {
        .fixture(id: "/Applications/Google Chrome.app", cpu: cpu, mem: mem, name: "Google Chrome",
                 appPath: "/Applications/Google Chrome.app", quittable: true, helpers: 38,
                 path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    }

    func diagnose(_ s: SystemSignals? = nil, _ groups: [ProcessGroup] = [], busySince: Date? = nil,
             lowPower: Bool = false, stuck: String? = nil) -> DiagnosisResult {
        Diagnosis.run(DiagnosisInput(signals: s ?? sig(), groups: groups, spotlightBusySince: busySince,
                                     lowPowerMode: lowPower, stuckApp: stuck, now: now), catalog: catalog)
    }

    func testQuietWhenNothing() {
        let r = diagnose()
        XCTAssertEqual(r.status, .quiet)
        XCTAssertTrue(r.findings.isEmpty)
        XCTAssertNil(r.hero)
        XCTAssertTrue(r.more.isEmpty)
    }

    func testHeatWarmIsLowBusy() {
        let r = diagnose(sig(thermal: .warm))
        XCTAssertEqual(r.hero?.kind, .heat)
        XCTAssertEqual(r.hero?.severity, .low)
        XCTAssertEqual(r.hero?.headline, "Your Mac is warm, so macOS is slowing it slightly to cool down.")
        XCTAssertEqual(r.status, .busy)
    }

    func testHeatHotIsStruggling() {
        let r = diagnose(sig(thermal: .hot))
        XCTAssertEqual(r.hero?.headline, "Your Mac is hot and slowing itself down to cool off.")
        XCTAssertEqual(r.hero?.severity, .high)
        XCTAssertEqual(r.status, .struggling)
        XCTAssertEqual(diagnose(sig(thermal: .veryHot)).hero?.severity, .critical)
    }

    func testMemoryElevatedPicksLargestQuittable() {
        let small = ProcessGroup.fixture(id: "A", cpu: 1, mem: 2 * gb, name: "Slack", appPath: "/Applications/Slack.app", quittable: true)
        let big = ProcessGroup.fixture(id: "B", cpu: 1, mem: 3 * gb, name: "WindowServer", quittable: false)
        let f = diagnose(sig(pressure: .elevated), [small, big]).findings.first { $0.kind == .memory }
        XCTAssertEqual(f?.headline, "Your Mac is running low on memory.")
        XCTAssertEqual(f?.severity, .medium)
        XCTAssertEqual(f?.groupID, "A")
        XCTAssertEqual(f?.primaryFix, .quitApp)
        XCTAssertEqual(diagnose(sig(pressure: .critical), [small]).findings.first { $0.kind == .memory }?.severity, .high)
    }

    func testSwapOver4GBTriggersMemory() {
        XCTAssertEqual(diagnose(sig(swap: 5 * gb)).hero?.kind, .memory)
        XCTAssertNil(diagnose(sig(swap: 3 * gb)).hero)
    }

    func testSpotlightNotDoubleCounted() {
        let r = diagnose(sig(), [.fixture(id: "pid:9", cpu: 246, name: "mds_stores", path: "/System/Library/mds_stores", uid: 0)])
        XCTAssertEqual(r.findings.map(\.kind), [.spotlight])
        XCTAssertEqual(r.hero?.headline, "Spotlight is doing a lot of work.")
        XCTAssertEqual(r.hero?.severity, .low)
        XCTAssertEqual(r.hero?.primaryFix, .openSpotlightSettings)
        XCTAssertEqual(r.hero?.leaveNote, "Settles on its own")
    }

    func testSpotlightStuckOffersRebuild() {
        let r = diagnose(sig(), [.fixture(id: "pid:9", cpu: 120, name: "mds_stores", uid: 0)],
                    busySince: now.addingTimeInterval(-3 * 3600 - 1))
        XCTAssertEqual(r.hero?.severity, .high)
        XCTAssertEqual(r.hero?.primaryFix, .rebuildSpotlightIndex)
    }

    func testPhotosLeaveNote() {
        let r = diagnose(sig(), [.fixture(id: "pid:5", cpu: 20, name: "photoanalysisd"), .fixture(id: "pid:6", cpu: 15, name: "mediaanalysisd")])
        XCTAssertEqual(r.findings.map(\.kind), [.photos])
        XCTAssertEqual(r.hero?.headline, "Photos is analyzing your library.")
        XCTAssertEqual(r.hero?.leaveNote, "Runs while plugged in")
    }

    func testWindowServer() {
        let r = diagnose(sig(), [.fixture(id: "pid:405", cpu: 45, name: "WindowServer")])
        XCTAssertEqual(r.findings.map(\.kind), [.windowServer])
        XCTAssertEqual(r.hero?.headline, "WindowServer is busy drawing your screen.")
        XCTAssertEqual(r.hero?.severity, .medium)
        XCTAssertEqual(r.hero?.primaryFix, .explain)
    }

    func testBrowserHeadline() {
        let r = diagnose(sig(), [chrome()])
        XCTAssertEqual(r.findings.map(\.kind), [.browser])
        XCTAssertTrue(r.hero!.headline.hasPrefix("Google Chrome and 38 helpers are using 24% CPU and"), r.hero!.headline)
        XCTAssertEqual(r.hero?.primaryFix, .reviewTabs)
        XCTAssertTrue(diagnose(sig(), [chrome(cpu: 10, mem: 500_000_000)]).findings.isEmpty)
    }

    func testCPUHogSeverities() {
        let xcode = ProcessGroup.fixture(id: "/Applications/Xcode.app", cpu: 120, name: "Xcode", appPath: "/Applications/Xcode.app",
                                         quittable: true, path: "/Applications/Xcode.app/Contents/MacOS/Xcode")
        let r = diagnose(sig(), [xcode])
        XCTAssertEqual(r.hero?.kind, .cpuHog)
        XCTAssertEqual(r.hero?.headline, "Xcode is using 120% CPU.")
        XCTAssertEqual(r.hero?.severity, .medium)
        XCTAssertEqual(r.hero?.primaryFix, .quitApp)
        var hot = xcode
        hot.cpuPercent = 250
        XCTAssertEqual(diagnose(sig(), [hot]).hero?.severity, .high)
        XCTAssertEqual(diagnose(sig(), [.fixture(id: "pid:3", cpu: 90, name: "duetexpertd", path: "/usr/libexec/duetexpertd")]).hero?.primaryFix, .explain)
    }

    func testHighCPUScalesWithCores() {
        let vm = ProcessGroup.fixture(id: "pid:1", cpu: 266, name: "ffmpeg", path: "/opt/homebrew/bin/ffmpeg")
        var big = sig()
        big.coreCount = 16
        XCTAssertEqual(diagnose(big, [vm]).hero?.severity, .medium)
        var small = sig()
        small.coreCount = 8
        XCTAssertEqual(diagnose(small, [vm]).hero?.severity, .high)
    }

    func testLowDisk() {
        let r = diagnose(sig(free: 10 << 30))
        XCTAssertEqual(r.hero?.kind, .lowDisk)
        XCTAssertEqual(r.hero?.headline, "Your disk is almost full.")
        XCTAssertTrue(r.hero!.detail.hasPrefix("Only "))
        XCTAssertEqual(r.hero?.severity, .high)
        XCTAssertEqual(r.hero?.primaryFix, .openClearDisk)
    }

    func testDiskGettingFullIsMedium() {
        let r = diagnose(sig(free: 40 << 30))
        XCTAssertEqual(r.hero?.kind, .lowDisk)
        XCTAssertEqual(r.hero?.headline, "Your disk is getting full.")
        XCTAssertEqual(r.hero?.severity, .medium)
    }

    func testPlentyFreeOnBigDiskIsQuiet() {
        // 99 GB free of 994 GB is under 10% but nowhere near slowing macOS down.
        var s = sig(free: 99_215_134_178)
        s.diskTotalBytes = 994_662_584_320
        XCTAssertNil(diagnose(s).hero)
    }

    func testVirtualMachineNamesHostApp() {
        let vm = ProcessGroup.fixture(id: "pid:40793", cpu: 146, name: "com.apple.Virtualization.VirtualMachine",
                                      path: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine")
        let docker = ProcessGroup.fixture(id: "/Applications/Docker.app", cpu: 3, name: "Docker", appPath: "/Applications/Docker.app",
                                          quittable: true, path: "/Applications/Docker.app/Contents/MacOS/Docker Desktop")
        let r = diagnose(sig(), [vm, docker])
        XCTAssertEqual(r.hero?.headline, "A virtual machine is using 146% CPU.")
        XCTAssertEqual(r.hero?.detail, "It's run by Docker. Quitting Docker frees all of it.")
        XCTAssertEqual(r.hero?.groupID, "/Applications/Docker.app")
        XCTAssertEqual(r.hero?.primaryFix, .quitApp)
        let alone = diagnose(sig(), [vm])
        XCTAssertEqual(alone.hero?.headline, "A virtual machine is using 146% CPU.")
        XCTAssertEqual(alone.hero?.primaryFix, .explain)
    }

    func testLongUptime() {
        let r = diagnose(sig(swap: 3 * gb, uptime: 15 * 86400))
        XCTAssertEqual(r.hero?.headline, "Your Mac hasn't restarted in 15 days.")
        XCTAssertEqual(r.hero?.severity, .low)
        XCTAssertEqual(r.hero?.primaryFix, .restartMac)
    }

    func testLowPower() {
        let r = diagnose(lowPower: true)
        XCTAssertEqual(r.findings.map(\.kind), [.lowPower])
        XCTAssertEqual(r.hero?.headline, "Low Power Mode is on, so your Mac runs slower to save energy.")
        XCTAssertEqual(r.hero?.primaryFix, .openBatterySettings)
    }

    func testStuckAppIsStruggling() {
        let r = diagnose(stuck: "Xcode")
        XCTAssertEqual(r.hero?.headline, "Xcode won't quit. Restart your Mac to clear it.")
        XCTAssertEqual(r.status, .struggling)
        XCTAssertEqual(r.hero?.primaryFix, .restartMac)
    }

    func testStuckAppClearsOnceGone() {
        let xcode = ProcessGroup.fixture(id: "/Applications/Xcode.app", cpu: 1, name: "Xcode", appPath: "/Applications/Xcode.app")
        XCTAssertTrue(Diagnosis.isRunning(app: "Xcode", in: [xcode]))
        XCTAssertFalse(Diagnosis.isRunning(app: "Xcode", in: []))
    }

    func testRankingAndMoreCap() {
        let groups: [ProcessGroup] = [
            .fixture(id: "pid:9", cpu: 120, name: "mds_stores"),
            .fixture(id: "pid:5", cpu: 40, name: "photoanalysisd"),
            .fixture(id: "pid:405", cpu: 45, name: "WindowServer"),
            .fixture(id: "/Applications/Xcode.app", cpu: 150, name: "Xcode", appPath: "/Applications/Xcode.app", quittable: true),
        ]
        let r = diagnose(sig(thermal: .hot, pressure: .elevated, free: 10 << 30), groups, lowPower: true)
        XCTAssertGreaterThanOrEqual(r.findings.count, 7)
        XCTAssertEqual(r.hero?.severity, .high)
        XCTAssertEqual(r.more.count, 4)
        XCTAssertEqual(r.findings.map(\.severity), r.findings.map(\.severity).sorted(by: >))
    }
}

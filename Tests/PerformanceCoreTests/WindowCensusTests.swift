import XCTest
@testable import PerformanceCore

final class WindowCensusTests: XCTestCase {
    func w(_ owner: String, _ pid: Int32, layer: Int = 0, onscreen: Bool = true) -> [String: Any] {
        ["kCGWindowOwnerName": owner, "kCGWindowOwnerPID": pid, "kCGWindowLayer": layer, "kCGWindowIsOnscreen": onscreen]
    }

    func testCountFiltersLayerAndSorts() {
        let info = [w("Google Chrome", 1), w("Google Chrome", 1), w("Google Chrome", 1), w("Dock", 2, layer: 20),
                    w("Notes", 3), w("Notes", 3, onscreen: false)]
        XCTAssertEqual(WindowCensus.count(windowInfo: info),
                       [WindowCount(ownerName: "Google Chrome", ownerPID: 1, count: 3), WindowCount(ownerName: "Notes", ownerPID: 3, count: 1)])
    }

    func testLiveCensusDoesNotCrash() {
        _ = WindowCensus.live()
        XCTAssertGreaterThan(WindowCensus.displays().count, 0)
    }
}

final class SpotlightAdvisorTests: XCTestCase {
    func testHeavyFolders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let dd = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Proj")
        try FileManager.default.createDirectory(at: dd, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 2_000_000).write(to: dd.appendingPathComponent("big.o"))
        let found = SpotlightAdvisor.heavyFolders(home: home, minimumBytes: 1_000_000)
        XCTAssertEqual(found.map(\.label), ["Xcode build data"])
        XCTAssertGreaterThanOrEqual(found[0].bytes, 2_000_000)
    }

    func testNoSandboxedAppContainers() {
        // Reading a sandboxed app's container raises macOS's "access data from other apps" prompt.
        XCTAssertFalse(SpotlightAdvisor.candidates.contains { $0.relativePath == "Library/Containers/com.utmapp.UTM" })
    }

    func testBusyTracker() {
        let t0 = Date(timeIntervalSince1970: 100)
        var t = BusyTracker()
        XCTAssertEqual(t.update(spotlightCPU: 60, now: t0), t0)
        XCTAssertEqual(t.update(spotlightCPU: 70, now: t0 + 10), t0)
        XCTAssertNil(t.update(spotlightCPU: 10, now: t0 + 20))
    }
}

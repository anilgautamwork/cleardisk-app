import XCTest
@testable import PerformanceCore

final class ReportTests: XCTestCase {
    func testRenderContainsHeroAndRows() throws {
        let catalog = try ProcessCatalog.bundled()
        let chrome = ProcessGroup.fixture(id: "/Applications/Google Chrome.app", cpu: 24, mem: 1_700_000_000, name: "Google Chrome",
                                          appPath: "/Applications/Google Chrome.app", quittable: true, helpers: 38,
                                          path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        let mds = ProcessGroup.fixture(id: "pid:9", cpu: 246, name: "mds_stores", path: "/System/Library/mds_stores", uid: 0)
        let signals = SystemSignals(cpuLoadPercent: 68, thermal: .warm)
        let result = Diagnosis.run(DiagnosisInput(signals: signals, groups: [mds, chrome], spotlightBusySince: nil,
                                                  lowPowerMode: false, stuckApp: nil, now: Date()), catalog: catalog)
        let text = Report.render(result: result, groups: [mds, chrome], catalog: catalog, signals: signals)
        XCTAssertTrue(text.hasPrefix("Status: Busy"), text)
        XCTAssertTrue(text.contains("Cause: Google Chrome and 38 helpers"), text)
        XCTAssertTrue(text.contains("Also: Spotlight is doing a lot of work."), text)
        XCTAssertTrue(text.contains("CPU 68% · Memory Normal · Heat Warm"), text)
        XCTAssertTrue(text.split(separator: "\n").contains { $0.hasPrefix("Google Chrome (+38)") }, text)
        XCTAssertTrue(text.contains("mds_stores  246%"), text)
    }
}

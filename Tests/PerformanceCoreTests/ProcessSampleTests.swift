import XCTest
@testable import PerformanceCore

final class ProcessSampleTests: XCTestCase {
    func testParsesRealSample() throws {
        let rows = PSParser.parse(try fixture("ps-sample.txt"))
        XCTAssertGreaterThan(rows.count, 500)
        let helper = try XCTUnwrap(rows.first { $0.name == "Google Chrome Helper (Renderer)" })
        XCTAssertTrue(helper.path.hasPrefix("/Applications/Google Chrome.app/"))
    }

    func testCPUTimeFormats() throws {
        XCTAssertEqual(try XCTUnwrap(PSParser.cpuSeconds("0:00.17")), 0.17, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PSParser.cpuSeconds("590:13.92")), 35413.92, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PSParser.cpuSeconds("1:02:03.50")), 3723.5, accuracy: 0.001)
        XCTAssertNil(PSParser.cpuSeconds("abc"))
    }

    func testParsesSpacesAndSkipsGarbage() {
        let text = "   12     1   501 mac   0:01.50   2048   3.5 /Applications/My App.app/Contents/MacOS/My App\nnot a row\n\n"
        XCTAssertEqual(PSParser.parse(text), [ProcessSample(pid: 12, ppid: 1, uid: 501, user: "mac", cpuTime: 1.5,
            rssBytes: 2048 * 1024, psCPU: 3.5, path: "/Applications/My App.app/Contents/MacOS/My App")])
    }

    func testLiveSourceReturnsProcesses() throws {
        XCTAssertGreaterThan(try PSProcessSource().sample().processes.count, 50)
    }
}
